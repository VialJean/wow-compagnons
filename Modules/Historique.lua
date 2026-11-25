-- Historique local des commandes : archive les commandes terminées ou annulées avant qu'elles disparaissent (7 jours), et purge
-- les entrées trop anciennes. Le calcul est dans Core/Historique.lua ; les commandes oubliées sans confirmation sont archivées
-- par la synchro (Core/Synchro.lua, surOubli).
local _, ns = ...
local Compagnons = ns.addon

local Historique = Compagnons:NewModule("HistoriqueModule", "AceEvent-3.0")
ns.HistoriqueModule = Historique

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "historique", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Historique:OnEnable()
	securise("purge", ns.Historique.purger, ns.db.global.historique, time())
	securise("archivage", self.Balayer, self)
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "Balayer")
	self:RegisterMessage("COMPAGNONS_COMMANDE_RECUE", "Balayer")
end

--- Archive les commandes finales de la copie locale (sans effet sur celles déjà archivées).
function Historique:Balayer()
	local n = ns.Historique.balayer(ns.db.global.historique, ns.db.global.commandes)
	if n > 0 then
		Compagnons:SendMessage("COMPAGNONS_HISTORIQUE_MAJ")
	end
end
