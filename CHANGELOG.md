# Changelog

## 0.6.0

- **Tips:** when you post an order, a new "Tip for the crafter" field (gold and silver) promises the crafter a sum on top of the reagents. A "Suggested" button fills in about 10% of the reagent cost, from the prices you have recorded. The tip shows on the order row and in its tooltip. The addon never sends money: you hand the tip over yourself, by trade or mail, as for any delivery. The tip is fixed when the order is posted; to change it, cancel the order and post it again. Guildmates still on 0.5.x see the order without the tip, and sync is unchanged.
- **Craft tree:** a new "Craft tree" button in the recipe details shows what to craft, step by step, down to raw materials (ore → bar → item), with the number of crafts, the left-overs, your stock across all your characters and the estimated cost of the raw materials. The "+" and "-" buttons change the number of items.
- **Options panel:** the settings of the `/cpg` commands now have a panel in the game's interface options ("Compagnons"), also opened by `/cpg options`. It reads and writes the same settings as the commands.
- **Favorites and ingredient navigation:** a marker on each recipe (row and details) adds it to your favorites, and the filter menu gets "Favorites" and "With my stock" (only recipes whose reagents you all have). Clicking a reagent in the recipe details lists the recipes that use it; click the "Uses: …" button at the top to clear it. Favorites are kept for your account, on your computer only.
- **Order history:** a new "History" tab keeps the orders you saw completed or cancelled (180 days or 500 orders), with a filter by member and profession and a search by item. The Members tab shows how many orders each member crafted and placed. The history is local: each player keeps what their own copy has seen, so the counts can differ between players.
- **Fix:** the recipe list no longer jumps back to the top while you scroll. Each time the guild data changed (a sync, a scan, someone coming online) the list was rebuilt from the top; it now keeps its position, and only a new search, filter or profession goes back to the top.

---

## 0.6.0 (français)

- **Pourboires :** en publiant une commande, un nouveau champ « Pourboire pour le crafteur » (or et argent) promet une somme au crafteur en plus des composants. Un bouton « Suggéré » remplit environ 10 % du coût des composants, d'après les prix relevés. Le pourboire apparaît sur la ligne de la commande et dans son infobulle. L'addon n'envoie jamais d'argent : vous remettez le pourboire vous-même, par échange ou courrier, comme pour toute livraison. Il est fixé à la publication ; pour le changer, annulez la commande et publiez-la de nouveau. Les membres restés en 0.5.x voient la commande sans le pourboire, et la synchro n'est pas coupée.
- **Arbre de craft :** un nouveau bouton « Arbre de craft » dans le détail d'une recette montre ce qu'il faut fabriquer, étage par étage, jusqu'aux matières premières (minerai → barre → objet), avec le nombre de fabrications, les surplus, votre stock sur tous vos personnages et le coût estimé des matières premières. Les boutons « + » et « - » changent le nombre d'objets.
- **Panneau d'options :** les réglages des commandes `/cpg` ont maintenant un panneau dans les options d'interface du jeu (« Compagnons »), ouvert aussi par `/cpg options`. Il lit et écrit les mêmes réglages que les commandes.
- **Favoris et navigation par composant :** un repère sur chaque recette (ligne et détail) l'ajoute à vos favoris, et le menu des filtres gagne « Favoris » et « Avec mon stock » (seulement les recettes dont vous avez tous les composants). Un clic sur un composant dans le détail d'une recette liste les recettes qui l'utilisent ; le bouton « Utilise : … » en haut le retire. Les favoris sont gardés pour votre compte, sur votre ordinateur seulement.
- **Historique des commandes :** un nouvel onglet « Historique » garde les commandes que vous avez vues terminées ou annulées (180 jours ou 500 commandes), avec un filtre par membre et par métier et une recherche par objet. L'onglet Membres indique combien de commandes chaque membre a craftées et passées. L'historique est local : chacun garde ce que sa propre copie a vu, les compteurs peuvent donc différer d'un joueur à l'autre.
- **Correction :** la liste des recettes ne remonte plus en haut pendant que l'on défile. À chaque changement des données de guilde (une synchro, un scan, un membre qui se connecte), la liste était reconstruite depuis le haut ; elle garde maintenant sa position, et seule une nouvelle recherche, un filtre ou un autre métier la ramène en haut.

