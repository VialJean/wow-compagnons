-- Tests hors jeu du texte des infobulles d'objet (docs/infobulles.md, §2). busted tests
local function charger()
	local ns = {}
	-- Les assertions de ce fichier portent sur le texte français : on simule un client en frFR.
	rawset(_G, "GetLocale", function() return "frFR" end)
	for _, fichier in ipairs({ "Locales/enUS.lua", "Locales/frFR.lua", "Core/Locales.lua", "Core/Bitset.lua",
		"Core/Catalogue.lua", "Core/Profil.lua", "Core/Commandes.lua", "Core/Desenchanter.lua",
		"Data/Desenchantement.lua", "Core/Infobulles.lua" }) do
		assert(loadfile(fichier))("Compagnons", ns)
	end
	rawset(_G, "GetLocale", nil)
	return ns
end

local ns = charger()

local donnees = {
	metiers = { [171] = { nom = "Alchimie", ordre = { 2329, 2331, 3000, 4000 } } },
	objets = {},
	recettes = {
		-- 2454 : créé par 2329 ; composants 2449 x1 et 3371 x1
		[2329] = { metier = 171, indice = 1, niveau = 1, nom = "Elixir de Force mineure", objet = 2454, qte = 1,
			qualite = 1, seuils = { 1, 55, 75, 95 }, composants = { { 2449, 1 }, { 3371, 1 } } },
		[2331] = { metier = 171, indice = 2, niveau = 1, nom = "Potion de mana mineure", objet = 2455, qte = 1,
			qualite = 1, seuils = { 1, 65, 85, 105 }, composants = { { 3371, 1 } } },
		[3000] = { metier = 171, indice = 3, niveau = 40, nom = "Huile de glace", objet = 9999, qte = 1,
			qualite = 2, seuils = { 40, 90, 110, 130 }, composants = { { 2449, 2 } } },
		-- 9999 est à la fois créé (3000) et composant (4000)
		[4000] = { metier = 171, indice = 4, niveau = 60, nom = "Flacon de glace", objet = 7777, qte = 1,
			qualite = 3, seuils = { 60, 100, 120, 140 }, composants = { { 9999, 1 } } },
	},
}

local function perso(nom, classe, niveau, recettes)
	return { nom = nom, classe = classe, metiers = { [171] = { id = 171, nom = "Alchimie", niveau = niveau, recettes = recettes } } }
end

local COULEURS = { SHAMAN = { 0, 0.44, 0.87 }, WARRIOR = { 0.78, 0.61, 0.43 } }

--- Contexte de test : `connectes` = ensemble des clés connectées.
local function contexte(personnages, options)
	local c = {
		catalogue = ns.Catalogue.nouveau(donnees, personnages, {}),
		commandes = {},
		miens = { ["Jean Vialjean"] = true },
		connait = function(spell)
			for _, cr in ipairs(ns.Catalogue.nouveau(donnees, personnages, {}):Crafteurs(spell)) do
				if cr.cle == "Jean Vialjean" then return cr.cle end
			end
		end,
		stock = function() return 0 end,
		enLigne = function() return false end,
		maj = false,
		options = options or { objet = true, composant = true, personne = false, commander = "ctrlmaj" },
		couleurClasse = function(classe)
			local col = COULEURS[classe] or { 0.8, 0.8, 0.8 }
			return col[1], col[2], col[3]
		end,
		couleurQualite = function() return 1, 1, 1 end,
	}
	return c
end

