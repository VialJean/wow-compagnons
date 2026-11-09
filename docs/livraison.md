# Spécification — Livraison et stocks (piste v3)

Statut : phases 0 et 1 implémentées (observation, stock par personnage, liste de courses) ; phases 2 à 6 à venir. Complète `docs/protocole.md` (commandes) et `docs/infobulles.md` (infobulles).

## 1. Objectif

Faire passer une commande **du besoin à la livraison sans quitter le jeu**, avec un suivi qui se met à jour tout seul :

- le client **envoie** les composants au crafteur, le crafteur **envoie** l'objet fabriqué au client ;
- chacun **reçoit** ce que l'autre envoie ;
- l'état de la commande (`mats reçus`, progression « 3/5 », `terminée`) suit ce qui s'est réellement passé.

Deuxième volet : un **stock de tous mes personnages** (sacs et banque) pour que « Manque N » et « Je fournis » soient
justes, plus une **liste de courses** regroupée.

## 2. Ce qui peut être automatique, et ce qui ne le peut pas

Blizzard interdit qu'un addon joue à la place du joueur. Certaines actions exigent un **clic réel** (événement matériel),
et un addon ne peut pas les déclencher seul. La conception s'appuie sur cette frontière :

| Niveau | Contenu | Exemples |
|---|---|---|
| **Automatique** (lecture seule) | détecter et enregistrer ce qui se passe | fin d'un échange, courrier reçu, objet fabriqué, contenu des sacs et de la banque |
| **Assisté** (un clic du joueur) | tout préparer, le joueur valide | remplir un échange ou un courrier avec les bons objets, destinataire et objet du courrier pré-remplis |
| **Interdit** | ce que l'addon ne fera jamais | accepter un échange, envoyer un courrier ou valider seul, répondre à la place du joueur |

À vérifier en jeu (§8) : l'API exacte de Forever pour chaque action, et si un seul clic peut déclencher plusieurs
opérations (par exemple poser tous les composants d'un coup) ou s'il en faut un par opération. Si c'est un par
opération, l'assistance se fait pas à pas (« Placer l'objet suivant »).

Dans la suite, « automatique » veut dire détection et suivi. L'envoi est « assisté ».

## 3. Flux de livraison

### 3.1 Composants : client vers crafteur

1. Le crafteur prend la commande (`prise`). Si `mats = tout` ou `partie`, le client doit fournir.
2. Le client ouvre un **échange** ou un **courrier** avec le crafteur : l'addon propose « Fournir les composants de la
   commande X » (liste des objets et quantités, avec le stock de tous mes personnages).
3. Après un clic, il place les composants (ou le fait objet par objet). Il valide lui-même.
4. Quand l'échange se **termine** ou que le courrier **arrive**, les deux addons le détectent :
   - côté crafteur : les composants reçus sont comptés pour la commande ;
   - quand tous les composants requis sont là, la commande passe seule à `mats reçus`.
5. Si `mats = crafteur`, cette étape est sautée.

### 3.2 Objet fabriqué : crafteur vers client

1. Le crafteur fabrique depuis la fenêtre de métier : chaque fabrication de la recette incrémente la progression de la
   commande (« 3/5 craftés »).
2. Le crafteur envoie : même assistance que §3.1, destinataire pré-rempli.
3. Quand l'échange se termine ou que le courrier est envoyé, l'addon compte les objets livrés.
4. Quand `livré ≥ quantité`, la commande passe seule à `terminée` côté crafteur. Le client voit la réception de son côté
   (échange fini ou courrier reçu) et la confirme (§6, question 2).

### 3.3 Rapprochement avec la bonne commande

Un échange peut concerner plusieurs commandes du même couple (client, crafteur). Règle : on répartit les objets sur les
commandes **de la plus ancienne à la plus récente**, dans la limite de ce qui est attendu. Ce qui dépasse n'est rattaché à
aucune commande (un message le signale). L'addon n'agit jamais sur un échange avec une personne qui n'est pas dans une
commande ouverte.

## 4. Modèle de données

Champs ajoutés à une commande (`docs/protocole.md`), tous facultatifs, version de protocole 3 :

```lua
progres = {
  craftes = 3,                 -- fabriqués par le crafteur (un seul auteur : le crafteur assigné)
  livres = 2,                  -- objets remis au client, constatés par l'échange ou le courrier
  mats = { [2449] = 10 },      -- composants reçus par le crafteur, par objet
}
recu = 2                       -- objets reçus, confirmés par le client (un seul auteur : le client)
```

