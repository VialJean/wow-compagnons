# Spécification — Infobulle de désenchantement

Statut : à valider. Complète `docs/infobulles.md`.

## 1. Objectif

Quand on ramasse ou survole une pièce d'équipement, savoir **qui, dans la guilde, peut la désenchanter** :
quel niveau d'Enchantement l'objet exige, qui l'atteint, et qui est trop bas.

Hors périmètre : ce que le désenchantement rapporte (poussières, essences, éclats) : cela dépend de tables de butin du
serveur, absentes du client.

## 2. Contenu

```
Compagnons · désenchantement
Niveau d'Enchantement requis : 125
Désenchantable par Orvanne (en ligne), Brumefer
Pas encore : Jean (toi) 60/125
```

| Ligne | Règle |
|---|---|
| Titre | « Compagnons · désenchantement », couleur or |
| Requis | « Niveau d'Enchantement requis : N », gris clair |
| Capables | membres (et mes personnages) dont le **niveau d'Enchantement ≥ requis**. En ligne d'abord, puis nom ; couleur de classe ; « (en ligne) » en vert, « (toi) » pour mes personnages. 3 noms au plus, puis « et N autres » |
| Trop bas | membres qui ont l'Enchantement mais **pas le niveau** : « Pas encore : Nom 60/125 ». 2 noms au plus, le plus proche d'abord |
| Aucun | si personne n'a l'Enchantement : « Aucun enchanteur dans la guilde », gris. Omis si l'option §6 est coupée |

Cas particuliers :

- Un objet que le jeu refuse de désenchanter (récompense de quête, objet lié sans désenchantement, qualité insuffisante)
  ne peut pas toujours être reconnu côté addon : l'infobulle le signale par un simple « si l'objet le permet »
  quand le doute existe (voir §8, question 2).
- **Qualités concernées** : inhabituelle (vert), rare (bleu), épique (violet). Armures et armes uniquement.
- Les infobulles de comparaison ne reçoivent rien.
- Si le jeu n'a pas encore les informations de l'objet en cache, rien n'est ajouté (sans erreur).

## 3. Données

### 3.1 Table du client

`ItemDisenchantLoot` (export CSV du client Forever, avec wow.export comme pour les recettes) :

| Colonne | Rôle |
|---|---|
| `Class` | classe d'objet (2 = arme, 4 = armure) |
| `Subclass` | sous-classe, ou -1 pour toutes |
| `Quality` | qualité de l'objet (2, 3, 4) |
| `MinLevel`, `MaxLevel` | tranche de niveau d'objet |
| `SkillRequired` | niveau d'Enchantement exigé |
| `ExpansionID` | extension : on ne garde que celles de Forever |

L'outil `compagnons-recettes` lit ce CSV et écrit `Data/Desenchantement.lua`, de façon déterministe, avec le même
tolérance sur les noms de colonnes et le même séparateur automatique que pour les recettes.

```lua
ns.Desenchantement = {
  build = "1.60.1.70862",
  lignes = { { classe = 4, sous = -1, qualite = 2, min = 1, max = 20, requis = 1 }, ... },
}
```

### 3.2 Ce qui vient du jeu à l'exécution

Pour l'objet survolé : classe, sous-classe, qualité et **niveau d'objet effectif**, lus par `C_Item.GetItemInfo` et
`C_Item.GetDetailedItemLevelInfo` (le niveau effectif tient compte des améliorations). Ces API sont vérifiées par
`/cpg diag` (section « Infobulles »).

### 3.3 Niveau d'Enchantement des membres

Déjà présent dans les profils synchronisés : le métier Enchantement (`333`) porte un `niveau`. Rien à ajouter au
protocole. Le niveau affiché est celui du dernier scan du membre.

## 4. Architecture

- `Core/Desenchantement.lua` (Lua pur, testé) : `requis(donnees, classe, sous, qualite, niveauObjet)` renvoie le niveau
  exigé ou `nil`. En cas de plusieurs lignes, la sous-classe précise l'emporte sur `-1`.
- `Core/Infobulles.lua` : `Infobulles.desenchanter(ctx, info)` renvoie les lignes du §2. `ctx` ajoute
  `niveauxEnchantement` : liste `{ cle, nom, classe, niveau, enLigne, mien }` fournie par le catalogue.
- `UI/Infobulles.lua` : dans le crochet existant, lire les informations de l'objet et ajouter le bloc **après** les blocs
  « objet craftable » et « composant ».
- `Catalogue:Enchanteurs()` : membres qui ont le métier 333, avec leur niveau, depuis les personnages et les profils.

## 5. Tests

- **Hors jeu** : tranches de niveau (bornes comprises), sous-classe précise contre `-1`, objet hors tranche, qualité
  non concernée, capables et « trop bas » triés, limites de noms, aucun enchanteur, option coupée.
- **Outil .NET** : lecture du CSV, tolérance sur les colonnes, filtrage par extension, sortie Lua déterministe.
- **En jeu** : survoler une arme et une armure inhabituelles dans le butin et dans un sac ; comparer le niveau requis
  annoncé avec le message du jeu quand on tente de désenchanter avec un niveau trop bas.

## 6. Options

`profile.infobulles.desenchantement` (activé par défaut) et `profile.infobulles.aucunEnchanteur` (activé).
`/cpg infobulles desenchantement|enchanteur` bascule.

## 7. Étapes

1. Vérifier les API objet dans `/cpg diag` (fait avec cette spec).
2. Exporter `ItemDisenchantLoot` en CSV avec wow.export.
3. Outil .NET et `Data/Desenchantement.lua`.
4. `Core/Desenchantement.lua`, `Catalogue:Enchanteurs()` et `Infobulles.desenchanter`, avec tests.
5. Branchement dans l'infobulle, options, vérification en jeu.

## 8. Questions ouvertes

1. **Niveau affiché des membres** : celui du dernier scan (proposé). Un membre qui a monté depuis peut apparaître « pas encore ».
2. **Objets non désenchantables** : le client ne le dit pas simplement. On ajoute « si l'objet le permet » (proposé) ou on
   ne dit rien.
3. **Bloc seul ou avec les autres** : en bas de l'infobulle, après « craftable » et « composant » (proposé).
4. **Mes personnages sans Enchantement** : ne rien afficher les concernant (proposé).
