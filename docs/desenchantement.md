# Spécification — Infobulle de désenchantement

Statut : implémentée, à vérifier en jeu. Complète `docs/infobulles.md`.

## 1. Objectif

Quand on ramasse ou survole une pièce d'équipement, savoir **si elle se désenchante** et **qui, dans la guilde, a
l'Enchantement** pour le faire, avec son niveau.

Hors périmètre :

- **Le niveau d'Enchantement exigé.** Il n'est pas dans le client Forever : la colonne `SkillRequired` de la table
  `ItemDisenchantLoot` vaut 0 sur les 54 lignes, le serveur le vérifie. L'infobulle ne dit donc pas « il te manque N
  points » ; elle donne le niveau d'objet et le niveau de chaque enchanteur, le joueur juge.
- Ce que le désenchantement rapporte (poussières, essences, éclats) : tables de butin du serveur, absentes du client.

## 2. Contenu

```
Compagnons · désenchantement
Désenchantable · niveau d'objet 42
Enchanteurs : Orvanne (en ligne, 150), Brumefer (140), Jean (toi, 60)
```

| Ligne | Règle |
|---|---|
| Titre | « Compagnons · désenchantement », couleur or |
| Éligibilité | « Désenchantable · niveau d'objet N », d'après les tranches du client (§3.1) |
| Enchanteurs | personnages qui ont le métier Enchantement (membres et mes personnages), avec leur niveau. En ligne d'abord, puis niveau décroissant, puis nom. Couleur de classe ; « (en ligne) » en vert, « (toi) » pour mes personnages. 4 au plus, puis « et N autres » |
| Aucun | « Aucun enchanteur dans la guilde », gris, si personne n'a le métier. Option §6 |

Le bloc s'ajoute **après** « objet craftable » et « composant », séparé par une ligne vide. Il n'apparaît que pour les
**armes et armures de qualité inhabituelle, rare ou épique**, dans les tranches de niveau d'objet du client.

Cas particuliers :

- Un objet que le jeu refuse de désenchanter malgré une tranche valide (récompense de quête, objet particulier) n'est pas
  reconnaissable côté addon : l'infobulle peut l'annoncer à tort. Le jeu reste seul juge.
- Les infobulles de comparaison ne reçoivent rien.
- Si le jeu n'a pas encore les informations de l'objet en cache, rien n'est ajouté, sans erreur.

## 3. Données

### 3.1 Tranches désenchantables (table du client)

`ItemDisenchantLoot` exportée en CSV avec wow.export, comme les tables de recettes :

| Colonne | Rôle |
|---|---|
| `Class` | classe d'objet (2 = arme, 4 = armure) |
| `Subclass` | sous-classe, -1 pour toutes |
| `Quality` | 2 = inhabituel, 3 = rare, 4 = épique |
| `MinLevel`, `MaxLevel` | tranche de niveau d'objet, bornes comprises |
| `SkillRequired`, `ExpansionID` | **ignorées** : toujours 0 et -2 dans Forever |

`compagnons-recettes --desenchantement <fichier>` lit ce CSV et écrit `Data/Desenchantement.lua`, de façon déterministe
(54 tranches, sans doublon, triées par classe, qualité, niveau).

```lua
ns.Desenchantement = {
  build = "1.60.1.70862",
  tranches = { { classe = 4, sous = -1, qualite = 2, min = 5, max = 15 }, ... },
}
```

Constats : les épiques ne se désenchantent qu'à partir du niveau d'objet 40 ; les objets de niveau 61 à 99 forment une
seule tranche ; il n'existe aucune tranche pour les objets ordinaires ni légendaires.

### 3.2 Ce qui vient du jeu à l'exécution

Classe, sous-classe, qualité et **niveau d'objet effectif** de l'objet survolé : `C_Item.GetItemInfo` (valeurs 3, 4, 12
et 13) et `C_Item.GetDetailedItemLevelInfo` sur le lien de l'infobulle, qui tient compte des améliorations. À vérifier par
`/cpg diag` (section « Infobulles »).

### 3.3 Niveau d'Enchantement des membres

Déjà dans les profils synchronisés : le métier `333` porte un `niveau`. Aucun changement de protocole. Le niveau affiché
est celui du dernier scan du membre.

## 4. Architecture

- `Core/Desenchanter.lua` (Lua pur) : `tranche(donnees, classe, sous, qualite, niveau)`.
- `Core/Catalogue.lua` : `Catalogue:Enchanteurs()`.
- `Core/Infobulles.lua` : `Infobulles.desenchanter(ctx, itemID)`, appelé par `Infobulles.lignes`.
- `UI/Infobulles.lua` : lit les informations d'objet et les passe au contexte.

## 5. Tests

`tests/infobulles_spec.lua` : tranches (bornes, qualités, classes, sous-classe précise), enchanteurs triés, limites,
aucun enchanteur, option coupée, profils reçus, séparation des blocs. `tests/Compagnons.Tests` : lecture du CSV,
colonnes manquantes, sortie Lua déterministe.

**En jeu** : survoler une arme et une armure inhabituelles, puis une épique de niveau d'objet inférieur à 40 (le bloc ne
doit pas apparaître), puis un consommable (rien).

## 6. Options

`profile.infobulles.desenchantement` (activé) et `profile.infobulles.aucunEnchanteur` (activé).
`/cpg infobulles desenchantement|enchanteur` bascule.

## 7. Évolution possible

Afficher le niveau d'Enchantement requis, si l'on obtient des seuils fiables pour Forever (par exemple relevés en jeu
avec un objet de chaque tranche). Il suffirait d'ajouter une colonne `requis` aux tranches et la comparaison avec le
niveau de chaque enchanteur (« capables » et « pas encore »).
