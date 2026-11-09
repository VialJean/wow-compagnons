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

Chaque message est `{ genre, charge }` avant codage ; `charge.v` porte la version du protocole (actuellement **2**),
un message d'une autre version est ignoré. La version 2 ajoute les commandes et change le format de `HASHES`
et de `PROFILE_REQ`.

| Type | Canal | Charge | Rôle |
|---|---|---|---|
| `HELLO` | GUILD | `{ v, h, n }` | annonce : hash global (profils et commandes) et nombre de profils |
| `PRET` | WHISPER | `{ v, h }` | un pair dont le hash diffère se propose (minuscule) |
| `HASHES` | WHISPER | `{ v, liste = { p = { [cle] = { maj, hash } }, c = { [id] = { rev, maj, par, hash } } } }` | l'annonceur envoie ses listes au premier pair prêt |
| `PROFILE_REQ` | WHISPER | `{ v, cles = {...}, ids = {...} }` | profils et commandes demandés (400 au plus de chaque) |
| `PROFILE` | WHISPER | `{ v, profil }` | un profil transmis pendant une synchro |
| `ORDER` | WHISPER | `{ v, commande }` | une commande transmise pendant une synchro |
| `PROFILE_UPD` | GUILD | `{ v, profil }` | un personnage vient d'être scanné |
| `ORDER_NEW` | GUILD | `{ v, commande }` | une commande vient d'être créée |
| `ORDER_UPD` | GUILD | `{ v, commande }` | une commande vient de changer d'état |

### Déroulement

1. **Connexion** : le client diffuse `HELLO` avec son hash global (somme de contrôle des listes triées `clé:hash`
   des profils et des commandes).
2. **Pairs identiques** (même hash) : aucune réponse. **Pairs différents** : après un délai aléatoire (0 à 2 s), un `PRET`
   minuscule, une seule fois pour un couple d'états donné.
3. **L'annonceur garde le premier `PRET`** (fenêtre de 20 s) et lui envoie `HASHES`. Les autres `PRET` sont ignorés.
4. **Le partenaire compare** les deux listes : il demande (`PROFILE_REQ`) ce qui est meilleur chez l'annonceur
   et lui envoie (`PROFILE`, `ORDER`) ce qui est meilleur chez lui, ou ce qui manque à l'autre.
5. **Propagation** : tout profil ou toute commande reçu par `PROFILE` ou `ORDER` provoque une nouvelle annonce `HELLO`
   (regroupée sur 5 s), ce qui permet aux autres pairs de se synchroniser à leur tour. Elle s'arrête quand tout le
   monde est identique.
6. **En ligne** : `PROFILE_UPD`, `ORDER_NEW` et `ORDER_UPD` sont diffusés à toute la guilde ; ils ne déclenchent
   pas de nouvelle annonce.

### Commandes

Une commande est un instantané complet, avec un numéro de révision `rev` (une révision par transition) :

```lua
{ id = "Prénom Nom#1731180062#1", client = "Prénom Nom", spell = 2329, qte = 5,
  crafteur = nil,            -- crafteur désigné, ou nil : ouvert à tous
  mats = "partie",           -- "tout" | "partie" | "crafteur" : qui fournit les composants
  note = "",                 -- 120 caractères au plus
  statut = "ouverte",        -- ouverte | prise | mats | terminee | annulee
  assigne = nil,             -- crafteur qui a pris la commande
  rev = 0, cree = 1731180062, maj = 1731180062, par = "Prénom Nom",
  histo = { { t, par, statut } } }   -- dix dernières transitions
```

Cycle de vie : `ouverte` → `prise` → `mats` (mats reçus) → `terminee`. Le crafteur peut **libérer** (retour à `ouverte`),
le client peut **annuler** tant que la commande n'est pas finale.

| Action | Depuis | Qui |
|---|---|---|
| prendre | ouverte | n'importe quel membre, ou seulement le crafteur désigné |
| mats | prise | le crafteur assigné |
| terminer | prise, mats | le crafteur assigné |
| libérer | prise, mats | le crafteur assigné |
| annuler | ouverte, prise, mats | le client |

### Règles

- **Profils : plus récent gagne.** On compare `maj`, puis le hash (le plus grand) pour départager de façon déterministe.
- **Commandes : plus de révisions gagne.** À révision égale (deux crafteurs qui prennent en même temps), l'action la plus
  ancienne l'emporte (`maj`), puis l'ordre alphabétique de l'auteur (`par`), puis le hash : tous les clients tranchent pareil.
- **Droits vérifiés à la réception.** Quand la copie reçue a une révision de plus que la nôtre, la transition doit être
  permise à son auteur (tableau ci-dessus), sinon elle est refusée. Une annulation ne vaut que de la main du client,
  une prise ou une avancée que de celle du crafteur assigné.
- **Un personnage ne se laisse pas écraser** : un profil reçu pour l'un de nos personnages est ignoré.
- **Rien n'est cru sur parole** : les hashes du réseau sont recalculés ; profils et commandes sont validés (tailles
  maximales, recette connue de la base, cohérence des états) et les messages invalides sont ignorés.
- **Oubli** : une commande terminée ou annulée depuis plus de 7 jours disparaît chez tous, et n'est pas réimportée.
  Au plus 600 commandes sont gardées.
- **Présence en ligne** : lue dans la liste de guilde du jeu, pas dans le protocole.

Le comportement est vérifié hors jeu par `tests/synchro_spec.lua` (2 à 50 clients simulés, connexions, scans et
commandes aléatoires, latence, messages forgés) : tous les clients convergent vers le même état.
