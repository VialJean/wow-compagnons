-- Texte des infobulles d'objet (voir docs/infobulles.md). Lua pur, sans API du jeu :
-- le contexte fournit les données et ce module renvoie une liste de lignes.
--
--   ligne = { texte = "...", r = 1, g = 1, b = 1 }
--
-- contexte = {
--   catalogue,                 ns.catalogue
--   commandes,                 table id -> commande
--   miens,                     ensemble des clés de nos personnages
--   connait(spellID),          clé de l'un de nos personnages qui connaît la recette, ou nil
--   stock(itemID),             quantité possédée (sacs et banque)
--   enLigne(cle),              vrai si le personnage est connecté
--   maj,                       vrai si Maj est enfoncé
--   options,                   { objet, composant, personne, commander }
--   couleurClasse(classe),     r, g, b
--   couleurQualite(qualite),   r, g, b
-- }
local _, ns = ...

local Infobulles = {}
ns.Infobulles = Infobulles

local MAX_NOMS = 3
local MAX_RECETTES_DETAIL = 8
local MAX_MEMBRES = 4

local OR = { 0.88, 0.7, 0.32 }
local BLANC = { 1, 1, 1 }
local GRIS = { 0.66, 0.61, 0.53 }
local ORANGE = { 0.91, 0.66, 0.31 }
local BLEU = { 0.5, 0.7, 1 }
local ROUGE_DOUX = { 0.9, 0.5, 0.42 }

local function ligne(texte, couleur)
	return { texte = texte, r = couleur[1], g = couleur[2], b = couleur[3] }
end

local function hex(r, g, b)
	local function o(x) return math.floor(x * 255 + 0.5) end
	return string.format("|cff%02x%02x%02x", o(r), o(g), o(b))
end

local function estFinale(o)
	return o.statut == "terminee" or o.statut == "annulee"
end

local function nomRecette(ctx, spellID)
	local r = ctx.catalogue.donnees.recettes[spellID]
	return r and r.nom or "?"
end

-- ---------------------------------------------------------------------------------------------
-- Objet craftable
-- ---------------------------------------------------------------------------------------------

