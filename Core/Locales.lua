-- Textes de l'interface, selon la langue du client.
--
-- Locales/enUS.lua est la langue de référence : toutes les clés y figurent. Les autres langues (Locales/frFR.lua…)
-- ne portent que leurs traductions ; une clé absente retombe sur l'anglais, et une clé inconnue renvoie la clé elle-même,
-- ce qui évite toute erreur à l'affichage.
--
-- Ajouter une langue : créer Locales/<langue>.lua sur le modèle de frFR.lua, l'ajouter au .toc avant ce fichier.
-- tests/locales_spec.lua vérifie les clés et les %s / %d de chaque langue.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, cle) return cle end })
ns.L = L

--- Remplit L : l'anglais d'abord, puis la langue demandée par-dessus.
function ns.chargerTextes(textes, langue)
	textes = textes or {}
	for cle, valeur in pairs(textes.enUS or {}) do L[cle] = valeur end
	if langue ~= "enUS" then
		for cle, valeur in pairs(textes[langue] or {}) do L[cle] = valeur end
	end
	ns.langue = langue
end

ns.chargerTextes(ns.Textes, GetLocale and GetLocale() or "enUS")
