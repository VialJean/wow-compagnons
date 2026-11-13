-- Suggestion de crafteur (docs/v5.md, §3.1). Lua pur : la présence en ligne est fournie par l'appelant.
--
-- Parmi les personnages qui connaissent une recette, classe ceux à qui confier une commande :
--   1. en ligne d'abord (il peut la prendre tout de suite) ;
--   2. à égalité, le moins chargé (commandes « prise » ou « mats » en cours) ;
--   3. puis le niveau de métier le plus élevé ;
--   4. puis l'ordre alphabétique : un ordre total, donc stable d'un affichage à l'autre.
local _, ns = ...

local Suggestion = {}
ns.Suggestion = Suggestion

--- Nombre de commandes en cours (prises, matériaux reçus) par crafteur assigné : { [cle] = n }.
function Suggestion.charges(commandes)
	local charges = {}
	for _, o in pairs(commandes or {}) do
		if o.assigne and (o.statut == "prise" or o.statut == "mats") then
			charges[o.assigne] = (charges[o.assigne] or 0) + 1
		end
	end
	return charges
end

--- Classe les candidats `{ cle, nom, niveau }` (comme `Catalogue:Crafteurs`).
-- `enLigne(cle)` : vrai si connecté ; `charges` : résultat de `charges` ; `exclure` : ensemble de clés à écarter (mes personnages).
-- Renvoie une nouvelle liste `{ cle, nom, niveau, enLigne, enCours }`, le meilleur d'abord.
function Suggestion.classer(candidats, enLigne, charges, exclure)
	local liste = {}
	for _, c in ipairs(candidats or {}) do
		if not (exclure and exclure[c.cle]) then
			liste[#liste + 1] = {
				cle = c.cle, nom = c.nom or c.cle, niveau = c.niveau or 0,
				enLigne = enLigne and enLigne(c.cle) == true or false,
				enCours = charges and charges[c.cle] or 0,
			}
		end
	end
	table.sort(liste, function(a, b)
		if a.enLigne ~= b.enLigne then return a.enLigne end
		if a.enCours ~= b.enCours then return a.enCours < b.enCours end
		if a.niveau ~= b.niveau then return a.niveau > b.niveau end
		return a.cle < b.cle
	end)
	return liste
end

--- Le crafteur à suggérer, ou nil s'il n'y en a aucun.
function Suggestion.meilleur(candidats, enLigne, charges, exclure)
	return Suggestion.classer(candidats, enLigne, charges, exclure)[1]
end

return Suggestion