- **Un seul auteur par champ** : `craftes`, `livres` et `mats` ne sont écrits que par le crafteur assigné, `recu` que par le
  client. Les copies ne se contredisent donc jamais ; la règle de fusion par révision reste inchangée.
- Chaque mise à jour passe par `ORDER_UPD`. Pour ne pas inonder le canal quand on fabrique en série, les compteurs sont
  regroupés : au plus une mise à jour toutes les 10 s, et toujours une en fin de série.
- Un échange ou un courrier détecté enregistre aussi une ligne dans `histo` (« 10 × Terrestrine reçus »).
- Les droits restent ceux du protocole : seul le crafteur assigné fait avancer, seul le client annule.

## 5. Stocks et liste de courses

### 5.1 Stock par personnage

- À la fermeture de la banque et des sacs, l'addon relève, pour chaque personnage, la quantité de **chaque composant connu**
  (environ 570 objets de la base), sacs et banque : `db.global.stock[cle] = { maj, [itemID] = quantité }`.
- Un personnage ne peut relever que ses propres sacs et sa propre banque, quand il est connecté. Le stock d'un autre
  personnage du compte est donc celui du dernier passage, avec sa date.
- Les quantités servent à : « Manque N » de l'infobulle, « Je fournis » du dialogue de commande, la liste de courses.

### 5.2 Liste de courses

Un onglet ou un panneau regroupe, pour mes commandes en cours :

