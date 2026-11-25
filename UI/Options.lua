-- Panneau d'options : les réglages de /cpg dans les options d'interface du jeu (catégorie « Compagnons »), ouvert aussi par
-- /cpg options. Il lit et écrit les mêmes réglages que les commandes slash, qui continuent de faire foi : aucune option nouvelle.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Options = Compagnons:NewModule("Options")
ns.Options = Options

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

local function profil() return ns.db.profile end

--- Les cases à cocher, par colonne et par section : { section, { { libellé, lire, écrire }, ... } }.
local function sections()
	local function simple(groupe, cle, defaut)
		return function()
			local v = profil()[groupe][cle]
			if v == nil then return defaut == true end
			return v
		end, function(valeur) profil()[groupe][cle] = valeur end
	end
	local function ligne(libelle, groupe, cle, defaut)
		local lire, ecrire = simple(groupe, cle, defaut)
		return { libelle, lire, ecrire }
	end
	return {
		{
			{ L.OPT_GENERAL, {
				{ L.OPT_MINICARTE,
					function() return not profil().minimap.hide end,
					function(valeur)
						-- Même effet que /cpg minimap : on ne bascule que si l'état demandé diffère.
						if valeur == profil().minimap.hide and ns.Minicarte and ns.Minicarte.Basculer then ns.Minicarte:Basculer() end
					end },
				{ L.OPT_STOCK,
					function() return profil().stock.suivi end,
					function(valeur)
						profil().stock.suivi = valeur
						if valeur and ns.Stocks and ns.Stocks.Releve then ns.Stocks:Releve() end
					end },
			} },
			{ L.OPT_RAPPELS, {
				ligne(L.OPT_RAPPELS_ACTIF, "rappels", "actif", true),
				ligne(L.OPT_RAPPELS_EXPIRATION, "rappels", "expiration", true),
			} },
			{ L.OPT_AVERTISSEMENT, {
				ligne(L.OPT_AVERTIR_SILENCE, "avertir", "silencieux", true),
				ligne(L.OPT_AVERTIR_CONNEXION, "avertir", "connexion", false),
			} },
		},
		{
			{ L.OPT_INFOBULLES, {
				ligne(L.OPT_INFO_OBJET, "infobulles", "objet", false),
				ligne(L.OPT_INFO_COUT, "infobulles", "cout", true),
				ligne(L.OPT_INFO_COMPOSANT, "infobulles", "composant", false),
				ligne(L.OPT_INFO_PERSONNE, "infobulles", "personne", false),
				ligne(L.OPT_INFO_DESENCHANTEMENT, "infobulles", "desenchantement", false),
				ligne(L.OPT_INFO_ENCHANTEUR, "infobulles", "aucunEnchanteur", false),
			} },
			{ L.OPT_LIVRAISON, {
				ligne(L.OPT_LIVRAISON_SUIVI, "livraison", "suivi", true),
				ligne(L.OPT_LIVRAISON_CONFIRMER, "livraison", "confirmer", true),
				ligne(L.OPT_LIVRAISON_AIDE, "livraison", "aide", true),
			} },
		},
	}
end

-- Raccourci « commander » des infobulles : ctrlmaj -> maj -> aucune.
local SUITE = { ctrlmaj = "maj", maj = "aucune", aucune = "ctrlmaj" }
local NOMS = function()
	return { ctrlmaj = L.OPT_TOUCHE_CTRLMAJ, maj = L.OPT_TOUCHE_MAJ, aucune = L.OPT_TOUCHE_AUCUNE }
end

function Options:Creer()
	local panneau = CreateFrame("Frame", "CompagnonsOptions")
	panneau.cases = {}

	local titre = panneau:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	titre:SetPoint("TOPLEFT", 16, -16)
	titre:SetText(L.OPT_TITRE)
	local aide = panneau:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	aide:SetPoint("TOPLEFT", titre, "BOTTOMLEFT", 0, -6)
	aide:SetText(L.OPT_AIDE)

	for c, colonne in ipairs(sections()) do
		local x = 16 + (c - 1) * 320
		local y = -76
		for _, section in ipairs(colonne) do
			local entete = panneau:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			entete:SetPoint("TOPLEFT", x, y)
			entete:SetText(section[1])
			y = y - 24
			for _, def in ipairs(section[2]) do
				local case = CreateFrame("CheckButton", nil, panneau, "UICheckButtonTemplate")
				case:SetSize(26, 26)
				case:SetPoint("TOPLEFT", x, y)
				case.texte = case:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
				case.texte:SetPoint("LEFT", case, "RIGHT", 2, 0)
				case.texte:SetText(def[1])
				case.lire, case.ecrire = def[2], def[3]
				case:SetScript("OnClick", function(b) securise("réglage", b.ecrire, b:GetChecked() and true or false) end)
				panneau.cases[#panneau.cases + 1] = case
				y = y - 26
			end
			y = y - 14
		end
		if c == 2 then
			-- Raccourci « commander » des infobulles, sous les cases de la colonne.
			local bouton = CreateFrame("Button", nil, panneau, "UIPanelButtonTemplate")
			bouton:SetSize(300, 24)
			bouton:SetPoint("TOPLEFT", x, y)
			bouton:SetScript("OnClick", function()
				local r = profil().infobulles
				r.commander = SUITE[r.commander] or "ctrlmaj"
				panneau:Actualiser()
			end)
			panneau.touche = bouton
		end
	end

	function panneau:Actualiser()
		for _, case in ipairs(self.cases) do case:SetChecked(case.lire() and true or false) end
		if self.touche then
			local nom = NOMS()[profil().infobulles.commander] or L.OPT_TOUCHE_CTRLMAJ
			self.touche:SetText(string.format(L.OPT_TOUCHE, nom))
		end
	end
	panneau:SetScript("OnShow", function(p) securise("actualisation des options", p.Actualiser, p) end)

	self.panneau = panneau
	return true
end

function Options:OnEnable()
	if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
	if not securise("création du panneau d'options", self.Creer, self) then return end
	securise("enregistrement des options", function()
		local categorie = Settings.RegisterCanvasLayoutCategory(self.panneau, "Compagnons")
		Settings.RegisterAddOnCategory(categorie)
		self.categorie = categorie
	end)
end

--- /cpg options : ouvre le panneau.
function Options:Ouvrir()
	if self.categorie and Settings and Settings.OpenToCategory then
		securise("ouverture des options", Settings.OpenToCategory, self.categorie:GetID())
	else
		Compagnons:Print(L.OPT_INDISPONIBLE)
	end
end
