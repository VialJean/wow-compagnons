-- FICHIER GÉNÉRÉ par l'outil Compagnons.Recettes (dépôt wow-compagnons-services).
-- Ne pas éditer à la main : relancer l'outil après chaque patch du jeu.
--
-- Format prévu :
--   metiers[skillLineID] = { nom = "...", ordre = { spellID, spellID, ... } }
--     `ordre` fixe l'indice de chaque recette dans le bitset du métier.
--   recettes[spellID] = {
--     metier = skillLineID, indice = n, niveau = 300,
--     seuils = { orange, jaune, vert, gris },
--     objet = itemID, qte = 1,
--     composants = { { itemID, qte }, ... },
--   }
local _, ns = ...

ns.Recettes = {
	build = nil,   -- ex. "1.60.1.70685"
	genere = nil,  -- date de génération
	metiers = {},
	recettes = {},
}
