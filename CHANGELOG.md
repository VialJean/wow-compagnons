# Changelog

## 0.3.0-beta1

**Delivery, from need to hand-over, without leaving the game**
- **Craft tracking:** each successful craft of a recipe you took counts toward the order ("3/5 crafted"), and the guild sees it.
- **Trades:** when a trade completes, the addon recognises materials received from the client or the crafted item handed over, and offers to move the order to "materials received" or "complete" (you confirm).
- **Mail:** same for mail you send and for attachments you collect.
- **Hand-over assistant:** next to the trade or mail window, a button places what you owe (reagents to your crafter, the crafted item to your client), one slot per click. You always validate the trade and send the mail yourself.
- **Shopping list** (`/cpg shopping`): every reagent your open orders need, with the stock of all your characters, and the estimated cost of what is missing.
- **Prices:** reagent prices are recorded when you look at the auction house, and shared with the guild (most recent wins). The order dialog shows the total reagent cost.
- **Tooltips:** "Useful to <character>" on reagents, disenchant results, and Ctrl+Shift+click to order a recipe.

**Compatibility**
- The sync protocol is still version 2: guildmates on 0.2.0-beta1 keep syncing with you. They just do not see or share prices.

**Known limits**
- Hand-overs split across several trades are not added up.
- The assistant uses your current character's bags only.
- The trade, mail and assistant features are new and still being validated on Forever: please report problems with `/cpg log`.

---

## 0.3.0-beta1 (français)

**De la commande à la livraison, sans quitter le jeu**
- **Suivi des fabrications :** chaque fabrication d'une recette prise compte dans la commande (« 3/5 craftés »), la guilde le voit.
- **Échanges et courriers :** à la fin d'un échange ou d'un courrier, l'addon reconnaît les matériaux reçus ou l'objet remis et propose de faire avancer la commande (tu confirmes).
- **Assistant de remise :** à côté de la fenêtre d'échange ou de courrier, un bouton pose ce que tu dois, un emplacement par clic. Tu valides toujours l'échange et envoies le courrier toi-même.
- **Liste de courses** (`/cpg courses`) : tous les composants de tes commandes, avec le stock de tous tes personnages et le coût estimé du manque.
- **Prix :** relevés à l'hôtel des ventes puis partagés avec la guilde. Coût total des composants dans la commande.
- **Compatibilité :** protocole de synchro toujours en version 2, la 0.2.0-beta1 continue de se synchroniser.

---

## 0.2.0-beta1

- Recipe browser, crafting orders, profession-window panel, alerts, minimap button, guild sync of profiles and orders.
- English and French.
