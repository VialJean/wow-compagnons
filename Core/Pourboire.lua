-- Pourboires : une somme que le client promet au crafteur en plus des composants. Lua pur, sans API WoW.
--
-- L'addon ne verse rien : le pourboire est une promesse affichée sur la commande, que le client remet lui-même
-- (échange ou courrier, avec l'assistant de remise habituel). Il est fixé à la création et ne change plus ;
-- pour le modifier, on annule la commande et on en publie une autre. Montants en cuivre.
local _, ns = ...

local Pourboire = {}
ns.Pourboire = Pourboire

Pourboire.MAX = 100000 * 10000 -- 100 000 po : même plafond que les prix
Pourboire.PART = 0.10          -- part suggérée du coût des composants

--- Montant valide (entier de cuivre entre 0 et MAX), ou nil.
function Pourboire.normaliser(n)
	if type(n) ~= "number" or n ~= n or n < 0 or n > Pourboire.MAX then return nil end
	return math.floor(n)
end

--- Pourboire suggéré pour un coût de composants (cuivre) : 10 %, arrondi à l'argent supérieur, au moins 1 pa.
-- 0 si le coût est inconnu ou nul : on ne suggère rien sans prix.
function Pourboire.suggere(cout)
	if type(cout) ~= "number" or cout <= 0 then return 0 end
	local brut = math.ceil(cout * Pourboire.PART / 100) * 100
	return math.min(Pourboire.MAX, math.max(100, brut))
end

--- Montant composé d'or, d'argent et de cuivre saisis (nil comptent pour 0).
function Pourboire.composer(or_, argent, cuivre)
	local total = (tonumber(or_) or 0) * 10000 + (tonumber(argent) or 0) * 100 + (tonumber(cuivre) or 0)
	return Pourboire.normaliser(total) or 0
end

return Pourboire
