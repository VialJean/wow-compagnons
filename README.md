# Compagnons — Atelier de guilde

Addon pour World of Warcraft: Forever : suivi des métiers et commandes de craft en guilde.
Tout fonctionne en jeu, sans serveur ; la synchronisation passe par le canal addon de la guilde.

## État

Sprint 0 : squelette Ace3, scanner de recettes, diagnostic du client.

## Commandes

| Commande | Effet |
|---|---|
| `/cpg` | aide |
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
Core/      initialisation, base de données, utilitaires
Data/      Recettes.lua, généré par Compagnons.Recettes (dépôt wow-compagnons-services)
Modules/   scanner, diagnostic ; puis synchro, commandes, tooltips…
Debug/     journal, futur panneau /cpg debug
tests/     busted
docs/      protocole.md : format des données et des messages
```

## Licence

MIT