- les composants à fournir (commandes où je suis client avec `mats = tout` ou `partie`) ;
- ceux que je dois acheter pour fabriquer (commandes que j'ai prises avec `mats = crafteur`) ;
- pour chacun : besoin total, stock de tous mes personnages (avec le personnage qui les a), manque ;
- « Copier dans le chat » pour demander à la guilde.

### 5.3 Partage de stock (facultatif, phase 6)

Demande de matériaux entre membres (« qui a du Lotus pourpre ? »). **Désactivé par défaut** : le partage est une option par
personnage, et seuls les composants de la base sont envoyés, jamais l'inventaire complet. Hors du périmètre initial.

## 6. Options et sécurité

| Option | Défaut | Effet |
|---|---|---|
| `livraison.suivi` | activé | détection des échanges, courriers et fabrications, mise à jour des commandes |
| `livraison.aide` | activé | boutons d'assistance (pré-remplissage) |
| `livraison.collecte` | désactivé | récupérer seul les pièces jointes des courriers venant d'un client ou d'un crafteur d'une commande ouverte |
| `stock.suivi` | activé | relevé des sacs et de la banque |
| `stock.partage` | désactivé | partage des quantités de composants avec la guilde |

Règles :

- Aucune action n'est faite sans clic pour les opérations qui l'exigent ; l'addon ne simule jamais un clic.
- Rien en combat, ni pendant une instance verrouillée.
- La collecte de courrier est limitée aux expéditeurs liés à une commande ouverte, et ne prend jamais d'argent.
- Chaque détection est journalisée (`/cpg journal`) avec l'événement d'origine, pour pouvoir vérifier ce que l'addon a compris.
- Un compteur peut toujours être corrigé à la main (menu de la commande).

## 7. Phases

| Phase | Contenu | Risque |
|---|---|---|
| 0 | **Observation** : `/cpg observer` journalise les événements d'échange, de courrier et de fabrication avec leurs données | nul |
| 1 | Stock par personnage, « Manque » et « Je fournis » avec les autres personnages, liste de courses | faible |
| 2 | Comptage des fabrications, progression « 3/5 », champs de protocole 3 | faible |
| 3 | Détection des échanges : composants reçus, objets livrés, passage automatique à `mats reçus` et `terminée` | moyen |
| 4 | Détection des courriers, collecte facultative | moyen |
| 5 | Assistance à l'envoi : destinataire et objets pré-remplis, un clic par validation | dépend des API |
| 6 | Partage de stock facultatif | confidentialité |

Les phases 1 et 2 ne dépendent d'aucune API sensible et apportent déjà une grande partie de la valeur. La phase 0 sert à
ne pas deviner les événements de Forever.

## 8. À vérifier en jeu (phase 0)

Événements et fonctions à relever avec `/cpg observer`, en faisant un échange, un courrier et une fabrication réels :

- échange : `TRADE_SHOW`, `TRADE_ACCEPT_UPDATE`, `TRADE_PLAYER_ITEM_CHANGED`, `TRADE_TARGET_ITEM_CHANGED`,
  `TRADE_CLOSED`, message « échange terminé », `GetTradePlayerItemInfo`, `GetTradeTargetItemInfo` ;
- courrier : `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `MAIL_SEND_SUCCESS`, `GetInboxItem`, `TakeInboxItem`, `GetSendMailItem` ;
- fabrication : `UNIT_SPELLCAST_SUCCEEDED` (sort de recette), `TRADE_SKILL_CRAFT_BEGIN` / `TRADE_SKILL_ITEM_CRAFTED`
  ou équivalents, messages de création d'objet ;
- sacs : `BAG_UPDATE_DELAYED`, `BANKFRAME_OPENED` / `BANKFRAME_CLOSED`, `C_Item.GetItemCount` ;
- restrictions : lesquelles de ces actions exigent un clic réel sous Forever, et combien d'opérations un clic peut enchaîner.

## 9. Tests

- **Hors jeu (busted)** : rapprochement des objets avec les commandes (plus ancienne d'abord, plafond, surplus), passage
  automatique `mats reçus` et `terminée`, compteurs à auteur unique, regroupement des mises à jour, fusion de copies,
  messages forgés (un client qui écrit `craftes`), calcul de la liste de courses avec plusieurs personnages, simulation de
  synchro avec progression en série.
- **En jeu** : échange complet à deux joueurs dans les deux sens, courrier dans les deux sens, fabrication de 5 objets
  avec suivi « 3/5 », échange annulé (rien ne doit être compté), échange partiel.

## 10. Questions ouvertes

1. **Confirmation du client** : la commande est-elle `terminée` dès la livraison constatée (proposé), ou seulement quand le
   client confirme la réception ?
2. **Échange annulé ou partiel** : on ne compte que ce qui a réellement changé de mains (proposé).
3. **Collecte de courrier** : option désactivée par défaut (proposé), limitée aux expéditeurs d'une commande ouverte.
4. **Seuil de regroupement** des mises à jour de progression : 10 s (proposé).
5. **Stock des autres personnages** : affiché avec sa date (proposé), avec avertissement s'il a plus de 7 jours.

## 11. Estimation de coût (décision et état)

**Décision** : les prix viennent de l'hôtel des ventes, **relevés par l'addon** quand le joueur cherche lui-même, puis
(à terme) partagés avec la guilde par la synchro. Aucun scan automatique. Les prix de vendeur du client (`BuyPrice`,
`SellPrice`) ne sont pas utilisés : beaucoup de composants ne s'achètent pas chez un PNJ, l'estimation serait fausse.

**Affichage** : coût du manque dans la liste de courses (par ligne et en bas), coût des composants dans le dialogue de
commande. Un composant sans prix n'est jamais ignoré en silence : il est compté (« 2 sans prix ») et la ligne affiche « ? ».

**Fait (phase 1 bis)**
- `Core/Prix.lua` (Lua pur, testé) : prix unitaire en cuivre avec horodatage, le plus récent gagne, valeurs aberrantes
  refusées, minimum d'une liste de lots à achat immédiat, coût d'une recette ou d'une liste, montants lisibles.
- `Modules/Marche.lua` : relevé à l'hôtel des ventes pour les deux familles d'API (ancienne :
  `AUCTION_ITEM_LIST_UPDATE` ; moderne : `COMMODITY_SEARCH_RESULTS_UPDATED`), avec garde-fous. Seuls les composants de la base
  sont mémorisés, au prix unitaire le plus bas à achat immédiat vu.
- `/cpg prix id-ou-lien montant` fixe un prix à la main (un nombre seul est en pièces d'or) ; `/cpg prix` donne le nombre de
  prix connus ; `/cpg prix clear` efface.
- Prix de plus de trois jours signalés comme anciens dans l'infobulle de la liste de courses.

**Reste à faire**
1. **Vérifier en jeu** quelle API de l'hôtel des ventes Forever expose : `/cpg observer` relève désormais ces API et
   événements à l'ouverture de l'hôtel des ventes. Si aucune des deux familles ne répond, le relevé automatique est à
   adapter, et la saisie manuelle sert de repli.
2. **Partager les prix avec la guilde** : n'importe quel membre qui visite l'hôtel des ventes met le prix à jour pour tous.
   À concevoir sans casser la compatibilité : les prix restent **hors du hash global** (les clients qui ne les connaissent pas
   ne doivent pas se croire désynchronisés), échangés par des messages dédiés ignorés par les anciennes versions, avec la
   même règle « le plus récent gagne », des bornes de validation (prix plausibles, horodatage non futur) et un plafond de
   fréquence. À tester avec le simulateur de synchro.
