# Compagnons — Atelier de guilde

Addon pour World of Warcraft: Forever : suivi des métiers et commandes de craft en guilde.
Tout fonctionne en jeu, sans serveur ; la synchronisation passe par le canal addon de la guilde.

## Installation

**CurseForge** (recommended): install *Compagnons* from the project page with your addon manager.

**Manual:**
1. Download `Compagnons-<version>-forever.zip` from the [Releases](https://github.com/VialJean/wow-compagnons/releases) page.
   Do not use GitHub's "Download ZIP" button: it does not include the libraries.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/` so that you get
   `AddOns/Compagnons/Compagnons.toc`.
3. Start the game, enable the addon on the character selection screen
   (tick *Load out of date AddOns* if needed) and log in.

**Getting started**
1. Open each of your professions once: the addon scans your known recipes.
2. Type `/cpg` (or click the minimap button) to open the workshop.
3. Guildmates who also run the addon share their recipes with you automatically.

Requirements: a full (not trial) account, and a guild. Trial accounts cannot send addon messages.

## État

Version 0.5 (bêta) : navigateur de recettes, commandes de craft (création, tableau, prise, libération,
annulation), panneau dans la fenêtre de métier, alertes, bouton de minicarte, synchronisation des profils
et des commandes de guilde, infobulles, liste de courses avec stock de tous les personnages et coût estimé (prix
relevés à l'hôtel des ventes et partagés avec la guilde), suivi des fabrications, détection des livraisons par échange et
par courrier, assistant de remise (un clic par objet ; l'échange et le courrier restent validés par le joueur), réception
confirmée par le client (une commande est « livrée » puis « terminée »), suggestion de crafteur, rappels à la connexion et
avertissement quand un membre de la guilde a une version trop ancienne de l'addon. Détail dans [CHANGELOG.md](CHANGELOG.md) et `docs/livraison.md`.

## Langues

L'interface et les noms du jeu suivent la langue du client : **anglais** (référence) et **français** sont livrés ; les
autres langues s'affichent en anglais. La synchronisation échange des identifiants, jamais des noms : un joueur anglophone
et un joueur francophone peuvent se synchroniser, chacun voit les noms dans sa langue.

Les commandes existent en anglais et en français :

| Commande | Alias français | Effet |
|---|---|---|
| `/cpg` | | ouvre ou ferme l'atelier de guilde (aussi `/cpg recipes`) |
| `/cpg minimap` | `minicarte` | masque ou réaffiche le bouton de la minicarte |
| `/cpg sync [announce]` | `annonce` | état de la synchro de guilde, ou force une annonce |
| `/cpg reminders [on\|off\|now]` | `rappels` | rappels à la connexion (une fois par jour) : commandes à confirmer, sans preneur, sans avancée ; propose d'annuler les commandes ouvertes depuis 30 jours |
| `/cpg warn [login on\|off\|silent on\|off\|send]` | `avertir` | avertissement des membres dont la version de Compagnons est trop ancienne : fenêtre et son à la connexion (et, en option, à chaque connexion d'un membre en retard), ou envoi du chuchotement (jamais automatique) |
| `/cpg tooltips [item\|reagent\|nobody\|disenchant\|enchanter\|order <ctrlshift\|shift\|none>]` | `infobulles` | réglages des infobulles |
| `/cpg help` | `aide` | liste des commandes |
| `/cpg diag` | | diagnostic du client (à lancer avec une fenêtre de métier ouverte) |
| `/cpg char` | `perso` | métiers et recettes scannés pour le personnage |
| `/cpg shopping` | `courses` | liste de courses pour mes commandes en cours, avec le stock de tous mes personnages |
| `/cpg stock [on\|off\|now]` | | suivi du stock de composants de tous mes personnages |
| `/cpg price [id ou lien montant\|clear]` | `prix` | prix des composants (relevés à l'hôtel des ventes ou saisis à la main) |
| `/cpg observer [on\|off\|clear\|show [n]]` | | relève les événements d'échange, de courrier, de fabrication et de l'hôtel des ventes (diagnostic) |
| `/cpg debug` | | active ou coupe les messages de debug |
| `/cpg log [n]` | `journal` | n dernières lignes du journal |

### Ajouter une langue

1. Copier `Locales/frFR.lua` en `Locales/<langue>.lua` (par exemple `deDE`) et traduire les valeurs. Les clés absentes
   retombent sur l'anglais.
2. Ajouter le fichier au `.toc`, avant `Core\Locales.lua`, et la langue à la liste `LANGUES` de `tests/locales_spec.lua`.
3. Pour les noms de recettes et de composants : exporter les tables du jeu dans cette langue avec wow.export, puis lancer
   `compagnons-recettes ... --noms deDE=<dossier>` (dépôt `wow-compagnons-services`) et ajouter `Data\Noms.deDE.lua` au `.toc`.

`tests/locales_spec.lua` vérifie que chaque langue a les mêmes clés que l'anglais et les mêmes `%s` / `%d`, qu'aucune clé
n'est utilisée sans exister, et qu'aucune clé n'est inutilisée.

## Développement

1. Récupérer les bibliothèques : `./scripts/libs.sh` (git, subversion et curl requis).
2. Lier le dépôt dans le dossier `Interface/AddOns/Compagnons` de l'installation Forever
   (lien symbolique, ou jonction `mklink /J` sous Windows).
3. En jeu : `/reload` après chaque modification.

Tests hors jeu (Lua 5.1) :

```bash
luarocks install busted luacheck
luacheck .
busted tests
```

## Publication

Un tag `vX.Y.Z` déclenche le packager : zip avec bibliothèques, release GitHub,
puis CurseForge et Wago une fois les secrets `CF_API_KEY` et `WAGO_API_TOKEN` configurés.

## Structure

```
Core/      initialisation, catalogue de recettes, profils, moteur de synchro (Lua pur, testé hors jeu)
Locales/   textes de l'interface : enUS (référence), frFR
Data/      Recettes.lua (structure), Noms.<langue>.lua, Desenchantement.lua : générés par Compagnons.Recettes
           (dépôt wow-compagnons-services)
Modules/   scanner, réseau (AceComm), diagnostic
UI/        fenêtre principale, panneau de la fenêtre de métier, bouton de minicarte
Debug/     journal, futur panneau /cpg debug
tests/     busted, dont le simulateur de synchro
docs/      protocole.md : format des données et des messages ; logo ; texte CurseForge
```

## Licence

MIT
