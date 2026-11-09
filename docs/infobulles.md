# Spécification — Infobulles détaillées

Statut : implémentée (étapes 1 à 4), à vérifier en jeu avec la liste du §7. Décisions prises : touche Ctrl+Maj,
crafteurs hors ligne affichés, ligne « personne » désactivée par défaut, seuil gris pour « monte encore », nombre de
commandes seulement. Source : section « Intégrations dans l'interface du jeu » de la spec Notion et écran
« Intégrations » de la maquette. Cette spec précise ce que la spec Notion laissait ouvert (« à revoir quand on y sera »).

## 1. Objectif

Faire apparaître l'information de la guilde là où le joueur regarde déjà : sur n'importe quelle infobulle d'objet du jeu
(sacs, banque, hôtel des ventes, chat, butin). Deux cas :

- **Objet craftable** : qui, dans la guilde, sait le fabriquer, et quelles commandes sont ouvertes pour lui.
- **Composant** : ce qu'il manque pour mes commandes, et qui, dans la guilde, l'utilise.

Hors périmètre : infobulles de l'addon lui-même (déjà faites : recettes, composants, lignes de commandes, boutons),
infobulle de sort/enchantement, infobulle de la minicarte.

## 2. Contenu

### 2.1 Objet craftable

Affiché si l'objet est créé par au moins une recette de la base (index « objet → recettes », voir §4).

```
Compagnons
Craftable par Kaelys (en ligne), Orvanne, Brumefer et 2 autres
2 commandes ouvertes · tu peux en remplir 1
Ctrl+Maj+clic : commander
```

| Ligne | Règle |
|---|---|
| Titre | « Compagnons », couleur or (`e0b252`), en gras |
| Crafteurs | union des crafteurs de **toutes** les recettes qui créent l'objet. Triés : en ligne d'abord, puis ordre alphabétique. Couleur de classe. 3 noms au plus, puis « et N autres ». Suffixe « (en ligne) » en vert, rien pour hors ligne |
| Personne | si la recette existe mais que personne ne la connaît : « Personne ne sait la fabriquer », gris clair. Option §6 |
| Commandes | nombre de commandes ouvertes ou prises pour cet objet. Si au moins une est remplissable par l'un de mes personnages : « tu peux en remplir N ». Ligne omise s'il n'y a aucune commande |
| Indication | « Ctrl+Maj+clic : commander », gris. Omise si la touche est désactivée (§6) |

### 2.2 Composant

Affiché si l'objet est un composant d'au moins une recette de la base.

```
Compagnons · composant
Manque 13 pour ta commande d'Huile de mana brillante
Brumefer : 4 recettes, dont 1 qui monte encore
Orvanne : 2 recettes
Maj : détail des recettes
```

| Ligne | Règle |
|---|---|
| Titre | « Compagnons · composant » |
| Manque | pour chaque commande **dont je suis le client**, non finale, où la recette utilise ce composant et où les composants ne sont pas fournis par le crafteur : `manque = besoin − (sac + banque)`, avec `besoin = qté composant × qté commande`. Affichée si `manque > 0`, en orange. Une seule commande détaillée, puis « et N autres commandes » |
| À fournir | pour chaque commande **que j'ai prise** et dont le crafteur fournit les composants (`mats = crafteur`) : « Requis pour ta commande de X : N ». En bleu |
| Crafteurs | pour chaque membre de la guilde qui connaît au moins une recette utilisant ce composant : « Nom : N recettes ». Triés par nombre de recettes décroissant, puis nom. 3 membres au plus, puis « et N autres » |
| Monte encore | « dont N qui monte encore » : recettes pour lesquelles le niveau du métier du membre est **inférieur au seuil gris** (`seuils[4]`) de la recette, donc qui font encore progresser. Omis si N = 0 |
| Détail (Maj) | maintenir **Maj** remplace la liste de crafteurs par la liste des recettes (8 au plus, puis « … »), avec le nom du premier crafteur de chacune |
| Indication | « Maj : détail des recettes », gris, tant que Maj n'est pas enfoncé |

Un objet peut être à la fois craftable et composant (ex. une barre de métal) : les deux blocs s'affichent, objet
craftable d'abord, séparés par une ligne vide.

### 2.3 Cas particuliers

