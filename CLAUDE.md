# Compagnons — consignes pour Claude

Addon World of Warcraft: Forever (suivi des métiers et commandes de craft en guilde). Tout se passe en jeu : pas de
serveur, pas de Relais ni de bot Discord (écartés).

## Documentation

- **Les documents (spécifications, conceptions, notes de version à venir) s'écrivent dans Notion**, pas dans des fichiers du
  dépôt. Ne pas créer de nouveau document dans `docs/`.
- Restent dans le dépôt : `README.md`, `CHANGELOG.md` (anglais puis français, lu par les joueurs), `docs/protocole.md` (fait foi
  pour le format des messages et des SavedVariables, parseur compris) et le texte CurseForge.

## Langue

- Code, commentaires, commits et documents en **français**.
- Textes de l'interface dans `Locales/` : `enUS` (référence) et `frFR`, mêmes clés partout.
  `tests/locales_spec.lua` le vérifie (clés identiques, mêmes `%s` / `%d`, aucune clé orpheline ni inutilisée).

## Vérifier

```bash
luacheck .
busted tests        # Lua 5.1, hors jeu
```

`Core/` reste du **Lua pur, sans API WoW**, pour être testé hors jeu. L'accès à l'API du jeu vit dans `Modules/` et `UI/`.

## Règles du jeu (Blizzard)

- L'addon ne valide jamais un échange ni un courrier à la place du joueur, et ne simule aucun clic.
- Les actions protégées exigent un clic réel du joueur ; rien n'est fait en combat.

## Protocole

- Tout changement de format de message ou de SavedVariables passe par `docs/protocole.md`.
- Un message d'une autre version du protocole est ignoré : un changement de version coupe la synchro avec les anciennes.

## Publication

Un tag `vX.Y.Z` déclenche le packager (release GitHub, CurseForge, Wago). Ne pas créer ni pousser de tag sans accord explicite.