local function textes(lignes)
	local t = {}
	for i, l in ipairs(lignes or {}) do t[i] = (l.texte:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	return t
end

local function contient(lignes, fragment)
	for _, t in ipairs(textes(lignes)) do
		if t:find(fragment, 1, true) then return true end
	end
	return false
end

local function ligneEgale(lignes, texte)
	for _, t in ipairs(textes(lignes)) do
		if t == texte then return true end
	end
	return false
end

local function commande(ctx, o)
	o.maintenant = 1000
	local c = ns.Commandes.nouvelle(o)
	for k, v in pairs(o) do if k ~= "maintenant" then c[k] = v end end
	ctx.commandes[c.id] = c
	return c
end

describe("Infobulles : objet craftable", function()
	local personnages

	before_each(function()
		personnages = {
			["Jean Vialjean"] = perso("Jean Vialjean", "SHAMAN", 60, { 2329 }),
			["Brumefer Hautrocher"] = perso("Brumefer Hautrocher", "WARRIOR", 100, { 2329, 2331 }),
		}
	end)

	it("liste les crafteurs, en ligne d'abord", function()
		local ctx = contexte(personnages)
		ctx.enLigne = function(cle) return cle == "Jean Vialjean" end
		local l = ns.Infobulles.objet(ctx, 2454)
		assert.are.equal("Compagnons", textes(l)[1])
		assert.are.equal("Craftable par Jean Vialjean (en ligne), Brumefer Hautrocher", textes(l)[2])
	end)

	it("limite à trois noms puis « et N autres »", function()
		for i = 1, 4 do
			personnages["Membre" .. i .. " Test"] = perso("Membre" .. i .. " Test", "MAGE", 10, { 2329 })
		end
		local ctx = contexte(personnages)
		local l = ns.Infobulles.objet(ctx, 2454)
		assert.is_true(contient(l, "et 3 autres"))
	end)

	it("fusionne les crafteurs de toutes les recettes qui créent l'objet", function()
		donnees.recettes[5000] = { metier = 171, indice = 5, niveau = 5, nom = "Autre rang", objet = 2454, qte = 1,
			qualite = 1, seuils = { 5, 10, 15, 20 }, composants = { { 2449, 1 } } }
		donnees.metiers[171].ordre[5] = 5000
		personnages["Camille Petit"] = perso("Camille Petit", "MAGE", 30, { 5000 })
		local ctx = contexte(personnages)
		local l = ns.Infobulles.objet(ctx, 2454)
		donnees.recettes[5000], donnees.metiers[171].ordre[5] = nil, nil
		assert.is_true(contient(l, "Camille Petit"))
		assert.is_true(contient(l, "Brumefer Hautrocher"))
	end)

	it("n'ajoute rien pour un objet inconnu de la base ou si l'option est coupée", function()
		local ctx = contexte(personnages)
		assert.is_nil(ns.Infobulles.objet(ctx, 123456))
		ctx.options.objet = false
		assert.is_nil(ns.Infobulles.objet(ctx, 2454))
		assert.is_nil(ns.Infobulles.objet(nil, 2454))
	end)

	it("« Personne ne sait la fabriquer » seulement avec l'option", function()
		local ctx = contexte(personnages)
		assert.is_false(contient(ns.Infobulles.objet(ctx, 9999), "Personne"))
		ctx.options.personne = true
		assert.is_true(contient(ns.Infobulles.objet(ctx, 9999), "Personne ne sait la fabriquer"))
	end)

	it("compte les commandes ouvertes et celles que je peux remplir", function()
		local ctx = contexte(personnages)
		commande(ctx, { client = "Wilgar Rolpik", spell = 2329, qte = 2 })
		commande(ctx, { client = "Wilgar Rolpik", spell = 3000, qte = 1 })   -- autre objet : ignorée
		local l = ns.Infobulles.objet(ctx, 2454)
		assert.is_true(contient(l, "1 commande ouverte · tu peux en remplir 1"))

		-- une commande finale ne compte plus
		commande(ctx, { client = "Wilgar Rolpik", spell = 2329, qte = 1, statut = "terminee", assigne = "Elias Legentillet" })
		assert.is_true(contient(ns.Infobulles.objet(ctx, 2454), "1 commande ouverte"))
		-- une commande pour un autre crafteur n'est pas remplissable par moi
		commande(ctx, { client = "Wilgar Rolpik", spell = 2329, qte = 1, crafteur = "Elias Legentillet" })
		assert.is_true(contient(ns.Infobulles.objet(ctx, 2454), "2 commandes ouvertes · tu peux en remplir 1"))
	end)

	it("affiche l'indication de commande rapide selon l'option", function()
		local ctx = contexte(personnages)
		assert.is_true(contient(ns.Infobulles.objet(ctx, 2454), "Ctrl+Maj+clic : commander"))
		ctx.options.commander = "maj"
		assert.is_true(contient(ns.Infobulles.objet(ctx, 2454), "Maj+clic : commander"))
		ctx.options.commander = "aucune"
		assert.is_false(contient(ns.Infobulles.objet(ctx, 2454), "clic : commander"))
	end)

	it("colore les noms avec la couleur de classe", function()
		local ctx = contexte(personnages)
		local l = ns.Infobulles.objet(ctx, 2454)
		assert.is_not_nil(l[2].texte:find("|cffc79c6eBrumefer", 1, true)) -- guerrier : 0.78, 0.61, 0.43
		assert.is_not_nil(l[2].texte:find("|cff0070deJean", 1, true))      -- chaman : 0, 0.44, 0.87
	end)
end)

describe("Infobulles : composant", function()
	local personnages, ctx

	before_each(function()
		personnages = {
			["Jean Vialjean"] = perso("Jean Vialjean", "SHAMAN", 60, { 2329 }),
			["Brumefer Hautrocher"] = perso("Brumefer Hautrocher", "WARRIOR", 100, { 2329, 2331 }),
		}
		ctx = contexte(personnages)
	end)

	it("« Utile à » liste qui a l'usage du composant, avec leur nombre de recettes", function()
		local l = ns.Infobulles.composant(ctx, 3371) -- utilisé par 2329 et 2331
		local t = textes(l)
		assert.are.equal("Compagnons · composant", t[1])
		-- Brumefer (niveau 100) : 2329 gris 95 -> ne monte plus ; 2331 gris 105 -> monte encore
		assert.is_true(ligneEgale(l, "Utile à Brumefer Hautrocher · 2 recettes, dont 1 qui monte encore"))
		assert.is_true(ligneEgale(l, "Utile à Jean Vialjean (toi) · 1 recette, dont 1 qui monte encore"))
		assert.are.equal("Maj : détail des recettes", t[#t])
	end)

	it("« Utile à » met en premier ceux pour qui l'objet fait encore progresser", function()
		-- Brumefer a plus de recettes mais plus rien ne monte pour lui ; Jean, lui, progresse encore
		personnages["Brumefer Hautrocher"].metiers[171].niveau = 300
		ctx = contexte(personnages)
		local t = textes(ns.Infobulles.composant(ctx, 3371))
		assert.are.equal("Utile à Jean Vialjean (toi) · 1 recette, dont 1 qui monte encore", t[2])
		assert.are.equal("Utile à Brumefer Hautrocher · 2 recettes", t[3])
	end)

	it("« Utile à » signale les membres en ligne, pas moi", function()
		ctx.enLigne = function() return true end
		local l = ns.Infobulles.composant(ctx, 3371)
		assert.is_true(contient(l, "Utile à Brumefer Hautrocher (en ligne) ·"))
		assert.is_false(contient(l, "(toi) (en ligne)"))
	end)

	it("« Utile à » se limite à quatre membres puis compte les autres", function()
		for i = 1, 5 do personnages["Membre" .. i .. " Test"] = perso("Membre" .. i .. " Test", "MAGE", 10, { 2331 }) end
		ctx = contexte(personnages)
		local l = ns.Infobulles.composant(ctx, 3371)
		assert.is_true(ligneEgale(l, "et 3 autres membres"))
	end)

	it("« Utile à » prévient quand personne ne connaît les recettes qui l'utilisent", function()
		local l = ns.Infobulles.composant(contexte({}), 3371)
		assert.is_true(ligneEgale(l, "Utile pour 2 recettes que personne ne connaît encore"))
	end)

	it("avec Maj, « Utile pour » classe mes recettes qui montent d'abord, puis celles des autres", function()
		ctx.maj = true
		local l = ns.Infobulles.composant(ctx, 3371)
		local t = textes(l)
		assert.are.equal("Utile pour (2 recettes) :", t[2])
		assert.are.equal("  Elixir de Force mineure · tu la connais, monte encore", t[3])
		assert.are.equal("  Potion de mana mineure · Brumefer Hautrocher", t[4])
		assert.is_false(contient(l, "Maj : détail"))
		assert.is_false(contient(l, "Utile à"))
	end)

	it("avec Maj, distingue une recette que je connais mais qui ne monte plus", function()
		personnages["Jean Vialjean"].metiers[171].niveau = 300
		ctx = contexte(personnages)
		ctx.maj = true
		assert.is_true(ligneEgale(ns.Infobulles.composant(ctx, 3371), "  Elixir de Force mineure · tu la connais"))
	end)

	it("avec Maj, met les recettes que personne ne connaît en dernier", function()
		ctx.maj = true
		local t = textes(ns.Infobulles.composant(ctx, 2449)) -- utilisé par 2329 (connue) et 3000 (inconnue)
		assert.are.equal("Utile pour (2 recettes) :", t[2])
		assert.are.equal("  Elixir de Force mineure · tu la connais, monte encore", t[3])
		assert.are.equal("  Huile de glace · personne", t[4])
	end)

	it("avec Maj, se limite à huit recettes puis compte les autres", function()
		for i = 1, 8 do
			local id = 6000 + i
			donnees.recettes[id] = { metier = 171, indice = 5 + i, niveau = 10 + i, nom = "Extra " .. i, objet = 0, qte = 0,
				qualite = 1, seuils = { 1, 2, 3, 4 }, composants = { { 3371, 1 } } }
			donnees.metiers[171].ordre[5 + i] = id
		end
		ctx = contexte(personnages)
		ctx.maj = true
		local l = ns.Infobulles.composant(ctx, 3371)
		for i = 1, 8 do donnees.recettes[6000 + i], donnees.metiers[171].ordre[5 + i] = nil, nil end
		assert.is_true(ligneEgale(l, "Utile pour (10 recettes) :"))
		assert.is_true(ligneEgale(l, "… et 2 autres recettes"))
	end)

	it("avec Maj, abrège la liste de crafteurs d'une recette (2 noms puis « et N autres »)", function()
		for i = 1, 4 do personnages["Membre" .. i .. " Test"] = perso("Membre" .. i .. " Test", "MAGE", 10, { 2331 }) end
		ctx = contexte(personnages)
		ctx.maj = true
		local trouve = false
		for _, t in ipairs(textes(ns.Infobulles.composant(ctx, 3371))) do
			if t:find("Potion de mana mineure ·", 1, true) and t:find("et 3 autres", 1, true) then trouve = true end
		end
		assert.is_true(trouve)
	end)

	it("calcule ce qu'il me manque pour mes commandes, sacs et banque compris", function()
		commande(ctx, { client = "Jean Vialjean", spell = 3000, qte = 10, mats = "partie" }) -- 2 x 10 = 20 de 2449
		ctx.stock = function() return 7 end
		local t = textes(ns.Infobulles.composant(ctx, 2449))
		assert.are.equal("Manque 13 pour ta commande : Huile de glace", t[2])
	end)

	it("ne signale pas de manque quand j'ai assez, ni pour une commande des autres", function()
		commande(ctx, { client = "Jean Vialjean", spell = 3000, qte = 1, mats = "partie" })
		ctx.stock = function() return 50 end
		assert.is_false(contient(ns.Infobulles.composant(ctx, 2449), "Manque"))
		commande(ctx, { client = "Wilgar Rolpik", spell = 3000, qte = 500 })
		ctx.stock = function() return 0 end
		assert.is_false(contient(ns.Infobulles.composant(ctx, 2449), "Manque 1000"))
	end)

	it("ne compte pas le manque si le crafteur fournit les composants", function()
		commande(ctx, { client = "Jean Vialjean", spell = 3000, qte = 10, mats = "crafteur" })
		assert.is_false(contient(ns.Infobulles.composant(ctx, 2449), "Manque"))
	end)

	it("indique ce qui est requis pour une commande que j'ai prise et dont le crafteur fournit les composants", function()
		commande(ctx, { client = "Wilgar Rolpik", spell = 3000, qte = 3, mats = "crafteur", statut = "prise",
			assigne = "Jean Vialjean", par = "Jean Vialjean" })
		assert.is_true(contient(ns.Infobulles.composant(ctx, 2449), "Requis pour ta commande de Huile de glace : 6"))
	end)

	it("résume « et N autres commandes »", function()
		commande(ctx, { client = "Jean Vialjean", spell = 3000, qte = 10 })
		commande(ctx, { client = "Jean Vialjean", spell = 3000, qte = 20 })
		assert.is_true(contient(ns.Infobulles.composant(ctx, 2449), "et 1 autre(s) commande(s)"))
	end)

	it("n'ajoute rien pour un objet qui n'est pas un composant ou si l'option est coupée", function()
		assert.is_nil(ns.Infobulles.composant(ctx, 2454))
		ctx.options.composant = false
		assert.is_nil(ns.Infobulles.composant(ctx, 3371))
	end)
end)

describe("Infobulles : objet craftable et composant à la fois", function()
	it("affiche les deux blocs, séparés par une ligne vide, objet craftable d'abord", function()
		local personnages = { ["Jean Vialjean"] = perso("Jean Vialjean", "SHAMAN", 60, { 3000, 4000 }) }
		local ctx = contexte(personnages)
		local t = textes(ns.Infobulles.lignes(ctx, 9999))
		assert.are.equal("Compagnons", t[1])
		local vide
		for i, x in ipairs(t) do if x == " " then vide = i end end
		assert.is_not_nil(vide)
		assert.are.equal("Compagnons · composant", t[vide + 1])
	end)

	it("renvoie nil pour un objet qui n'intéresse pas l'addon", function()
		local ctx = contexte({})
		assert.is_nil(ns.Infobulles.lignes(ctx, 424242))
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- Désenchantement
-- ---------------------------------------------------------------------------------------------

describe("Désenchanter : éligibilité (tranches du client)", function()
	local function tranche(classe, sous, qualite, niveau)
		return ns.Desenchanter.tranche(ns.Desenchantement, classe, sous, qualite, niveau)
	end

	it("reconnaît les armes et armures inhabituelles dans leurs tranches, bornes comprises", function()
		assert.is_not_nil(tranche(4, 0, 2, 5))
		assert.is_not_nil(tranche(4, 0, 2, 15))
		assert.is_not_nil(tranche(2, 7, 2, 42))
		assert.is_not_nil(tranche(4, 1, 2, 99))
	end)

	it("refuse sous le niveau 5, au-delà de 99 et hors tranche", function()
		assert.is_nil(tranche(4, 0, 2, 4))
		assert.is_nil(tranche(4, 0, 2, 100))
	end)

	it("les épiques ne se désenchantent qu'à partir du niveau d'objet 40", function()
		assert.is_nil(tranche(4, 0, 4, 39))
		assert.is_not_nil(tranche(4, 0, 4, 40))
		assert.is_not_nil(tranche(2, 0, 4, 60))
	end)

	it("refuse les autres classes d'objet et les qualités non concernées", function()
		assert.is_nil(tranche(0, 0, 2, 20))  -- consommable
		assert.is_nil(tranche(7, 0, 2, 20))  -- artisanat
		assert.is_nil(tranche(4, 0, 1, 20))  -- ordinaire
		assert.is_nil(tranche(4, 0, 0, 20))  -- médiocre
		assert.is_nil(tranche(4, 0, 5, 60))  -- légendaire
	end)

	it("n'explose pas sur des valeurs manquantes", function()
		assert.is_nil(ns.Desenchanter.tranche(ns.Desenchantement, nil, nil, nil, nil))
		assert.is_nil(ns.Desenchanter.tranche(nil, 4, 0, 2, 20))
		assert.is_nil(ns.Desenchanter.tranche({}, 4, 0, 2, 20))
	end)

	it("une sous-classe précise l'emporte sur « toutes »", function()
		local fictives = { tranches = {
			{ classe = 4, sous = -1, qualite = 2, min = 1, max = 99 },
			{ classe = 4, sous = 3, qualite = 2, min = 10, max = 20 },
		} }
		assert.are.equal(3, ns.Desenchanter.tranche(fictives, 4, 3, 2, 15).sous)
		assert.are.equal(-1, ns.Desenchanter.tranche(fictives, 4, 1, 2, 15).sous)
	end)
end)

describe("Infobulles : désenchantement", function()
	local personnages, ctx, objet

	local function enchanteur(nom, classe, niveau)
		return { nom = nom, classe = classe,
			metiers = { [333] = { id = 333, nom = "Enchantement", niveau = niveau, recettes = {} } } }
	end

	before_each(function()
		personnages = {
			["Jean Vialjean"] = enchanteur("Jean Vialjean", "SHAMAN", 60),
			["Brumefer Hautrocher"] = enchanteur("Brumefer Hautrocher", "WARRIOR", 140),
			["Orvanne Test"] = enchanteur("Orvanne Test", "MAGE", 150),
			["Sans Metier"] = perso("Sans Metier", "MAGE", 10, { 2329 }),
		}
		donnees.metiers[333] = { nom = "Enchantement", ordre = {} }
		ctx = contexte(personnages)
		ctx.options.desenchantement = true
		ctx.options.aucunEnchanteur = true
		objet = { classe = 4, sous = 1, qualite = 2, niveau = 42 }
		ctx.infoObjet = function() return objet end
		ctx.enLigne = function(cle) return cle == "Orvanne Test" end
	end)

	after_each(function()
		donnees.metiers[333] = nil
	end)

	it("annonce que l'objet est désenchantable et liste les enchanteurs, en ligne d'abord puis par niveau", function()
		local t = textes(ns.Infobulles.desenchanter(ctx, 12345))
		assert.are.equal("Compagnons · désenchantement", t[1])
		assert.are.equal("Désenchantable · niveau d'objet 42", t[2])
		assert.are.equal("Enchanteurs : Orvanne Test (en ligne, 150), Brumefer Hautrocher (140), Jean Vialjean (toi, 60)", t[3])
	end)

	it("ne liste que les personnages qui ont l'Enchantement", function()
		assert.is_false(contient(ns.Infobulles.desenchanter(ctx, 12345), "Sans Metier"))
	end)

	it("n'ajoute rien pour un objet qui ne se désenchante pas", function()
		objet = { classe = 0, sous = 0, qualite = 2, niveau = 42 } -- consommable
		assert.is_nil(ns.Infobulles.desenchanter(ctx, 12345))
		objet = { classe = 4, sous = 1, qualite = 1, niveau = 42 } -- ordinaire
		assert.is_nil(ns.Infobulles.desenchanter(ctx, 12345))
	end)

	it("n'ajoute rien si le jeu n'a pas encore les informations de l'objet", function()
		ctx.infoObjet = function() return nil end
		assert.is_nil(ns.Infobulles.desenchanter(ctx, 12345))
	end)

	it("signale l'absence d'enchanteur, sauf si l'option est coupée", function()
		local seuls = { ["Sans Metier"] = perso("Sans Metier", "MAGE", 10, { 2329 }) }
		ctx = contexte(seuls)
		ctx.options.desenchantement, ctx.options.aucunEnchanteur = true, true
		ctx.infoObjet = function() return objet end
		assert.is_true(contient(ns.Infobulles.desenchanter(ctx, 12345), "Aucun enchanteur dans la guilde"))
		ctx.options.aucunEnchanteur = false
		assert.is_false(contient(ns.Infobulles.desenchanter(ctx, 12345), "Aucun enchanteur"))
		assert.is_true(contient(ns.Infobulles.desenchanter(ctx, 12345), "Désenchantable"))
	end)

	it("se coupe avec l'option", function()
		ctx.options.desenchantement = false
		assert.is_nil(ns.Infobulles.desenchanter(ctx, 12345))
	end)

	it("limite à quatre enchanteurs puis « et N autres »", function()
		for i = 1, 3 do personnages["Membre" .. i .. " Test"] = enchanteur("Membre" .. i .. " Test", "MAGE", 10 * i) end
		ctx = contexte(personnages)
		ctx.options.desenchantement, ctx.options.aucunEnchanteur = true, true
		ctx.infoObjet = function() return objet end
		assert.is_true(contient(ns.Infobulles.desenchanter(ctx, 12345), "et 2 autres"))
	end)

	it("lit aussi le niveau d'Enchantement des autres membres (profils reçus)", function()
		local profil = { cle = "Wilgar Rolpik", nom = "Wilgar Rolpik", classe = "MAGE", maj = 5, hash = 1,
			metiers = { [333] = { niveau = 225, max = 300, bits = "" } } }
		ctx.catalogue = ns.Catalogue.nouveau(donnees, personnages, { ["Wilgar Rolpik"] = profil })
		assert.is_true(contient(ns.Infobulles.desenchanter(ctx, 12345), "Wilgar Rolpik (225)"))
	end)

	it("s'ajoute aux autres blocs, séparé par une ligne vide", function()
		-- 2454 est créé par une recette : bloc « craftable » puis « désenchantement »
		local t = textes(ns.Infobulles.lignes(ctx, 2454))
		assert.are.equal("Compagnons", t[1])
		local vide
		for i, x in ipairs(t) do if x == " " then vide = i end end
		assert.is_not_nil(vide)
		assert.are.equal("Compagnons · désenchantement", t[vide + 1])
	end)
end)
