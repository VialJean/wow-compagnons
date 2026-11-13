# Changelog

## 0.5.0

**Update required for the whole guild.** The sync protocol changes (version 3): guildmates still on 0.4.x no longer sync with you, and you no longer sync with them until they update.

**Delivery**
- **Delivered, awaiting confirmation:** when the crafter hands over the item, the order is now "delivered" and waits for the client to confirm receipt ("Received") or to say it did not arrive ("Not received": the order goes back to the crafter). If the client is their own crafter, the order is completed right away. A delivered order nobody confirms is forgotten after 7 days.
- **One-click confirmation:** when the crafted item arrives by trade or mail from the crafter, the addon offers to confirm receipt (you validate). Items received before the crafter declares the delivery are remembered.
- **Alerts:** the client is told when an order is delivered; the crafter is told when the client confirms or disputes. The minimap button also counts the orders waiting for your confirmation.

**Guild**
- **Crafter suggestion:** the order dialog suggests who to ask: online first, then the least busy, then the highest profession level. One click picks them.
- **Login reminders (once a day per character):** orders to confirm, orders with no taker, orders you took that have not moved, delivered orders the client has not confirmed. An order left open for 30 days is offered for cancellation. `/cpg reminders [on|off|now]`.
- **Outdated versions are impossible to miss:** when a guildmate is still on an older version, a window, a warning text and sound, a red banner over the workshop window, a red "!" on the minimap button and the Members tab all say so. The first time, the addon whispers that person to update; the "Warn them" button repeats it (once a day at most). A newer version than yours is flagged the same way, so the next protocol change will not be silent. `/cpg warn [auto|silent on|off|send]`.
- **Members tab:** shows each member's addon version.

**Known limits**
- The whisper to an outdated member, the version warning display and the reception detection by trade and mail have not been validated in game yet. Please report problems with `/cpg log`.

---

## 0.5.0 (français)

**Mise à jour obligatoire pour toute la guilde.** Le protocole de synchro change (version 3) : les membres restés en 0.4.x ne se synchronisent plus avec toi, et toi avec eux, tant qu'ils n'ont pas mis à jour.

**Livraison**
- **Livrée, en attente de confirmation :** quand le crafteur remet l'objet, la commande est « livrée » et attend que le client confirme la réception (« Bien reçu ») ou dise qu'il ne l'a pas reçue (« Pas reçu » : la commande revient au crafteur). Si le client est son propre crafteur, la commande est terminée d'emblée. Une commande livrée que personne ne confirme est oubliée au bout de 7 jours.
- **Confirmation en un clic :** quand l'objet fabriqué arrive par échange ou par courrier de ton crafteur, l'addon propose de confirmer la réception (tu valides). Ce qui est reçu avant que le crafteur déclare la livraison est retenu.
- **Alertes :** le client est prévenu quand une commande est livrée ; le crafteur, quand le client confirme ou conteste. Le bouton de minicarte compte aussi les commandes qui attendent ta confirmation.

**Guilde**
- **Suggestion de crafteur :** le dialogue de commande propose à qui la confier : en ligne d'abord, puis le moins chargé, puis le niveau de métier le plus élevé. Un clic pour le choisir.
- **Rappels à la connexion (une fois par jour et par personnage) :** commandes à confirmer, sans preneur, prises sans avancée, livrées que le client n'a pas confirmées. Une commande restée ouverte 30 jours est proposée à l'annulation. `/cpg rappels [on|off|now]`.
- **Une version trop ancienne ne passe plus inaperçue :** quand un membre de la guilde est resté sur une version plus ancienne, une fenêtre, un texte d'avertissement avec son, un bandeau rouge au-dessus de l'atelier, un « ! » rouge sur la minicarte et l'onglet Membres le disent. La première fois, l'addon écrit un chuchotement à cette personne pour qu'elle mette à jour ; le bouton « Les prévenir » le répète (une fois par jour au plus). Une version plus récente que la tienne est signalée de la même façon : le prochain changement de protocole ne sera plus silencieux. `/cpg avertir [auto|silence on|off|envoyer]`.
- **Onglet Membres :** affiche la version de l'addon de chaque membre.

**Limites connues**
- Le chuchotement aux membres en retard, l'affichage de l'avertissement de version et la détection de réception par échange et par courrier n'ont pas encore été validés en jeu. Signale les problèmes avec `/cpg journal`.

---

## 0.4.0

**Delivery**
- **Hand-overs in several parts add up:** materials the client sends in two trades or mails, or a crafted item handed over in two times, are now added together; the order moves forward when the total is enough.
- **Hand-over assistant:** it now also looks in your reagent bag, and tells you where what is missing is (in your bank, or on which of your other characters).
- **Orders:** hovering an order shows the Blizzard tooltip of the item (or spell), then the guild's crafters, then the order details.
- **Alerts:** each alert is written in the chat as soon as it arrives, even during combat (the pop-up still waits for the end of the fight).
- **Diagnostic:** the `/cpg diag` report is translated (English and French).

---

## 0.4.0 (français)

**Livraison**
- **Remises en plusieurs fois :** les matériaux envoyés par le client en deux échanges ou courriers, ou l'objet fabriqué remis en deux fois, s'additionnent ; la commande avance quand le total suffit.
- **Assistant de remise :** il regarde aussi dans le sac de composants, et indique où se trouve ce qui manque (en banque, ou sur lequel de tes autres personnages).
- **Commandes :** au survol, l'infobulle de Blizzard (objet ou sort), puis les crafteurs de la guilde, puis le détail de la commande.
- **Alertes :** chaque alerte s'écrit dans le chat dès qu'elle arrive, même en combat (le cadre attend toujours la fin du combat).
- **Diagnostic :** le rapport de `/cpg diag` est traduit (anglais et français).

---

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
