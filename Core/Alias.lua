-- Alias des commandes /cpg : l'anglais et le français sont acceptés, quelle que soit la langue du client.
-- Les noms internes restent ceux d'origine (français) ; ce module traduit ce que le joueur tape. Lua pur.
--   /cpg minimap, /cpg recipes, /cpg log, /cpg char, /cpg help, /cpg sync announce
--   /cpg tooltips item|reagent|nobody|disenchant|enchanter|order <ctrlshift|shift|none>
local _, ns = ...

local Alias = {}
ns.Alias = Alias

local ACTIONS = {
	recipes = "recettes", minimap = "minicarte", log = "journal", char = "perso",
	tooltips = "infobulles", help = "aide", announce = "annonce", shopping = "courses", price = "prix", warn = "avertir", reminders = "rappels",
}
local OPTIONS = {
	item = "objet", reagent = "composant", nobody = "personne",
	disenchant = "desenchantement", enchanter = "enchanteur", order = "commander",
}
local VALEURS = { ctrlshift = "ctrlmaj", shift = "maj", none = "aucune" }

local function minuscules(texte)
	return type(texte) == "string" and texte:lower() or ""
end

--- Sous-commande de /cpg (ou argument comme « announce ») : nom interne.
function Alias.action(texte)
	local t = minuscules(texte)
	return ACTIONS[t] or t
end

--- Option de /cpg tooltips : nom interne.
function Alias.option(texte)
	local t = minuscules(texte)
	return OPTIONS[t] or t
end

--- Valeur de l'option « commander » : nom interne.
function Alias.valeur(texte)
	local t = minuscules(texte)
	return VALEURS[t] or t
end

return Alias
