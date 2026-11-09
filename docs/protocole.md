# Protocole Compagnons — version 1 (brouillon)

Ce document fait foi pour le format des SavedVariables et des messages addon.
Le parseur du Relais (dépôt `wow-compagnons-services`) vérifie `schema` et refuse un format inconnu.

## SavedVariables

`CompagnonsDB` (compte, géré par AceDB) :

```lua
CompagnonsDB = {
  global = {
    schema = 1,
    personnages = {
      ["Brumefer Hautrocher"] = {   -- clé : nom complet, voir « Noms des personnages »
        nom = "Brumefer Hautrocher", prenom = "Brumefer", royaume = "Royaume",
        classe = "WARRIOR", maj = 1731180062,
        metiers = {
          [171] = {                 -- skillLineID, ou nom si l'ID est indisponible
            id = 171, nom = "Alchimie", niveau = 285, max = 300,
            recettes = { 2330, 2331, ... },   -- spellIDs appris, triés
            nbApprises = 98, nbVues = 182, scanneLe = 1731180062,
          },
        },
      },
    },
    guilde = {},      -- copie synchronisée : sprint synchro
    commandes = {},   -- sprint commandes
    diag = { sessions = 12, premiere = ..., derniere = ..., rapport = { ... } },
  },
  profiles = { ... },  -- réglages AceDB
}
```

`CompagnonsPersoDB` (par personnage) : uniquement `sessions` pour l'instant (diagnostic).

## Noms des personnages

Dans Forever, un personnage a un **prénom et un nom de famille**. Le jeu renvoie le nom de famille là où WoW
met le royaume : `UnitName("player")` donne `"Jean", "Vialjean"`, et `GetUnitName("player", true)` donne
`"Jean Vialjean"`. Le royaume réel (`GetNormalizedRealmName()`) est le même pour tous.

- La **clé** d'un personnage est son nom complet, `"Prénom Nom"`, tel qu'il apparaît dans la liste de guilde.
- `nom` : nom complet ; `prenom` : prénom seul ; `royaume` : informatif.
- Un expéditeur de message addon peut arriver sous la forme `Prénom-Nom` (comme le dossier des SavedVariables) :
  le normaliser en remplaçant le tiret par une espace avant de chercher la clé.
- Les données enregistrées sous l'ancienne clé `Prénom-Royaume` sont migrées au chargement pour le personnage courant.

## Messages addon

Préfixe `COMPAGNONS`. Charge utile : `LibSerialize` → `LibDeflate:CompressDeflate` → `LibDeflate:EncodeForWoWAddonChannel`.
Les notes saisies par les joueurs passent en texte clair via `SendAddonMessageLogged`.

| Type | Canal | Contenu |
|---|---|---|
| `HELLO` | GUILD | version, protocole, hash global, nombre de profils |
| `DIFF_REQ` | WHISPER | demande des hashes par membre |
| `DIFF` | WHISPER | liste `{ membre, hash }` |
| `PROFILE_REQ` | WHISPER | liste de membres à transmettre |
| `PROFILE` | WHISPER | profil complet : métiers, niveaux, bitsets de recettes |
| `RECIPE_ADD` | GUILD | nouvelle recette apprise |
| `ORDER_NEW` | GUILD | nouvelle commande |
| `ORDER_UPD` | GUILD | transition de statut |
| `BYE` | GUILD | déconnexion (optionnel) |

Règles de conflit : horodatage le plus ancien, puis ordre alphabétique du nom ; toute transition non autorisée est ignorée.
À détailler au sprint synchro.
