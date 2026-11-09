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

Chaque message est `{ genre, charge }` avant codage ; `charge.v` porte la version du protocole (actuellement 1),
un message d'une autre version est ignoré.

| Type | Canal | Charge | Rôle |
|---|---|---|---|
| `HELLO` | GUILD | `{ v, h, n }` | annonce : hash global et nombre de profils |
| `PRET` | WHISPER | `{ v, h }` | un pair dont le hash diffère se propose (minuscule) |
| `HASHES` | WHISPER | `{ v, liste = { [cle] = { maj, hash } } }` | l'annonceur envoie sa liste au premier pair prêt |
| `PROFILE_REQ` | WHISPER | `{ v, cles = { cle, ... } }` | profils demandés (400 au plus) |
| `PROFILE` | WHISPER | `{ v, profil }` | un profil transmis pendant une synchro |
| `PROFILE_UPD` | GUILD | `{ v, profil }` | un personnage vient d'être scanné |
| `RECIPE_ADD`, `ORDER_NEW`, `ORDER_UPD` | GUILD | | commandes : sprint suivant |

### Déroulement

1. **Connexion** : le client diffuse `HELLO` avec son hash global (somme de contrôle de la liste triée `clé:hash`).
2. **Pairs identiques** (même hash) : aucune réponse. **Pairs différents** : après un délai aléatoire (0 à 2 s), un `PRET`
   minuscule, une seule fois pour un couple d'états donné.
3. **L'annonceur garde le premier `PRET`** (fenêtre de 20 s) et lui envoie `HASHES`. Les autres `PRET` sont ignorés.
4. **Le partenaire compare** les deux listes : il demande (`PROFILE_REQ`) ce qui est plus récent chez l'annonceur
   et lui envoie (`PROFILE`) ce qui est plus récent chez lui, ou ce qui manque à l'autre.
5. **Propagation** : tout profil reçu par `PROFILE` provoque une nouvelle annonce `HELLO` (regroupée sur 5 s),
   ce qui permet aux autres pairs de se synchroniser à leur tour. Elle s'arrête quand tout le monde est identique.
6. **Scan en ligne** : `PROFILE_UPD` est diffusé à toute la guilde ; il ne déclenche pas de nouvelle annonce.

### Règles

- **Plus récent gagne** : on compare `maj`, puis le hash (le plus grand) pour départager de façon déterministe.
- **Un personnage ne se laisse pas écraser** : un profil reçu pour l'un de nos personnages est ignoré.
- **Rien n'est cru sur parole** : le hash du réseau est recalculé, les profils sont validés (clé ≤ 64 caractères,
  ≤ 20 métiers, bitset ≤ 1 024 octets, métiers connus de la base) et les messages invalides sont ignorés.
- **Présence en ligne** : lue dans la liste de guilde du jeu, pas dans le protocole.
- Transitions de commandes non autorisées : ignorées (au sprint commandes).

Le comportement est vérifié hors jeu par `tests/synchro_spec.lua` (2 à 50 clients simulés, connexions et scans
aléatoires, latence) : tous les clients convergent vers le même état.