---

## 0.5.3

- **Version warning, quieter:** the pop-up window, the central text and the sound no longer appear by default, not even once at login. The chat line, the red banner in the workshop window, the "!" on the minimap button and the Members tab still tell you. `/cpg warn silent off` brings the window and sound back.

---

## 0.5.3 (français)

- **Avertissement de version, plus discret :** la fenêtre, le texte central et le son n'apparaissent plus par défaut, pas même une fois à la connexion. La ligne dans le chat, le bandeau rouge de la fenêtre de l'atelier, le « ! » du bouton de minicarte et l'onglet Membres continuent de vous prévenir. `/cpg avertir silence off` ramène la fenêtre et le son.

---

## 0.5.2

- **Crafting cost in the item tooltip:** a craftable item now shows "Crafting cost: …" in its Compagnons block, from the reagent prices you have recorded (auction house and vendors). It is the cheapest recipe, per item. With missing prices it says "at least …"; with old prices it says so. `/cpg tooltips cost` turns it off.
- **Buy price in the tooltip:** below the crafting cost, "Buy price: …" shows the lowest price seen for the item itself (auction house, or vendor), with a note when it is old. Prices of craftable items are now recorded too when you browse the auction house; they stay on your computer and are not shared with the guild. Reagent tooltips show their price as well.
- **"Bind on equip" filter:** the filter menu of the workshop window has a new "Bind on equip" entry, which keeps only recipes whose item binds when equipped (897 of the 2509 recipes). It comes from the game data bundled with the addon, so the list and the profession counters are instant and stable. Enchantings, which create no item, are hidden while it is on.
- **Fix:** vendor prices were not recorded (the game no longer has `GetMerchantItemInfo`; the addon now reads `C_MerchantFrame.GetItemInfo`).

---

## 0.5.2 (français)

- **Coût de fabrication dans l'infobulle :** un objet craftable affiche « Coût de fabrication : … » dans son bloc Compagnons, d'après les prix des composants que vous avez relevés (hôtel des ventes et marchands). C'est la recette la moins chère, par objet. S'il manque des prix, la ligne dit « au moins … » ; si les prix sont anciens, elle le dit. `/cpg infobulles cout` la coupe.
- **Prix d'achat dans l'infobulle :** sous le coût de fabrication, « Prix d'achat : … » donne le prix le plus bas relevé pour l'objet lui-même (hôtel des ventes ou vendeur), avec une mention quand il est ancien. Les prix des objets fabricables sont maintenant aussi relevés quand vous parcourez l'hôtel des ventes ; ils restent sur votre ordinateur et ne sont pas partagés avec la guilde. L'infobulle d'un composant affiche aussi son prix.
- **Filtre « Lié quand équipé » :** le menu des filtres de la fenêtre de l'atelier a une nouvelle entrée « Lié quand équipé », qui ne garde que les recettes dont l'objet est lié quand il est équipé (897 des 2509 recettes). L'information vient des données du jeu embarquées dans l'addon : la liste et les compteurs par métier sont immédiats et stables. Les enchantements, qui ne créent aucun objet, sont masqués tant que le filtre est actif.
- **Correction :** les prix des marchands n'étaient pas relevés (le jeu n'a plus `GetMerchantItemInfo` ; l'addon lit maintenant `C_MerchantFrame.GetItemInfo`).

---

## 0.5.1

