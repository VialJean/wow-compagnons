-- Catalogue : la base de recettes embarquée croisée avec les métiers connus des personnages.
-- Lua pur, sans API WoW, pour être testable hors du jeu.
--
-- Entrées :
--   donnees      = ns.Recettes (Data/Recettes.lua)
--   personnages  = CompagnonsDB.global.personnages
local _, ns = ...

local Catalogue = {}
Catalogue.__index = Catalogue
ns.Catalogue = Catalogue

-- Lettres accentuées françaises (UTF-8) → lettre simple. La recherche ignore casse et accents.
local ACCENTS = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
	["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae",
	["’"] = "'",
	-- espagnol, portugais, italien, allemand
	["á"] = "a", ["Á"] = "a", ["ã"] = "a", ["Ã"] = "a", ["å"] = "a", ["Å"] = "a",
	["í"] = "i", ["Í"] = "i", ["ì"] = "i", ["Ì"] = "i",
	["ó"] = "o", ["Ó"] = "o", ["ò"] = "o", ["Ò"] = "o", ["õ"] = "o", ["Õ"] = "o", ["ø"] = "o", ["Ø"] = "o",
	["ú"] = "u", ["Ú"] = "u",
	["ñ"] = "n", ["Ñ"] = "n", ["ß"] = "ss", ["ÿ"] = "y", ["ý"] = "y", ["Ý"] = "y",
}

--- Minuscules sans accents.
function Catalogue.normaliser(texte)
	if not texte or texte == "" then return "" end
	texte = texte:gsub("[\195\197\226][\128-\191]*", function(c) return ACCENTS[c] or c end)
	-- Cyrillique : majuscules (U+0410 à U+042F, plus Ё) vers minuscules ; string.lower ne touche que l'ASCII.
	texte = texte:gsub("\208([\129\144-\175])", function(b)
		local n = b:byte()
		if n == 129 then return "\209\145" end        -- Ё -> ё
		if n <= 159 then return "\208" .. string.char(n + 32) end -- А-П -> а-п
		return "\209" .. string.char(n - 32)          -- Р-Я -> р-я
	end)
	return texte:lower()
end
local normaliser = Catalogue.normaliser

--- Crée un catalogue.
-- personnages : métiers scannés sur ce compte (listes de spellIDs)
-- guilde      : profils reçus des autres membres (bitsets) ; ils sont ignorés pour nos propres personnages
function Catalogue.nouveau(donnees, personnages, guilde)
	local c = setmetatable({
		donnees = donnees or { metiers = {}, recettes = {}, objets = {} },
		recherche = {}, -- [spellID] = texte normalisé (recette + composants)
		triees = nil,   -- spellIDs triés une fois pour toutes
		connus = {},    -- [spellID] = { { cle, nom, classe, niveau }, ... }
	}, Catalogue)
	c:Actualiser(personnages, guilde)
	return c
end

local function nomMetier(donnees, id)
	local m = donnees.metiers[id]
	return m and m.nom or tostring(id)
end

