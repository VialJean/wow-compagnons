-- Ensemble d'indices encodé en chaîne d'octets : 8 indices par octet,
-- le bit de poids faible correspond au plus petit indice.
-- Sert à transmettre les recettes connues d'un métier : l'indice est la position
-- de la recette dans la liste ordonnée du métier (Data/Recettes.lua), identique chez tous les clients.
--
-- Lua pur, sans la bibliothèque `bit` de WoW, pour être testable hors du jeu.
-- La chaîne produite peut contenir l'octet 0 : elle doit passer par
-- LibDeflate:EncodeForWoWAddonChannel avant tout envoi sur le canal addon.
local _, ns = ...

local floor, ceil = math.floor, math.ceil
local char, byte = string.char, string.byte
local unpack = unpack or table.unpack

local Bitset = {}
ns.Bitset = Bitset

local function bitActif(valeur, rang)
	return floor(valeur / 2 ^ rang) % 2 == 1
end

--- Encode un ensemble { [indice] = true } d'indices compris entre 1 et taille.
-- Les indices hors bornes sont ignorés.
function Bitset.encoder(ensemble, taille)
	local octets = {}
	for i = 1, ceil(taille / 8) do octets[i] = 0 end
	for indice in pairs(ensemble) do
		if indice >= 1 and indice <= taille then
			local o = floor((indice - 1) / 8) + 1
			local rang = (indice - 1) % 8
			if not bitActif(octets[o], rang) then
				octets[o] = octets[o] + 2 ^ rang
			end
		end
	end
	-- string.char par paquets pour rester sous la limite d'arguments de Lua.
	local morceaux = {}
	for debut = 1, #octets, 200 do
		morceaux[#morceaux + 1] = char(unpack(octets, debut, math.min(debut + 199, #octets)))
	end
	return table.concat(morceaux)
end

--- Décode une chaîne en ensemble { [indice] = true }.
function Bitset.decoder(chaine)
	local ensemble = {}
	for o = 1, #chaine do
		local valeur = byte(chaine, o)
		for rang = 0, 7 do
			if bitActif(valeur, rang) then
				ensemble[(o - 1) * 8 + rang + 1] = true
			end
		end
	end
	return ensemble
end

--- Nombre d'indices présents dans une chaîne encodée.
function Bitset.compter(chaine)
	local n = 0
	for o = 1, #chaine do
		local valeur = byte(chaine, o)
		while valeur > 0 do
			n = n + valeur % 2
			valeur = floor(valeur / 2)
		end
	end
	return n
end

return Bitset