**Fixes**
- **Handover assistant:** it now appears the first time you open the trade or mail window after a reload (it only appeared from the second time).
- **Handover assistant, partial stacks:** the game ignored the split when attaching to mail, so a whole stack of 12 left instead of 6. The assistant now first splits the stack into a free bag slot (first click), then places that stack (second click). If no bag slot is free, it tells you.
- **Version warning:** the window, text and sound no longer repeat each time an outdated guildmate logs in. They appear once at your login; `/cpg warn login on` brings the repeat back. The banner, the minimap "!" and the Members tab stay up to date.
- **Bug reports:** the last lines of the log (`/cpg log`) are now saved when you reload or log out, to attach to a report.

---

## 0.5.1 (français)

**Corrections**
- **Assistant de remise :** il s'affiche dès la première ouverture de l'échange ou du courrier après un rechargement (il n'apparaissait qu'à partir de la deuxième).
- **Assistant de remise, tas partiels :** le jeu ignorait le fractionnement vers le courrier, et un tas entier de 12 partait au lieu de 6. L'assistant sépare maintenant le tas dans une case libre des sacs (premier clic), puis pose ce tas (second clic). S'il n'y a aucune case libre, il le dit.
- **Avertissement de version :** la fenêtre, le texte et le son ne reviennent plus à chaque connexion d'un membre en retard. Ils apparaissent une fois à votre connexion ; `/cpg avertir connexion on` rétablit la répétition. Le bandeau, le « ! » de la minicarte et l'onglet Membres restent à jour.
- **Rapports de bug :** les dernières lignes du journal (`/cpg journal`) sont enregistrées au rechargement ou à la déconnexion, pour les joindre à un rapport.

---

## 0.5.0

**Update required for the whole guild.** The sync protocol changes (version 3): guildmates still on 0.4.x no longer sync with you, and you no longer sync with them until they update.

**Delivery**
- **Delivered, awaiting confirmation:** when the crafter hands over the item, the order is now "delivered" and waits for the client to confirm receipt ("Received") or to say it did not arrive ("Not received": the order goes back to the crafter). If the client is their own crafter, the order is completed right away. A delivered order nobody confirms is forgotten after 7 days.
- **One-click confirmation:** when the crafted item arrives by trade or mail from the crafter, the addon offers to confirm receipt (you validate). Items received before the crafter declares the delivery are remembered.
- **Alerts:** the client is told when an order is delivered; the crafter is told when the client confirms or disputes. The minimap button also counts the orders waiting for your confirmation.

**Guild**
- **Crafter suggestion:** the order dialog suggests who to ask: online first, then the least busy, then the highest profession level. One click picks them.
- **Login reminders (once a day per character):** orders to confirm, orders with no taker, orders you took that have not moved, delivered orders the client has not confirmed. An order left open for 30 days is offered for cancellation. `/cpg reminders [on|off|now]`.
- **Outdated versions are impossible to miss:** when a guildmate is still on an older version, a window, a warning text and sound, a red banner over the workshop window, a red "!" on the minimap button and the Members tab all say so. The addon never whispers anyone on its own: the "Warn them" button (window or Members tab) whispers each outdated member to update, once a day at most. A newer version than yours is flagged the same way, so the next protocol change will not be silent. `/cpg warn [login on|off|silent on|off|send]`. The window, text and sound appear once at your login; they repeat each time an outdated member logs in only if you turn on `/cpg warn login on`..
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
- **Une version trop ancienne ne passe plus inaperçue :** quand un membre de la guilde est resté sur une version plus ancienne, une fenêtre, un texte d'avertissement avec son, un bandeau rouge au-dessus de l'atelier, un « ! » rouge sur la minicarte et l'onglet Membres le disent. L'addon n'envoie jamais de chuchotement tout seul : le bouton « Les prévenir » (fenêtre ou onglet Membres) écrit à chaque membre en retard pour qu'il mette à jour, une fois par jour au plus. Une version plus récente que la tienne est signalée de la même façon : le prochain changement de protocole ne sera plus silencieux. `/cpg avertir [connexion on|off|silence on|off|envoyer]`. La fenêtre, le texte et le son apparaissent une fois à votre connexion ; ils reviennent à chaque connexion d'un membre en retard seulement si vous activez `/cpg avertir connexion on`..
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
