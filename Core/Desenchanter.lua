-- Règle d'éligibilité au désenchantement. Lua pur, sans API du jeu.
-- Les tranches viennent de Data/Desenchantement.lua (table ItemDisenchantLoot du client). Le niveau d'Enchantement
-- exigé n'y figure pas (le serveur le vérifie) : on sait si l'objet se désenchante, pas à partir de quel niveau.
local _, ns = ...

local Desenchanter = {}
ns.Desenchanter = Desenchanter

--- Tranche qui permet de désenchanter un objet, ou nil.
-- classe : 2 = arme, 4 = armure ; sous : sous-classe ; qualite : 2 à 4 ; niveau : niveau d'objet effectif.
function Desenchanter.tranche(donnees, classe, sous, qualite, niveau)
	if not donnees or type(classe) ~= "number" or type(qualite) ~= "number" or type(niveau) ~= "number" then
		return nil
	end
	local meilleure
	for _, t in ipairs(donnees.tranches or {}) do
		if t.classe == classe and t.qualite == qualite and niveau >= t.min and niveau <= t.max then
			if t.sous == sous then return t end -- une sous-classe précise l'emporte
			if t.sous == -1 then meilleure = meilleure or t end
		end
	end
	return meilleure
end

return Desenchanter
