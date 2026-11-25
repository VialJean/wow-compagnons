-- Historique des commandes : une trace locale des commandes terminées ou annulées, gardée après l'oubli de 7 jours du
-- protocole. Lua pur, sans API WoW. Format dans docs/protocole.md (`global.historique`).
--
--   historique = { entree, ... }   -- dans l'ordre d'archivage
--   entree = { id, spell, qte, client, crafteur, cree, fin, issue, pourboire }
--     issue : "terminee" | "annulee" | "sansconfirmation" (livrée, jamais confirmée, oubliée après 7 jours)
--
-- L'historique est local : chacun archive ce que sa copie a vu, les compteurs peuvent différer d'un joueur à l'autre.
local _, ns = ...

local Historique = {}
ns.Historique = Historique

Historique.MAX = 500                  -- entrées gardées
Historique.DUREE = 180 * 24 * 3600    -- âge maximal d'une entrée

local function present(historique, id)
	for _, e in ipairs(historique) do
		if e.id == id then return true end
	end
	return false
end

--- Archive une commande si elle a une issue (terminée ou annulée). `oubli` : la commande va être oubliée ; une commande
-- livrée sans confirmation est alors archivée « sans confirmation ». Renvoie vrai si une entrée a été ajoutée.
function Historique.archiver(historique, c, oubli)
	local issue
	if c.statut == "terminee" or c.statut == "annulee" then
		issue = c.statut
	elseif c.statut == "livree" and oubli then
		issue = "sansconfirmation"
	else
		return false
	end
	if present(historique, c.id) then return false end
	historique[#historique + 1] = {
		id = c.id, spell = c.spell, qte = c.qte, client = c.client, crafteur = c.assigne,
		cree = c.cree, fin = c.maj, issue = issue, pourboire = c.pourboire,
	}
	return true
end

--- Archive toutes les commandes finales d'une table { [id] = commande }. Renvoie le nombre d'entrées ajoutées.
function Historique.balayer(historique, commandes)
	local n = 0
	for _, c in pairs(commandes) do
		if Historique.archiver(historique, c, false) then n = n + 1 end
	end
	return n
end

--- Retire les entrées trop anciennes, puis les plus anciennes au-delà de MAX. Renvoie le nombre d'entrées retirées.
function Historique.purger(historique, maintenant)
	table.sort(historique, function(a, b)
		if a.fin ~= b.fin then return a.fin < b.fin end
		return a.id < b.id
	end)
	local avant = #historique
	local gardees = {}
	for _, e in ipairs(historique) do
		if maintenant - e.fin <= Historique.DUREE then gardees[#gardees + 1] = e end
	end
	local debut = math.max(1, #gardees - Historique.MAX + 1)
	for i = #historique, 1, -1 do historique[i] = nil end
	for i = debut, #gardees do historique[#historique + 1] = gardees[i] end
	return avant - #historique
end

--- Compteurs par membre : { [clé] = { craftees, passees } }. Une commande est « craftée » pour son crafteur et « passée »
-- pour son client quand elle a abouti (terminée, ou livrée sans confirmation) ; une annulation ne compte pour personne.
function Historique.compteurs(historique)
	local c = {}
	local function de(cle)
		if not c[cle] then c[cle] = { craftees = 0, passees = 0 } end
		return c[cle]
	end
	for _, e in ipairs(historique) do
		if e.issue ~= "annulee" then
			de(e.client).passees = de(e.client).passees + 1
			if e.crafteur then de(e.crafteur).craftees = de(e.crafteur).craftees + 1 end
		end
	end
	return c
end

--- Entrées filtrées, les plus récentes d'abord. options : membre (client ou crafteur), metier (skillLineID), texte,
-- donnees (ns.Recettes), normaliser (fonction de normalisation des textes).
function Historique.liste(historique, options)
	options = options or {}
	local donnees = options.donnees
	local norme = options.normaliser or function(t) return (t or ""):lower() end
	local texte = norme(options.texte or "")
	local liste = {}
	for _, e in ipairs(historique) do
		local garde = true
		if options.membre and e.client ~= options.membre and e.crafteur ~= options.membre then garde = false end
		local recette = donnees and donnees.recettes and donnees.recettes[e.spell]
		if garde and options.metier and (not recette or recette.metier ~= options.metier) then garde = false end
		if garde and texte ~= "" then
			local nom = recette and norme(recette.nom or "") or ""
			garde = nom:find(texte, 1, true) ~= nil
		end
		if garde then liste[#liste + 1] = e end
	end
	table.sort(liste, function(a, b)
		if a.fin ~= b.fin then return a.fin > b.fin end
		return a.id < b.id
	end)
	return liste
end

return Historique
