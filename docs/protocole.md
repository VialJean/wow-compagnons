# Protocole Compagnons — version 4

Ce document fait foi pour le format des SavedVariables et des messages addon. Il décrit le **protocole de synchro, version 4**
(0.6) ; le **format des SavedVariables** a sa propre version, `schema` (1). L'historique des versions est en fin de document.
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
    annonces = {},    -- 0.6 : petites annonces de la guilde, synchronisées : [id] = annonce (voir « Petites annonces »)
    historique = {    -- 0.6 : commandes terminées ou annulées vues par cette copie, locales, jamais synchronisées
      { id = "Prénom Nom#1731180062#1", spell = 2329, qte = 5, client = "Prénom Nom", crafteur = "Prénom Nom",
        cree = 1731180062, fin = 1731200000, issue = "terminee", pourboire = 25000 },
      -- issue : terminee | annulee | sansconfirmation (livrée, jamais confirmée, oubliée après 7 jours)
      -- 500 entrées ou 180 jours au plus ; purge au chargement
    },
    favoris = { [2329] = true },  -- 0.6 : recettes favorites du compte, locales, jamais synchronisées
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

Chaque message est `{ genre, charge }` avant codage ; `charge.v` porte la version du protocole (actuellement **4**),
un message d'une autre version est ignoré (journalisé, jamais intégré, jamais répondu).

**Invariant : ne jamais changer l'enveloppe.** `{ genre, charge }`, `charge.v` numérique, et le codage `LibSerialize` →
`LibDeflate` → `EncodeForWoWAddonChannel` restent identiques d'une version à l'autre. C'est ce qui permet à une version
de lire le `v` d'un pair plus récent ou plus ancien et de le signaler au joueur, même quand tout le reste est incompatible.

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
| `PRIX` | WHISPER | `{ v, prix = { [itemID] = { p, t } } }` | prix transmis pendant une synchro (100 au plus par message) |
| `PRIX_UPD` | GUILD | `{ v, prix }` | prix qui viennent d'être relevés à l'hôtel des ventes, regroupés sur 5 s |
| `ANNONCE` | GUILD | `{ v, annonce }` | une petite annonce vient d'être publiée, modifiée, reconduite ou retirée (seul l'auteur écrit) |
| `ANNONCE_SYNC` | WHISPER | `{ v, annonce }` | une annonce transmise pendant une synchro (provoque une nouvelle annonce `HELLO`, comme `ORDER`) |

### Prix (compatible v2)

Les prix restent **hors du hash global** et gardent `v = 2` : `HELLO` porte en plus `hp` (hash des prix), `HASHES.liste.x`
un résumé `{ [itemID] = { t, p } }` et `PROFILE_REQ.px` la liste des prix demandés. Une ancienne version ignore ces champs
et les genres `PRIX` et `PRIX_UPD` : elle ne se croit jamais désynchronisée à cause des prix. Un pair n'est comparé sur
les prix que s'il annonce `hp`/`x`. Règle de fusion : le relevé le plus récent gagne, à date égale le moins cher. Un message
est validé à la réception : objet de la base, prix de 1 cuivre à 200 000 po, horodatage pas plus de 5 minutes dans le futur,
200 prix au plus, sinon le lot est ignoré.

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
  pourboire = nil,           -- promesse du client au crafteur, en cuivre (1 à 1 000 000 000), absent si nul
  statut = "ouverte",        -- ouverte | prise | mats | livree | terminee | annulee
  assigne = nil,             -- crafteur qui a pris la commande
  rev = 0, cree = 1731180062, maj = 1731180062, par = "Prénom Nom",
  histo = { { t, par, statut } } }   -- dix dernières transitions
