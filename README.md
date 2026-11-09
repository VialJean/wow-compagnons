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

Version 0.1 (bêta) : navigateur de recettes, panneau dans la fenêtre de métier, bouton de minicarte,
synchronisation des profils de guilde. À venir : commandes et tableau des commandes, puis le Relais
et le bot Discord.

## Commandes

| Commande | Effet |
|---|---|
| `/cpg` | ouvre ou ferme l'atelier de guilde (aussi `/cpg recettes`) |
| `/cpg minicarte` | masque ou réaffiche le bouton de la minicarte |
| `/cpg sync [annonce]` | état de la synchro de guilde, ou force une annonce |
| `/cpg aide` | liste des commandes |
| `/cpg diag` | diagnostic du client (à lancer avec une fenêtre de métier ouverte) |
| `/cpg perso` | métiers et recettes scannés pour le personnage |
| `/cpg debug` | active ou coupe les messages de debug |
| `/cpg journal [n]` | n dernières lignes du journal |

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
Data/      Recettes.lua, généré par Compagnons.Recettes (dépôt wow-compagnons-services)
Modules/   scanner, réseau (AceComm), diagnostic
UI/        fenêtre principale, panneau de la fenêtre de métier, bouton de minicarte
Debug/     journal, futur panneau /cpg debug
tests/     busted, dont le simulateur de synchro
docs/      protocole.md : format des données et des messages ; logo ; texte CurseForge
```

## Licence

MIT
