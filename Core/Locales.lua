-- Chaînes de l'interface. Le français est la langue de référence ;
-- une clé absente renvoie la clé elle-même, ce qui évite toute erreur à l'affichage.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, cle) return cle end })
ns.L = L

L.AIDE_TITRE = "Compagnons — commandes"
L.AIDE_OUVRIR = "/cpg : ouvre ou ferme l'atelier de guilde (aussi /cpg recettes)"
L.AIDE_MINICARTE = "/cpg minicarte : masque ou réaffiche le bouton de la minicarte"
L.AIDE_DEBUG = "/cpg debug : active ou coupe les messages de debug"
L.AIDE_JOURNAL = "/cpg journal [n] : affiche les n dernières lignes du journal"
L.AIDE_PERSO = "/cpg perso : métiers et recettes scannés pour ce personnage"
L.AIDE_DIAG = "/cpg diag : diagnostic du client (à lancer avec une fenêtre de métier ouverte)"

L.DEBUG_ON = "Debug activé."
L.DEBUG_OFF = "Debug désactivé."
L.JOURNAL_VIDE = "Le journal est vide."
L.PERSO_AUCUN = "Aucun métier scanné. Ouvre une fenêtre de métier pour lancer le scan."
L.SCAN_OK = "%s : %d recettes apprises enregistrées."

-- Atelier de guilde
L.TITRE = "Compagnons — Atelier de guilde"
L.RECHERCHE = "Recette ou composant…"
L.FILTRES = "Filtres"
L.FILTRE_CRAFTABLE = "Craftable dans la guilde"
L.FILTRE_EN_LIGNE = "Crafteur en ligne"
L.FILTRE_INCONNUE = "Personne ne la connaît"
L.METIERS = "Métiers"
L.TOUS_METIERS = "Tous"
L.ONGLET_RECETTES = "Recettes"
L.ONGLET_COMMANDES = "Commandes"
L.COMMANDES_BIENTOT = "Les commandes arrivent bientôt."
L.COMMANDER = "Commander"
L.AUCUN_RESULTAT = "Aucune recette ne correspond."
L.RESULTATS = "%d résultats"
L.COMPOSANTS = "Composants"
L.PEUVENT_CRAFTER = "Peuvent la crafter"
L.PERSONNE_CONNAIT = "Personne ne la connaît encore."
L.PERSONNE = "Personne"
L.CRAFTEURS = "%d crafteurs"
L.CRAFTEURS_EN_LIGNE = "%d crafteurs · %d en ligne"
L.METIER_NIVEAU = "%s · compétence %d"
L.EN_LIGNE = "en ligne"
L.HORS_LIGNE = "hors ligne"
L.PIED = "Base de recettes du build %s · %d personnage(s) scanné(s)"

-- Minicarte
L.MINICARTE_PERSOS = "%d personnage(s) scanné(s)"
L.MINICARTE_AIDE = "Clic : ouvrir · Clic droit : masquer"
L.MINICARTE_MASQUEE = "Bouton de minicarte masqué. /cpg minicarte pour le réafficher."

-- Panneau de la fenêtre de métier
L.PANNEAU_TITRE = "Compagnons · %s"
L.SELECTIONNE_RECETTE = "Sélectionne une recette."
L.RECETTE_INCONNUE_BASE = "Recette absente de la base."
L.ET_AUTRES = "… et %d autres"
L.BILAN = "%d recettes sur %d connues dans la guilde"
L.OUVRIR_ATELIER = "Ouvrir l'atelier de guilde"