```

Cycle de vie : `ouverte` → `prise` → `mats` (mats reçus) → `livree` (livrée, en attente de confirmation) → `terminee`.
Le crafteur **livre** ; le client **confirme** la réception (`terminee`) ou la **conteste** (retour à `prise`, même crafteur).
Si le client est aussi le crafteur assigné, la livraison termine directement la commande. Le crafteur peut **libérer** avant la
livraison (retour à `ouverte`), le client peut **annuler** tant que la commande n'est pas finale.

| Action | Depuis | Qui |
|---|---|---|
| prendre | ouverte | n'importe quel membre, ou seulement le crafteur désigné |
| mats | prise | le crafteur assigné |
| livrer | prise, mats | le crafteur assigné (la commande est `terminee` d'emblée s'il est aussi le client) |
| confirmer | livree | le client |
| contester | livree | le client (retour à `prise`, le crafteur assigné ne change pas) |
| libérer | prise, mats | le crafteur assigné |
| annuler | ouverte, prise, mats, livree | le client |
| progres | prise, mats | le crafteur assigné (nombre fabriqué, vers le haut seulement) |

### Pourboire

Une commande peut porter `pourboire`, un montant en cuivre que le client promet au crafteur. Il est **hors du
hash** de la commande : une version qui ne le connaît pas l'ignore sans se croire désynchronisée. Il est fixé à la création et ne change plus (pour le modifier, le client annule et republie). À la réception,
un montant qui n'est pas un nombre entier de cuivre entre 0 et 1 000 000 000 est ignoré (la commande reste valide, sans
pourboire). L'addon ne verse jamais rien : c'est une mention affichée, que le client remet lui-même (échange ou courrier).

### Petites annonces (protocole 4)

Une annonce est un message permanent de la guilde, en texte libre (« cherche un enchanteur pour mes bottes »).

```lua
{ id = "Prénom Nom#1731180062#1", auteur = "Prénom Nom",
  texte = "",            -- obligatoire, 200 caractères au plus, en clair
  rev = 0, maj = 1731180062,   -- révision (une par modification) et dernière reconduction
  retire = nil }         -- true : annonce retirée (la pierre tombale se propage avant d'être oubliée)
```

- **Seul l'auteur écrit.** L'identifiant commence par `auteur#`, un `ANNONCE` diffusé en direct n'est accepté que de son auteur,
  et une copie qui change l'auteur est refusée. **La révision la plus haute gagne**, puis la
  reconduction la plus récente (`maj`), puis le hash.
- **Limites** : 5 annonces actives par auteur, 400 annonces gardées. Une annonce expire **30 jours** après sa dernière
  reconduction (l'auteur reconduit les siennes à chaque connexion, ce qui compte une révision) ; une annonce retirée est
  oubliée après 7 jours. Les annonces d'un auteur absent de la liste de guilde sont purgées localement à la connexion.
- **Synchro** : le hash global (`HELLO`) comprend les annonces ; `HASHES.liste.a` = `{ [id] = { rev, maj, hash } }` ;
  `PROFILE_REQ.an` = ids demandés ; l'échange différentiel se fait par `ANNONCE_SYNC`.

### Règles

- **Profils : plus récent gagne.** On compare `maj`, puis le hash (le plus grand) pour départager de façon déterministe.
- **Commandes : plus de révisions gagne.** À révision égale (deux crafteurs qui prennent en même temps), l'action la plus
  ancienne l'emporte (`maj`), puis l'ordre alphabétique de l'auteur (`par`), puis le hash : tous les clients tranchent pareil.
- **Droits vérifiés à la réception.** Quand la copie reçue a une révision de plus que la nôtre, la transition doit être
  permise à son auteur (tableau ci-dessus), sinon elle est refusée. Une annulation, une confirmation ou une contestation ne
  valent que de la main du client ; une prise, une avancée ou une livraison que de celle du crafteur assigné : **un crafteur ne
  peut pas déclarer lui-même la commande terminée**. Une copie plus lointaine (plusieurs révisions d'avance) n'est vérifiée que
  pour sa cohérence interne : l'auteur de la dernière transition y a droit (`Commandes.valider`).
- **Un personnage ne se laisse pas écraser** : un profil reçu pour l'un de nos personnages est ignoré.
- **Rien n'est cru sur parole** : les hashes du réseau sont recalculés ; profils et commandes sont validés (tailles
  maximales, recette connue de la base, cohérence des états) et les messages invalides sont ignorés.
- **Oubli** : une commande terminée ou annulée, ou livrée sans confirmation, depuis plus de 7 jours disparaît chez tous, et
  n'est pas réimportée.
  Au plus 600 commandes sont gardées.
- **Présence en ligne** : lue dans la liste de guilde du jeu, pas dans le protocole.

Le comportement est vérifié hors jeu par `tests/synchro_spec.lua` (2 à 50 clients simulés, connexions, scans et
commandes aléatoires, latence, messages forgés) : tous les clients convergent vers le même état.

## Historique

| Protocole | Addon | Changements |
|---|---|---|
| 1 | 0.1 | profils de personnages, `HELLO` / `PRET` / `HASHES` / `PROFILE*` |
| 2 | 0.2 à 0.4 | commandes (`ORDER*`), format de `HASHES` et `PROFILE_REQ` ; prix (`PRIX*`, `hp`, `x`) et progression des fabrications ajoutés **sans** changer de version (champs facultatifs ignorés par les anciennes) |
| 3 | 0.5 | état `livree`, actions `livrer`, `confirmer`, `contester` (remplacent `terminer`) ; le client écrit désormais des transitions |
| 4 | 0.6 | petites annonces (`ANNONCE`, `ANNONCE_SYNC`, `HASHES.liste.a`, `PROFILE_REQ.an`, annonces dans le hash global) ; `pourboire` facultatif sur les commandes (hors hash) |

**Pourquoi une rupture en 3.** Un état inconnu fait rejeter la commande par une version 2, et une confirmation écrite par le client
(auteur différent du crafteur) échouerait à sa validation, avec des demandes répétées à chaque synchro. Il n'y a donc pas de
passerelle : les 0.4.x et la 0.5 ne se synchronisent plus entre elles, et la 0.5 signale aux joueurs de mettre à jour.

**Données déjà enregistrées.** Une commande `terminee` d'avant la 0.5 reste `terminee` (sans attente de confirmation), et reste
valide avec son crafteur comme auteur. Le format des SavedVariables ne change pas : `schema` reste 1.

**Pourquoi une rupture en 4.** Le hash global comprend maintenant les annonces : une version 3 et une version 4 ne s'accorderaient
jamais sur un même état et se relanceraient à chaque annonce. Il n'y a donc pas de passerelle : la 0.5.x et la 0.6 ne se
synchronisent plus entre elles, et la 0.6 est une mise à jour obligatoire (l'avertissement de version existant le signale).
Le format des SavedVariables reste `schema` 1 : les nouveaux champs (`annonces`, `historique`, `favoris`) sont facultatifs.
