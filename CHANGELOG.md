# Changelog

## 0.3.1

**Fixes**
- **Hand-over assistant:** the panel next to the mail (or trade) window now closes with it instead of staying on screen.
- **Minimap button:** the count of orders you can fill is now visible on the button (it was drawn under the icon).
- **Members tab:** guildmates who run the addon are listed even before they have scanned their professions ("Professions not scanned yet").

---

## 0.3.1 (français)

**Corrections**
- **Assistant de remise :** le cadre à côté de la fenêtre de courrier (ou d'échange) se ferme avec elle au lieu de rester affiché.
- **Bouton de minicarte :** le nombre de commandes que tu peux remplir est de nouveau visible sur le bouton (il passait sous l'icône).
- **Onglet Membres :** les membres de la guilde qui ont l'addon apparaissent même avant d'avoir scanné leurs métiers (« Métiers pas encore scannés »).

---

## 0.3.0-beta1

**Delivery, from need to hand-over, without leaving the game**
- **Craft tracking:** each successful craft of a recipe you took counts toward the order ("3/5 crafted"), and the guild sees it.
- **Trades:** when a trade completes, the addon recognises materials received from the client or the crafted item handed over, and offers to move the order to "materials received" or "complete" (you confirm).
- **Mail:** same for mail you send and for attachments you collect.
- **Hand-over assistant:** next to the trade or mail window, a button places what you owe (reagents to your crafter, the crafted item to your client), one slot per click. You always validate the trade and send the mail yourself.
- **Shopping list** (`/cpg shopping`): every reagent your open orders need, with the stock of all your characters, and the estimated cost of what is missing.
- **Prices:** reagent prices are recorded when you look at the auction house or visit a vendor, and shared with the guild. A vendor price (unlimited stock, gold only) takes priority over the auction house: it is the real cost. The order dialog shows the total reagent cost.
- **Members tab:** who in the guild runs the addon, with their professions, skill level and known recipes. Filter by profession or online status.
- **Tooltips:** "Useful to <character>" on reagents, disenchant results, and Ctrl+Shift+click to order a recipe.

**Compatibility**
- The sync protocol is still version 2: guildmates on 0.2.0-beta1 keep syncing with you. They just do not see or share prices.

**Known limits**
- Hand-overs split across several trades are not added up.
- The assistant uses your current character's bags only.
- Trades, mail and the hand-over assistant have been tested in game on Forever and work. Please report problems with `/cpg log`.

---

## 0.3.0-beta1 (français)

**De la commande à la livraison, sans quitter le jeu**
- **Suivi des fabrications :** chaque fabrication d'une recette prise compte dans la commande (« 3/5 craftés »), la guilde le voit.
- **Échanges et courriers :** à la fin d'un échange ou d'un courrier, l'addon reconnaît les matériaux reçus ou l'objet remis et propose de faire avancer la commande (tu confirmes).
- **Assistant de remise :** à côté de la fenêtre d'échange ou de courrier, un bouton pose ce que tu dois, un emplacement par clic. Tu valides toujours l'échange et envoies le courrier toi-même.
- **Liste de courses** (`/cpg courses`) : tous les composants de tes commandes, avec le stock de tous tes personnages et le coût estimé du manque.
- **Onglet Membres :** qui a l'addon dans la guilde, avec ses métiers, son niveau et ses recettes connues ; filtre par métier ou par présence en ligne.
- **Prix :** relevés à l'hôtel des ventes et chez les marchands PNJ, puis partagés avec la guilde (un prix de vendeur l'emporte). Coût total des composants dans la commande.
- **Compatibilité :** protocole de synchro toujours en version 2, la 0.2.0-beta1 continue de se synchroniser.

---

## 0.2.0-beta1

- Recipe browser, crafting orders, profession-window panel, alerts, minimap button, guild sync of profiles and orders.
- English and French.
