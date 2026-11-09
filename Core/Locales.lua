-- Chaînes de l'interface. Le français est la langue de référence ;
-- une clé absente renvoie la clé elle-même, ce qui évite toute erreur à l'affichage.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, cle) return cle end })
ns.L = L

L.AIDE_TITRE = "Compagnons — commandes"
L.AIDE_DEBUG = "/cpg debug : active ou coupe les messages de debug"
L.AIDE_JOURNAL = "/cpg journal [n] : affiche les n dernières lignes du journal"
L.AIDE_PERSO = "/cpg perso : métiers et recettes scannés pour ce personnage"
L.AIDE_DIAG = "/cpg diag : diagnostic du client (à lancer avec une fenêtre de métier ouverte)"

L.DEBUG_ON = "Debug activé."
L.DEBUG_OFF = "Debug désactivé."
L.JOURNAL_VIDE = "Le journal est vide."
L.PERSO_AUCUN = "Aucun métier scanné. Ouvre une fenêtre de métier pour lancer le scan."
L.SCAN_OK = "%s : %d recettes apprises enregistrées."