--- Union des crafteurs des recettes données, en ligne d'abord, puis par nom.
local function crafteursDe(ctx, recettes)
	local vus, liste = {}, {}
	for _, spellID in ipairs(recettes) do
		for _, c in ipairs(ctx.catalogue:Crafteurs(spellID)) do
			if not vus[c.cle] then
				vus[c.cle] = true
				liste[#liste + 1] = { cle = c.cle, nom = c.nom, classe = c.classe, enLigne = ctx.enLigne(c.cle) and true or false }
			end
		end
	end
	table.sort(liste, function(a, b)
		if a.enLigne ~= b.enLigne then return a.enLigne end
		if a.nom ~= b.nom then return a.nom < b.nom end
		return a.cle < b.cle
	end)
	return liste
end

local function nomsColores(ctx, crafteurs)
	local morceaux = {}
	for i = 1, math.min(#crafteurs, MAX_NOMS) do
		local c = crafteurs[i]
		local r, g, b = ctx.couleurClasse(c.classe)
		local texte = hex(r, g, b) .. c.nom .. "|r"
		if c.enLigne then texte = texte .. " |cff5fd068(" .. ns.L.EN_LIGNE .. ")|r" end
		morceaux[i] = texte
	end
	local texte = table.concat(morceaux, ", ")
	if #crafteurs > MAX_NOMS then texte = texte .. " " .. string.format(ns.L.INFO_ET_AUTRES, #crafteurs - MAX_NOMS) end
	return texte
end

--- Lignes à ajouter à l'infobulle d'un objet créé par une recette de la base, ou nil.
function Infobulles.objet(ctx, itemID)
	if not ctx or not ctx.options or not ctx.options.objet or not ctx.catalogue then return nil end
	local recettes = ctx.catalogue:RecettesCreant(itemID)
	if #recettes == 0 then return nil end

	local lignes = { ligne(ns.L.INFO_TITRE, OR) }
	local crafteurs = crafteursDe(ctx, recettes)
	if #crafteurs > 0 then
		lignes[#lignes + 1] = ligne(ns.L.INFO_CRAFTABLE_PAR .. " " .. nomsColores(ctx, crafteurs), BLANC)
	elseif ctx.options.personne then
		lignes[#lignes + 1] = ligne(ns.L.INFO_PERSONNE, ROUGE_DOUX)
	end

	-- Commandes pour cet objet : toutes celles qui ne sont pas finales, dont celles que l'on peut remplir.
	local ensemble = {}
	for _, spellID in ipairs(recettes) do ensemble[spellID] = true end
	local total, remplissables = 0, 0
	for _, o in pairs(ctx.commandes or {}) do
		if ensemble[o.spell] and not estFinale(o) then
			total = total + 1
			if o.statut == "ouverte" and not ctx.miens[o.client] and ctx.connait(o.spell)
				and (not o.crafteur or ctx.miens[o.crafteur]) then
				remplissables = remplissables + 1
			end
		end
	end
	if total > 0 then
		local texte = string.format(total == 1 and ns.L.INFO_COMMANDE or ns.L.INFO_COMMANDES, total)
		if remplissables > 0 then texte = texte .. " · " .. string.format(ns.L.INFO_TU_PEUX, remplissables) end
		lignes[#lignes + 1] = ligne(texte, BLANC)
	end

	local touche = ctx.options.commander
	if touche == "ctrlmaj" then
		lignes[#lignes + 1] = ligne(ns.L.INFO_COMMANDER_CTRLMAJ, GRIS)
	elseif touche == "maj" then
		lignes[#lignes + 1] = ligne(ns.L.INFO_COMMANDER_MAJ, GRIS)
	end
	return lignes
end

-- ---------------------------------------------------------------------------------------------
-- Composant
-- ---------------------------------------------------------------------------------------------

--- « manque » et « à fournir » pour nos commandes qui utilisent ce composant.
local function lignesCommandes(ctx, itemID, recettes)
	local ensemble = {}
	for _, spellID in ipairs(recettes) do ensemble[spellID] = true end

	local manques, requis = {}, {}
	for _, o in pairs(ctx.commandes or {}) do
		if ensemble[o.spell] and not estFinale(o) then
			local besoin = ctx.catalogue:QuantiteComposant(o.spell, itemID) * o.qte
			if ctx.miens[o.client] and o.mats ~= "crafteur" then
				local manque = besoin - ctx.stock(itemID)
				if manque > 0 then manques[#manques + 1] = { o = o, manque = manque } end
			end
			if o.assigne and ctx.miens[o.assigne] and o.mats == "crafteur" and (o.statut == "prise" or o.statut == "mats") then
				requis[#requis + 1] = { o = o, besoin = besoin }
			end
		end
	end
	local function parCommande(a, b)
		if a.o.maj ~= b.o.maj then return a.o.maj > b.o.maj end
		return a.o.id < b.o.id
	end
	table.sort(manques, parCommande)
	table.sort(requis, parCommande)

	local lignes = {}
	if #manques > 0 then
		local m = manques[1]
		lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_MANQUE, m.manque, nomRecette(ctx, m.o.spell)), ORANGE)
		if #manques > 1 then
			lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_AUTRES_COMMANDES, #manques - 1), ORANGE)
		end
	end
	if #requis > 0 then
		local r = requis[1]
		lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_REQUIS, nomRecette(ctx, r.o.spell), r.besoin), BLEU)
		if #requis > 1 then
			lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_AUTRES_COMMANDES, #requis - 1), BLEU)
		end
	end
	return lignes
end

--- Par membre : nombre de recettes utilisant le composant, dont celles qui font encore progresser.
local function crafteursDuComposant(ctx, recettes)
	local parCle = {}
	for _, spellID in ipairs(recettes) do
		local gris = (ctx.catalogue.donnees.recettes[spellID].seuils or {})[4]
		for _, c in ipairs(ctx.catalogue:Crafteurs(spellID)) do
			local e = parCle[c.cle]
			if not e then
				e = { cle = c.cle, nom = c.nom, classe = c.classe, n = 0, monte = 0,
					mien = ctx.miens[c.cle] and true or false, enLigne = ctx.enLigne(c.cle) and true or false }
				parCle[c.cle] = e
			end
			e.n = e.n + 1
			if gris and (c.niveau or 0) < gris then e.monte = e.monte + 1 end
		end
	end
	local liste = {}
	for _, e in pairs(parCle) do liste[#liste + 1] = e end
	table.sort(liste, function(a, b)
		-- Qui en a le plus l'usage : d'abord ceux pour qui ça fait encore progresser, puis le plus de recettes.
		if a.monte ~= b.monte then return a.monte > b.monte end
		if a.n ~= b.n then return a.n > b.n end
		if a.enLigne ~= b.enLigne then return a.enLigne end
		if a.nom ~= b.nom then return a.nom < b.nom end
		return a.cle < b.cle
	end)
	return liste
end

--- « Utile à Brumefer · 4 recettes, dont 1 qui monte encore » : qui, dans la guilde, a l'usage du composant.
local function lignesUtileA(ctx, recettes)
	local membres = crafteursDuComposant(ctx, recettes)
	if #membres == 0 then
		return { ligne(string.format(ns.L.INFO_UTILE_PERSONNE, #recettes), GRIS) }
	end
	local lignes = {}
	for i = 1, math.min(#membres, MAX_MEMBRES) do
		local m = membres[i]
		local r, g, b = ctx.couleurClasse(m.classe)
		local nom = hex(r, g, b) .. m.nom .. "|r"
		if m.mien then nom = nom .. " (" .. ns.L.INFO_TOI_COURT .. ")" end
		if m.enLigne and not m.mien then nom = nom .. " |cff5fd068(" .. ns.L.EN_LIGNE .. ")|r" end
		local detail = string.format(m.n == 1 and ns.L.INFO_UNE_RECETTE_COURT or ns.L.INFO_N_RECETTES_COURT, m.n)
		if m.monte > 0 then detail = detail .. ", " .. string.format(ns.L.INFO_MONTE_COURT, m.monte) end
		lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_UTILE_A, nom, detail), BLANC)
	end
	if #membres > MAX_MEMBRES then
		lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_ET_AUTRES_MEMBRES, #membres - MAX_MEMBRES), GRIS)
	end
	return lignes
end

--- Recettes qui utilisent le composant, classées par intérêt : celles que je connais et qui font encore
-- progresser, celles que je connais, celles qu'un membre connaît, les autres ; puis par niveau et par nom.
local function recettesUtiles(ctx, recettes)
	local liste = {}
	for _, spellID in ipairs(recettes) do
		local r = ctx.catalogue.donnees.recettes[spellID]
		local gris = (r.seuils or {})[4]
		local mienne, monte = false, false
		local autres = {}
		for _, c in ipairs(ctx.catalogue:Crafteurs(spellID)) do
			if ctx.miens[c.cle] then
				mienne = true
				if gris and (c.niveau or 0) < gris then monte = true end
			else
				autres[#autres + 1] = c.nom
			end
		end
		local rang
		if mienne and monte then rang = 1
		elseif mienne then rang = 2
		elseif #autres > 0 then rang = 3
		else rang = 4 end
		liste[#liste + 1] = { spell = spellID, recette = r, rang = rang, mienne = mienne, monte = monte, autres = autres }
	end
	table.sort(liste, function(a, b)
		if a.rang ~= b.rang then return a.rang < b.rang end
		if a.recette.niveau ~= b.recette.niveau then return a.recette.niveau < b.recette.niveau end
		return a.recette.nom < b.recette.nom
	end)
	return liste
end

--- Ce qu'on sait de la recette à droite de son nom : moi, ou les autres crafteurs, ou personne.
local function precision(e)
	if e.mienne then return e.monte and ns.L.INFO_TOI_MONTE or ns.L.INFO_TOI end
	if #e.autres == 0 then return ns.L.INFO_PERSONNE_COURT end
	local texte = table.concat(e.autres, ", ", 1, math.min(#e.autres, 2))
	if #e.autres > 2 then texte = texte .. " " .. string.format(ns.L.INFO_ET_AUTRES, #e.autres - 2) end
	return texte
end

--- Lignes « Utile pour » (avec Maj) : les recettes les plus intéressantes, puis le nombre des autres.
local function lignesUtilePour(ctx, recettes)
	local utiles = recettesUtiles(ctx, recettes)
	local lignes = { ligne(string.format(ns.L.INFO_UTILE_POUR, #utiles), GRIS) }
	for i = 1, math.min(#utiles, MAX_RECETTES_DETAIL) do
		local e = utiles[i]
		local qr, qg, qb = ctx.couleurQualite(e.recette.qualite)
		lignes[#lignes + 1] = ligne(string.format("  %s%s|r · %s", hex(qr, qg, qb), e.recette.nom, precision(e)), BLANC)
	end
	if #utiles > MAX_RECETTES_DETAIL then
		lignes[#lignes + 1] = ligne(string.format(ns.L.INFO_ET_AUTRES_RECETTES, #utiles - MAX_RECETTES_DETAIL), GRIS)
	end
	return lignes
end

--- Lignes à ajouter à l'infobulle d'un objet utilisé comme composant, ou nil.
function Infobulles.composant(ctx, itemID)
	if not ctx or not ctx.options or not ctx.options.composant or not ctx.catalogue then return nil end
	local recettes = ctx.catalogue:RecettesUtilisant(itemID)
	if #recettes == 0 then return nil end

	local lignes = { ligne(ns.L.INFO_TITRE_COMPOSANT, OR) }
	for _, l in ipairs(lignesCommandes(ctx, itemID, recettes)) do lignes[#lignes + 1] = l end

	if ctx.maj then
		-- Détail : les recettes les plus intéressantes, avec qui les connaît.
		for _, l in ipairs(lignesUtilePour(ctx, recettes)) do lignes[#lignes + 1] = l end
	else
		-- Par défaut : à qui l'objet est utile, pour savoir qui en a l'usage quand on le trouve.
		for _, l in ipairs(lignesUtileA(ctx, recettes)) do lignes[#lignes + 1] = l end
		lignes[#lignes + 1] = ligne(ns.L.INFO_MAJ_DETAIL, GRIS)
	end
	return lignes
end

-- ---------------------------------------------------------------------------------------------
-- Désenchantement
-- ---------------------------------------------------------------------------------------------

local MAX_ENCHANTEURS = 4

--- Lignes « désenchantement » pour une pièce d'équipement, ou nil si l'objet ne se désenchante pas.
-- ctx.infoObjet(itemID) renvoie { classe, sous, qualite, niveau } ou nil (informations pas encore en cache).
function Infobulles.desenchanter(ctx, itemID)
	if not ctx or not ctx.options or not ctx.options.desenchantement or not ctx.catalogue or not ctx.infoObjet then
		return nil
	end
	local info = ctx.infoObjet(itemID)
	if not info then return nil end
	if not ns.Desenchanter.tranche(ns.Desenchantement, info.classe, info.sous, info.qualite, info.niveau) then
		return nil
	end

	local lignes = {
		ligne(ns.L.INFO_TITRE_DESENCH, OR),
		ligne(string.format(ns.L.INFO_DESENCH_OK, info.niveau), BLANC),
	}

	local liste = {}
	for _, e in ipairs(ctx.catalogue:Enchanteurs()) do
		liste[#liste + 1] = {
			nom = e.nom, classe = e.classe, niveau = e.niveau, cle = e.cle,
			mien = ctx.miens[e.cle] and true or false, enLigne = ctx.enLigne(e.cle) and true or false,
		}
	end
	if #liste == 0 then
		if ctx.options.aucunEnchanteur then lignes[#lignes + 1] = ligne(ns.L.INFO_AUCUN_ENCHANTEUR, GRIS) end
		return lignes
	end
	-- En ligne d'abord, puis le plus haut niveau, puis le nom.
	table.sort(liste, function(a, b)
		if a.enLigne ~= b.enLigne then return a.enLigne end
		if a.niveau ~= b.niveau then return a.niveau > b.niveau end
		if a.nom ~= b.nom then return a.nom < b.nom end
		return a.cle < b.cle
	end)

	local morceaux = {}
	for i = 1, math.min(#liste, MAX_ENCHANTEURS) do
		local e = liste[i]
		local r, g, b = ctx.couleurClasse(e.classe)
		local precisions = {}
		if e.mien then precisions[#precisions + 1] = ns.L.INFO_TOI_COURT
		elseif e.enLigne then precisions[#precisions + 1] = "|cff5fd068" .. ns.L.EN_LIGNE .. "|r" end
		precisions[#precisions + 1] = tostring(e.niveau)
		morceaux[i] = string.format("%s%s|r (%s)", hex(r, g, b), e.nom, table.concat(precisions, ", "))
	end
	local texte = ns.L.INFO_ENCHANTEURS .. " " .. table.concat(morceaux, ", ")
	if #liste > MAX_ENCHANTEURS then texte = texte .. " " .. string.format(ns.L.INFO_ET_AUTRES, #liste - MAX_ENCHANTEURS) end
	lignes[#lignes + 1] = ligne(texte, BLANC)
	return lignes
end

--- Toutes les lignes d'un objet : « objet craftable », « composant », « désenchantement », séparés par une ligne vide.
function Infobulles.lignes(ctx, itemID)
	local blocs = {}
	for _, bloc in ipairs({
		Infobulles.objet(ctx, itemID) or false,
		Infobulles.composant(ctx, itemID) or false,
		Infobulles.desenchanter(ctx, itemID) or false,
	}) do
		if bloc then blocs[#blocs + 1] = bloc end
	end
	if #blocs == 0 then return nil end

	local lignes = {}
	for i, bloc in ipairs(blocs) do
		if i > 1 then lignes[#lignes + 1] = { texte = " ", r = 1, g = 1, b = 1 } end
		for _, l in ipairs(bloc) do lignes[#lignes + 1] = l end
	end
	return lignes
end

return Infobulles