--- Reconstruit l'index « recette → personnages qui la connaissent ».
function Catalogue:Actualiser(personnages, guilde)
	if personnages then self.personnages = personnages end
	if guilde then self.guilde = guilde end
	self.connus = {}

	local function ajouter(spellID, cle, nom, classe, niveau)
		local liste = self.connus[spellID]
		if not liste then
			liste = {}
			self.connus[spellID] = liste
		end
		liste[#liste + 1] = { cle = cle, nom = nom, classe = classe, niveau = niveau }
	end

	local propres = self.personnages or {}
	for cle, perso in pairs(propres) do
		for cleMetier, metier in pairs(perso.metiers or {}) do
			local id = ns.Profil.idMetier(self.donnees, metier, cleMetier)
			for _, spellID in ipairs(metier.recettes or {}) do
				local r = self.donnees.recettes[spellID]
				if r and (id == nil or r.metier == id) then
					ajouter(spellID, cle, perso.nom or cle, perso.classe, metier.niveau)
				end
			end
		end
	end

	for cle, profil in pairs(self.guilde or {}) do
		if not propres[cle] then
			for id, spells in pairs(ns.Profil.recettes(profil, self.donnees)) do
				local niveau = profil.metiers[id].niveau
				for _, spellID in ipairs(spells) do
					ajouter(spellID, cle, profil.nom or cle, profil.classe, niveau)
				end
			end
		end
	end

	for _, liste in pairs(self.connus) do
		table.sort(liste, function(a, b) return a.cle < b.cle end)
	end
end

--- Personnages qui connaissent la recette : { { cle, nom, classe, niveau }, ... }.
function Catalogue:Crafteurs(spellID)
	return self.connus[spellID] or {}
end

local function triees(self)
	if self.triees then return self.triees end
	local liste = {}
	for spellID in pairs(self.donnees.recettes) do liste[#liste + 1] = spellID end
	local d = self.donnees
	table.sort(liste, function(a, b)
		local ra, rb = d.recettes[a], d.recettes[b]
		if ra.niveau ~= rb.niveau then return ra.niveau < rb.niveau end
		local na, nb = normaliser(ra.nom), normaliser(rb.nom)
		if na ~= nb then return na < nb end
		return a < b
	end)
	self.triees = liste
	return liste
end

local function texteRecherche(self, spellID)
	local t = self.recherche[spellID]
	if t then return t end
	local r = self.donnees.recettes[spellID]
	local morceaux = { normaliser(r.nom) }
	for _, comp in ipairs(r.composants or {}) do
		local objet = self.donnees.objets and self.donnees.objets[comp[1]]
		if objet and objet[1] ~= "" then morceaux[#morceaux + 1] = normaliser(objet[1]) end
	end
	t = table.concat(morceaux, "\n")
	self.recherche[spellID] = t
	return t
end

--- Filtre les recettes.
-- options :
--   texte        chaîne cherchée dans le nom de la recette et de ses composants (tous les mots)
--   metier       skillLineID, ou nil pour tous
--   craftable    vrai : au moins un personnage la connaît
--   enLigne      vrai : au moins un personnage connecté la connaît (nécessite estEnLigne)
--   inconnue     vrai : personne ne la connaît
--   estEnLigne   fonction(cle) -> booléen
-- Renvoie la liste des spellIDs, du plus bas niveau au plus haut.
function Catalogue:Chercher(options)
	options = options or {}
	local mots = {}
	for mot in normaliser(options.texte or ""):gmatch("%S+") do mots[#mots + 1] = mot end

	local resultat = {}
	for _, spellID in ipairs(triees(self)) do
		local r = self.donnees.recettes[spellID]
		local garde = options.metier == nil or r.metier == options.metier

		if garde and #mots > 0 then
			local haystack = texteRecherche(self, spellID)
			for _, mot in ipairs(mots) do
				if not haystack:find(mot, 1, true) then
					garde = false
					break
				end
			end
		end

		if garde and (options.craftable or options.enLigne or options.inconnue) then
			local crafteurs = self.connus[spellID]
			local nb = crafteurs and #crafteurs or 0
			if options.craftable and nb == 0 then garde = false end
			if options.inconnue and nb > 0 then garde = false end
			if garde and options.enLigne then
				local present = false
				for i = 1, nb do
					if options.estEnLigne and options.estEnLigne(crafteurs[i].cle) then
						present = true
						break
					end
				end
				garde = present
			end
		end

		if garde then resultat[#resultat + 1] = spellID end
	end
	return resultat
end

--- Liste des métiers de la base : { { id, nom, total }, ... }, triée par nom.
function Catalogue:Metiers()
	local nombres = {}
	for _, r in pairs(self.donnees.recettes) do
		nombres[r.metier] = (nombres[r.metier] or 0) + 1
	end
	local liste = {}
	for id, total in pairs(nombres) do
		liste[#liste + 1] = { id = id, nom = nomMetier(self.donnees, id), total = total }
	end
	table.sort(liste, function(a, b)
		local na, nb = normaliser(a.nom), normaliser(b.nom)
		if na ~= nb then return na < nb end
		return a.id < b.id
	end)
	return liste
end

--- Index « objet → recettes », construits une fois à la première demande.
local function indexer(self)
	if self.creant then return end
	self.creant, self.utilisant = {}, {}
	for spellID, r in pairs(self.donnees.recettes) do
		if r.objet and r.objet > 0 then
			local l = self.creant[r.objet]
			if not l then l = {}; self.creant[r.objet] = l end
			l[#l + 1] = spellID
		end
		for _, comp in ipairs(r.composants or {}) do
			local l = self.utilisant[comp[1]]
			if not l then l = {}; self.utilisant[comp[1]] = l end
			l[#l + 1] = spellID
		end
	end
	for _, index in ipairs({ self.creant, self.utilisant }) do
		for _, l in pairs(index) do table.sort(l) end
	end
end

--- spellIDs des recettes qui créent l'objet.
function Catalogue:RecettesCreant(itemID)
	indexer(self)
	return self.creant[itemID] or {}
end

--- spellIDs des recettes qui consomment l'objet comme composant.
function Catalogue:RecettesUtilisant(itemID)
	indexer(self)
	return self.utilisant[itemID] or {}
end

Catalogue.ENCHANTEMENT = 333 -- skillLineID du métier Enchantement

--- Personnages qui ont le métier Enchantement, avec leur niveau : { { cle, nom, classe, niveau }, ... }.
-- Nos personnages (listes de recettes) et les profils reçus des autres membres.
function Catalogue:Enchanteurs()
	local liste = {}
	local propres = self.personnages or {}
	for cle, perso in pairs(propres) do
		for cleMetier, metier in pairs(perso.metiers or {}) do
			if ns.Profil.idMetier(self.donnees, metier, cleMetier) == Catalogue.ENCHANTEMENT then
				liste[#liste + 1] = { cle = cle, nom = perso.nom or cle, classe = perso.classe, niveau = metier.niveau or 0 }
			end
		end
	end
	for cle, profil in pairs(self.guilde or {}) do
		local m = not propres[cle] and profil.metiers and profil.metiers[Catalogue.ENCHANTEMENT]
		if m then
			liste[#liste + 1] = { cle = cle, nom = profil.nom or cle, classe = profil.classe, niveau = m.niveau or 0 }
		end
	end
	return liste
end

--- Les membres qui ont l'addon et leurs métiers : mes personnages et les profils reçus de la guilde.
-- { { cle, nom, classe, moi, metiers = { { id, nom, niveau, max, recettes }, ... } }, ... }, triée par nom ;
-- les métiers de chacun sont triés par nom. Un personnage sans métier est omis.
function Catalogue:Membres()
	local liste = {}
	local d = self.donnees
	local propres = self.personnages or {}

	local function ajouter(membre)
		table.sort(membre.metiers, function(a, b)
			local na, nb = normaliser(a.nom), normaliser(b.nom)
			if na ~= nb then return na < nb end
			return (a.id or 0) < (b.id or 0)
		end)
		if #membre.metiers > 0 then liste[#liste + 1] = membre end
	end

	for cle, perso in pairs(propres) do
		local m = { cle = cle, nom = perso.nom or cle, classe = perso.classe, moi = true, metiers = {} }
		for cleMetier, metier in pairs(perso.metiers or {}) do
			local id = ns.Profil.idMetier(d, metier, cleMetier)
			local nombre = 0
			for _, spellID in ipairs(metier.recettes or {}) do
				local r = d.recettes[spellID]
				if r and (id == nil or r.metier == id) then nombre = nombre + 1 end
			end
			m.metiers[#m.metiers + 1] = { id = id, nom = id and nomMetier(d, id) or metier.nom or tostring(cleMetier),
				niveau = metier.niveau or 0, max = metier.max or 0, recettes = nombre }
		end
		ajouter(m)
	end

	for cle, profil in pairs(self.guilde or {}) do
		if not propres[cle] then
			local m = { cle = cle, nom = profil.nom or cle, classe = profil.classe, moi = false, metiers = {} }
			local connues = ns.Profil.recettes(profil, d)
			for id, metier in pairs(profil.metiers or {}) do
				m.metiers[#m.metiers + 1] = { id = id, nom = nomMetier(d, id), niveau = metier.niveau or 0,
					max = metier.max or 0, recettes = #(connues[id] or {}) }
			end
			ajouter(m)
		end
	end

	table.sort(liste, function(a, b)
		local na, nb = normaliser(a.nom), normaliser(b.nom)
		if na ~= nb then return na < nb end
		return a.cle < b.cle
	end)
	return liste
end

--- Quantité de `itemID` consommée par la recette (0 si elle ne l'utilise pas).
function Catalogue:QuantiteComposant(spellID, itemID)
	local r = self.donnees.recettes[spellID]
	for _, comp in ipairs(r and r.composants or {}) do
		if comp[1] == itemID then return comp[2] end
	end
	return 0
end

--- Résumé des quantités de composants d'une recette : { { itemID, qte, nom, qualite }, ... }.
function Catalogue:Composants(spellID)
	local r = self.donnees.recettes[spellID]
	local liste = {}
	if not r then return liste end
	for _, comp in ipairs(r.composants or {}) do
		local objet = self.donnees.objets and self.donnees.objets[comp[1]]
		liste[#liste + 1] = {
			itemID = comp[1],
			qte = comp[2],
			nom = objet and objet[1] or "",
			qualite = objet and objet[2] or 1,
		}
	end
	return liste
end

return Catalogue
