-- Profil d'un personnage tel qu'il circule entre les membres de la guilde.
-- Lua pur, sans API WoW.
--
--   profil = {
--     cle = "Prénom Nom", nom = "Prénom Nom", prenom = "Prénom", classe = "SHAMAN",
--     maj = 1731180062,                        -- horodatage du dernier scan, sert à départager
--     metiers = { [171] = { niveau = 60, max = 75, bits = "<bitset des recettes>" } },
--     hash = 123456,                           -- somme de contrôle du contenu (recalculée à la réception)
--   }
local _, ns = ...

local Profil = {}
ns.Profil = Profil

local MAX_CLE = 64
local MAX_METIERS = 20
local MAX_BITS = 1024

local byte, format = string.byte, string.format

--- Somme de contrôle Adler-32 (arithmétique exacte, sans opérateurs binaires).
local function adler(texte)
	local a, b = 1, 0
	for i = 1, #texte do
		a = (a + byte(texte, i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end
Profil.adler = adler

local function hex(bits)
	local t = {}
	for i = 1, #bits do t[i] = format("%02x", byte(bits, i)) end
	return table.concat(t)
end

--- Hash du contenu d'un profil (indépendant de l'ordre de parcours des tables).
function Profil.hash(p)
	local ids = {}
	for id in pairs(p.metiers or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	local morceaux = { p.cle, p.nom or "", p.prenom or "", p.classe or "", tostring(p.maj) }
	for _, id in ipairs(ids) do
		local m = p.metiers[id]
		morceaux[#morceaux + 1] = format("%d:%d:%d:%s", id, m.niveau or 0, m.max or 0, hex(m.bits or ""))
	end
	return adler(table.concat(morceaux, "\n"))
end

--- Identifie le métier de la base correspondant à un métier scanné (par id, sinon par nom).
function Profil.idMetier(donnees, metier, cleStockage)
	if metier.id and donnees.metiers[metier.id] then return metier.id end
	if type(cleStockage) == "number" and donnees.metiers[cleStockage] then return cleStockage end
	local voulu = ns.Catalogue.normaliser(metier.nom or (type(cleStockage) == "string" and cleStockage) or "")
	if voulu == "" then return nil end
	for id, m in pairs(donnees.metiers) do
		if ns.Catalogue.normaliser(m.nom) == voulu then return id end
	end
	return nil
end

--- Construit le profil d'un personnage scanné localement.
function Profil.dePersonnage(cle, perso, donnees)
	local metiers = {}
	for cleMetier, metier in pairs(perso.metiers or {}) do
		local id = Profil.idMetier(donnees, metier, cleMetier)
		local base = id and donnees.metiers[id]
		if base then
			local ensemble = {}
			for _, spellID in ipairs(metier.recettes or {}) do
				local r = donnees.recettes[spellID]
				if r and r.metier == id then ensemble[r.indice] = true end
			end
			metiers[id] = {
				niveau = metier.niveau or 0,
				max = metier.max or 0,
				bits = ns.Bitset.encoder(ensemble, #base.ordre),
			}
		end
	end
	local p = {
		cle = cle,
		nom = perso.nom or cle,
		prenom = perso.prenom,
		classe = perso.classe,
		maj = perso.maj or 0,
		metiers = metiers,
	}
	p.hash = Profil.hash(p)
	return p
end

--- Valide et normalise un profil reçu du réseau. Renvoie nil s'il est inutilisable.
-- Le hash annoncé n'est jamais cru : il est recalculé.
function Profil.valider(brut, donnees)
	if type(brut) ~= "table" then return nil end
	local cle = brut.cle
	if type(cle) ~= "string" or cle == "" or #cle > MAX_CLE then return nil end
	if type(brut.maj) ~= "number" or brut.maj < 0 or brut.maj ~= brut.maj then return nil end
	if type(brut.metiers) ~= "table" then return nil end

	local metiers, n = {}, 0
	for id, m in pairs(brut.metiers) do
		if type(id) == "number" and type(m) == "table" and donnees.metiers[id] then
			n = n + 1
			if n > MAX_METIERS then return nil end
			local bits = m.bits
			if type(bits) ~= "string" or #bits > MAX_BITS then return nil end
			metiers[id] = {
				niveau = tonumber(m.niveau) or 0,
				max = tonumber(m.max) or 0,
				bits = bits,
			}
		end
	end

	local function texte(v) return type(v) == "string" and v:sub(1, MAX_CLE) or nil end
	local p = {
		cle = cle,
		nom = texte(brut.nom) or cle,
		prenom = texte(brut.prenom),
		classe = texte(brut.classe),
		maj = brut.maj,
		metiers = metiers,
	}
	p.hash = Profil.hash(p)
	return p
end

--- Vrai si `a` doit remplacer `b` : plus récent, puis plus grand hash à égalité (déterministe).
function Profil.plusRecent(a, b)
	if a.maj ~= b.maj then return a.maj > b.maj end
	return a.hash > b.hash
end

--- Recettes connues d'un profil : { [skillLineID] = { spellID, ... } }.
function Profil.recettes(p, donnees)
	local resultat = {}
	for id, m in pairs(p.metiers) do
		local base = donnees.metiers[id]
		if base then
			local liste = {}
			for indice in pairs(ns.Bitset.decoder(m.bits)) do
				local spellID = base.ordre[indice]
				if spellID and donnees.recettes[spellID] then liste[#liste + 1] = spellID end
			end
			table.sort(liste)
			resultat[id] = liste
		end
	end
	return resultat
end

return Profil
