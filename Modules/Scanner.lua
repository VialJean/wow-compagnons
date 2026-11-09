-- Scan des métiers : à l'ouverture d'une fenêtre de métier, enregistre le métier,
-- son niveau et les recettes apprises du personnage.
--
-- Le jeu ne donne la liste des recettes que fenêtre ouverte : un personnage
-- n'est connu de l'addon qu'après avoir ouvert chacun de ses métiers une fois.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Scanner = Compagnons:NewModule("Scanner", "AceEvent-3.0")
local TS = C_TradeSkillUI

local DELAI = 0.5 -- la liste arrive en plusieurs TRADE_SKILL_LIST_UPDATE : on regroupe
local planifie = false

function Scanner:OnEnable()
	if not TS or not TS.GetAllRecipeIDs then
		ns.log("erreur", "scan", "C_TradeSkillUI.GetAllRecipeIDs indisponible : scan désactivé")
		return
	end
	self:RegisterEvent("TRADE_SKILL_SHOW", "Planifier")
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "Planifier")
end

function Scanner:Planifier(evenement)
	if planifie then return end
	planifie = true
	ns.log("info", "scan", "%s : scan planifié", evenement)
	C_Timer.After(DELAI, function()
		planifie = false
		local ok, err = pcall(self.Analyser, self)
		if not ok then ns.log("erreur", "scan", "échec du scan : %s", tostring(err)) end
	end)
end

--- Métier affiché : { id, nom, niveau, max }. Essaie l'API moderne puis l'ancienne.
local function metierAffiche()
	if TS.GetBaseProfessionInfo then
		local info = TS.GetBaseProfessionInfo()
		if info and info.professionName and info.professionName ~= "" then
			return {
				id = info.professionID,
				nom = info.professionName,
				niveau = info.skillLevel,
				max = info.maxSkillLevel,
			}
		end
	end
	if GetTradeSkillLine then
		local nom, niveau, max = GetTradeSkillLine()
		if nom and nom ~= "UNKNOWN" then
			return { nom = nom, niveau = niveau, max = max }
		end
	end
	return nil
end

--- Vrai si la fenêtre affiche les métiers d'un autre joueur (lien, guilde, PNJ).
local function fenetreEtrangere()
	if TS.IsTradeSkillLinked and TS.IsTradeSkillLinked() then return true end
	if TS.IsTradeSkillGuild and TS.IsTradeSkillGuild() then return true end
	if TS.IsNPCCrafting and TS.IsNPCCrafting() then return true end
	return false
end

function Scanner:Analyser()
	if fenetreEtrangere() then
		ns.log("info", "scan", "fenêtre d'un autre joueur : ignorée")
		return
	end

	local metier = metierAffiche()
	if not metier then
		ns.log("warn", "scan", "métier affiché introuvable")
		return
	end

	local ids = TS.GetAllRecipeIDs()
	if not ids or #ids == 0 then
		ns.log("warn", "scan", "%s : aucune recette renvoyée (liste pas encore chargée ?)", metier.nom)
		return
	end

	local apprises, nbVues = {}, 0
	for _, id in ipairs(ids) do
		local info = TS.GetRecipeInfo(id)
		if info then
			nbVues = nbVues + 1
			if info.learned then apprises[#apprises + 1] = id end
		end
	end
	table.sort(apprises)

	local cle = ns.clePersonnage()
	local persos = ns.db.global.personnages
	local perso = persos[cle]
	if not perso then
		perso = { metiers = {} }
		persos[cle] = perso
	end
	perso.nom = UnitName("player")
	perso.royaume = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
	perso.classe = select(2, UnitClass("player"))
	perso.maj = time()

	local cleMetier = metier.id or metier.nom
	local avant = perso.metiers[cleMetier]
	perso.metiers[cleMetier] = {
		id = metier.id,
		nom = metier.nom,
		niveau = metier.niveau,
		max = metier.max,
		recettes = apprises,       -- spellIDs ; converti en bitset au moment de la synchro
		nbApprises = #apprises,
		nbVues = nbVues,           -- > nbApprises : l'API renvoie aussi les non apprises
		scanneLe = time(),
	}

	local nouvelles = #apprises - (avant and avant.nbApprises or 0)
	ns.log("info", "scan", "%s %s/%s : %d apprises, %d vues (%+d)",
		metier.nom, tostring(metier.niveau), tostring(metier.max), #apprises, nbVues, nouvelles)

	if not avant or nouvelles ~= 0 then
		Compagnons:Print(string.format(L.SCAN_OK, metier.nom, #apprises))
	end
	Compagnons:SendMessage("COMPAGNONS_METIER_SCANNE", cle, cleMetier)
end
