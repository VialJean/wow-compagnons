-- Observation des événements du jeu (phase 0 de docs/livraison.md) : formatage et tampon circulaire, en Lua pur.
-- Le module Modules/Observateur.lua l'alimente avec les événements réels d'échange, de courrier et de fabrication.
local _, ns = ...

local Observation = {}
ns.Observation = Observation

local MAX_TEXTE = 80

--- Texte court d'une valeur : les tables et les fonctions ne sont pas détaillées, les longues chaînes sont coupées.
function Observation.texte(valeur)
	local genre = type(valeur)
	local s
	if genre == "table" then
		return "{...}"
	elseif genre == "function" then
		return "<fonction>"
	elseif genre == "nil" then
		return "nil"
	else
		s = tostring(valeur)
	end
	s = s:gsub("[\r\n]+", " ")
	if #s > MAX_TEXTE then s = s:sub(1, MAX_TEXTE) .. "…" end
	return s
end

--- « EVENEMENT arg1 arg2 … » : les arguments `nil` en fin de liste sont conservés (le nombre compte).
function Observation.ligne(evenement, ...)
	local n = select("#", ...)
	if n == 0 then return evenement end
	local morceaux = {}
	for i = 1, n do morceaux[i] = Observation.texte((select(i, ...))) end
	return evenement .. " " .. table.concat(morceaux, " ")
end

--- Ajoute { t, texte } au tampon et ne garde que les `capacite` dernières entrées.
function Observation.ajouter(tampon, capacite, t, texte)
	tampon[#tampon + 1] = { t, texte }
	while #tampon > capacite do table.remove(tampon, 1) end
end

--- Les `n` dernières lignes, de la plus ancienne à la plus récente, sous forme « HH:MM:SS texte ».
function Observation.dernieres(tampon, n, formatHeure)
	local debut = math.max(1, #tampon - n + 1)
	local lignes = {}
	for i = debut, #tampon do
		local e = tampon[i]
		lignes[#lignes + 1] = (formatHeure and formatHeure(e[1]) or tostring(e[1])) .. " " .. e[2]
	end
	return lignes
end

return Observation