- **Enchantements** : pas d'objet créé, donc pas d'infobulle d'objet craftable. Leurs composants, eux, ont une infobulle de composant.
- **Plusieurs rangs ou plusieurs recettes** pour un même objet : on fusionne (union des crafteurs, somme des commandes).
- **Objet inconnu de la base** (équipement, quête…) : l'addon n'ajoute rien.
- **Infobulles de comparaison** (`ShoppingTooltip1/2`) : rien n'est ajouté.
- **Données pas encore prêtes** (catalogue non construit) : rien n'est ajouté, sans erreur.

## 3. Comportement

1. Ajout en **fin d'infobulle**, après tout ce que le jeu et les autres addons écrivent.
2. **Jamais en double** : une infobulle peut être reconstruite plusieurs fois pendant un même survol. On marque l'infobulle
   avec l'identifiant de l'objet déjà traité et on le réinitialise quand elle est vidée.
3. **Pas de coût caché** : le calcul d'un survol est borné (index « objet → recettes » précalculés à la première demande).
   Mesuré sur la base réelle : 20 ms pour les 2 919 objets, 2 ms au pire pour un seul. Aucun cache n'est donc nécessaire,
   ce qui évite d'avoir à l'invalider quand le stock, les commandes ou les profils changent.
4. **En combat** : même comportement qu'en dehors, le calcul est léger. Seule l'alerte (toast) attend la fin du combat.
5. **Maj enfoncé ou relâché** pendant le survol met l'infobulle à jour (`MODIFIER_STATE_CHANGED`).
6. **Jamais d'erreur visible** : tout est protégé par `pcall` et journalisé (`/cpg journal`).

## 4. Données et architecture

### 4.1 Index (Core/Catalogue.lua, Lua pur, testé hors jeu)

Construits à la demande, une fois, à partir de `ns.Recettes` :

| Fonction | Rôle |
|---|---|
| `Catalogue:RecettesCreant(itemID)` | spellIDs des recettes qui créent l'objet |
| `Catalogue:RecettesUtilisant(itemID)` | spellIDs des recettes qui consomment l'objet comme composant |
| `Catalogue:Crafteurs(spellID)` | existe déjà |

### 4.2 Construction du texte (Core/Infobulles.lua, Lua pur, testé hors jeu)

Aucune API du jeu : le module reçoit les données et renvoie une liste de lignes.

```lua
Infobulles.objet(contexte, itemID)      --> { ligne, ... } ou nil
Infobulles.composant(contexte, itemID)  --> { ligne, ... } ou nil
-- ligne = { texte = "...", r = 1, g = 1, b = 1 }   (couleur 0..1)
```

`contexte` regroupe ce qui vient du jeu ou de l'addon : le catalogue, les commandes, l'ensemble de mes personnages,
une fonction `stock(itemID)`, une fonction `enLigne(cle)`, l'état de Maj et les options. Cela permet de tester tous les
cas du §2 avec des données fictives.

### 4.3 Branchement dans le jeu (UI/Infobulles.lua, fin et protégé)

