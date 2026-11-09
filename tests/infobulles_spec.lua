-- Tests hors jeu du texte des infobulles d'objet (docs/infobulles.md, §2). busted tests
local function charger()
	local ns = {}
	for _, fichier in ipairs({ "Core/Locales.lua", "Core/Bitset.lua", "Core/Catalogue.lua", "Core/Profil.lua",
		"Core/Commandes.lua", "Core/Infobulles.lua" }) do
		assert(loadfile(fichier))("Compagnons", ns)
	end
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

	it("liste les crafteurs avec leur nombre de recettes, le plus fournis d'abord", function()
		local l = ns.Infobulles.composant(ctx, 3371) -- utilisé par 2329 et 2331
		local t = textes(l)
		assert.are.equal("Compagnons · composant", t[1])
		assert.are.equal("Brumefer Hautrocher : 2 recettes dont 1 qui monte encore", t[2]) -- 2329 : gris 95 < 100 ; 2331 : 105 > 100
		assert.are.equal("Jean Vialjean : 1 recette dont 1 qui monte encore", t[3])
		assert.are.equal("Maj : détail des recettes", t[4])
	end)

	it("ne parle pas de « monte encore » quand plus rien ne fait progresser", function()
		personnages["Brumefer Hautrocher"].metiers[171].niveau = 300
		ctx = contexte(personnages)
		local t = textes(ns.Infobulles.composant(ctx, 3371))
		assert.are.equal("Brumefer Hautrocher : 2 recettes", t[2])
	end)

	it("avec Maj, détaille les recettes à la place des crafteurs", function()
		ctx.maj = true
		local t = textes(ns.Infobulles.composant(ctx, 3371))
		assert.are.equal("Elixir de Force mineure · Brumefer Hautrocher", t[2])
		assert.are.equal("Potion de mana mineure · Brumefer Hautrocher", t[3])
		assert.is_false(contient(ns.Infobulles.composant(ctx, 3371), "Maj : détail"))
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