- **Accrocher** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` si l'API existe.
- **Repli** : `GameTooltip:HookScript("OnTooltipSetItem", fn)` (et `ItemRefTooltip`) sinon.
- L'identifiant d'objet vient de la donnée de l'infobulle (`data.id`) ou de `tooltip:GetItem()`.
- Les lignes sont ajoutées par `AddLine` / `AddDoubleLine`, puis `tooltip:Show()` pour recalculer la taille.
- Cibles : `GameTooltip`, `ItemRefTooltip` (liens du chat). Les infobulles de comparaison sont ignorées.

Relevé en jeu : `TooltipDataProcessor` (avec `AddTooltipPostCall`), `Enum.TooltipDataType.Item`, `GameTooltip:SetItemByID`,
`GetItem`, `HookScript`, `ItemRefTooltip`, `HandleModifiedItemClick` sont tous présents ; seul
`ContainerFrameItemButton_OnModifiedClick` est absent, ce qui est sans conséquence. Le crochet moderne est donc
utilisé, sans repli par `OnTooltipSetItem`.

### 4.4 Vérification préalable des API (Modules/Diagnostic.lua)

Avant d'écrire le branchement, `/cpg diag` relève dans la section « Infobulles » :
`TooltipDataProcessor`, `Enum.TooltipDataType.Item`, `GameTooltip.SetItemByID`, `GameTooltip.GetItem`,
`C_Item.GetItemCount`, `IsModifiedClick` / `IsShiftKeyDown` / `IsControlKeyDown`, `ItemRefTooltip`, `HandleModifiedItemClick`.
Le résultat décide entre le crochet moderne et le repli.

## 5. Commande depuis un lien d'objet (Ctrl+Maj+clic)

La spec Notion prévoit « Maj+clic sur un lien d'objet ». Maj+clic insère déjà le lien dans le chat, ce qui ferait
conflit. **Proposition : Ctrl+Maj+clic**, configurable (§6).

- Cible : un lien d'objet cliqué dans le chat, un objet de sac, de banque ou de l'hôtel des ventes.
- Accrocher `HandleModifiedItemClick` (ou `ContainerFrameItemButton_OnModifiedClick` en repli), après les actions du jeu,
  seulement si Ctrl et Maj sont enfoncés.
- Si l'objet est créé par une recette de la base : ouvrir le dialogue de commande sur la recette. S'il y en a plusieurs,
  prendre celle dont le plus de crafteurs sont en ligne, puis la plus basse en niveau.
- Sinon : un message dans le chat (« Aucune recette connue pour cet objet »).
- Ne rien faire en combat ni si le dialogue est déjà ouvert pour une autre recette sans confirmation.

## 6. Options

Stockées dans `profile.infobulles`, modifiables par `/cpg infobulles`.

| Option | Défaut | Effet |
|---|---|---|
| `objet` | activé | infobulle d'objet craftable (§2.1) |
| `composant` | activé | infobulle de composant (§2.2) |
| `personne` | désactivé | ligne « Personne ne sait la fabriquer » pour les objets craftables inconnus de la guilde |
| `commander` | `ctrl+maj` | touche de commande rapide : `ctrl+maj`, `maj`, ou `aucune` |

`/cpg infobulles` affiche l'état ; `/cpg infobulles objet|composant|personne` bascule l'option.

## 7. Tests

**Hors jeu (busted)** : `tests/infobulles_spec.lua`, un test par ligne du §2 avec des données fictives :
crafteurs triés (en ligne d'abord), « et N autres », union de plusieurs recettes, objet craftable et composant à la fois,
manque calculé avec sac et banque, commande dont le crafteur fournit les composants, « monte encore » selon le seuil gris,
détail avec Maj, objet inconnu, catalogue absent, options désactivées. Test d'index dans `tests/catalogue_spec.lua`.

**En jeu (liste de contrôle)** :
1. Survoler un objet craftable par la guilde (sac, chat, hôtel des ventes) : le bloc « Compagnons » s'affiche, une seule fois.
2. Survoler un composant : lignes « Manque » et crafteurs corrects ; Maj affiche le détail.
3. Survoler un objet sans recette : aucune ligne ajoutée.
4. Désactiver une option : le bloc disparaît.
5. Passer d'un objet à l'autre rapidement : pas de doublon, pas d'erreur dans `/cpg journal`.
6. Ctrl+Maj+clic sur un lien d'objet craftable : le dialogue de commande s'ouvre sur la bonne recette.

## 8. Étapes

1. Relevé des API dans `/cpg diag` (§4.4) : un `/reload` suffit, résultat lisible dans le fichier SavedVariables.
2. Index et `Infobulles.objet` / `Infobulles.composant` avec tests.
3. Branchement dans le jeu et options.
4. Ctrl+Maj+clic.

## 9. Questions ouvertes

1. **Touche de commande rapide** : Ctrl+Maj (proposé), ou Maj comme dans la spec Notion malgré le conflit avec le chat ?
2. **Crafteurs hors ligne** : les afficher (proposé, en gris avec le nombre) ou seulement les connectés ?
3. **Ligne « Personne ne sait la fabriquer »** : désactivée par défaut (proposé, pour limiter le bruit) ou activée ?
4. **Seuil « monte encore »** : seuil gris (proposé), ou seuil vert si l'on veut ne compter que les recettes encore rentables ?
5. **Commandes sur l'infobulle d'objet** : montrer le détail (client, quantité) ou seulement le nombre (proposé) ?
