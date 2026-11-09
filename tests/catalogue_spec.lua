-- Tests hors jeu du Catalogue (recherche, filtres, crafteurs) : busted tests
local function charger()
	local ns = {}
	local chunk = assert(loadfile("Core/Catalogue.lua"))
	chunk("Compagnons", ns)
	return ns.Catalogue
end

local donnees = {
	metiers = {
		[171] = { nom = "Alchimie", ordre = { 2329, 2331, 3000 } },
		[333] = { nom = "Enchantement", ordre = { 7418 } },
	},
	objets = {
		[2449] = { "Terrestrine", 1 },
		[3371] = { "Fiole vide", 1 },
		[10940] = { "Poussière d'âme", 1 },
	},
	recettes = {
		[2329] = { metier = 171, indice = 1, niveau = 1, nom = "Élixir de Force mineure",
			objet = 2454, qte = 1, qualite = 1, composants = { { 2449, 1 }, { 3371, 1 } } },
		[2331] = { metier = 171, indice = 2, niveau = 1, nom = "Potion de mana mineure",
			objet = 2455, qte = 1, qualite = 1, composants = { { 3371, 1 } } },
		[3000] = { metier = 171, indice = 3, niveau = 40, nom = "Huile de glace",
			objet = 9999, qte = 1, qualite = 2, composants = { { 2449, 2 } } },
		[7418] = { metier = 333, indice = 1, niveau = 1, nom = "Enchanter le bracelet",
			objet = 0, qte = 0, qualite = 0, composants = { { 10940, 1 } } },
	},
}

local personnages = {
	["Jean-Royaume"] = {
		nom = "Jean", classe = "SHAMAN",
		metiers = {
			[171] = { id = 171, nom = "Alchimie", niveau = 60, recettes = { 2329, 2331, 424242 } },
		},
	},
	["Brumefer-Royaume"] = {
		nom = "Brumefer", classe = "WARRIOR",
		metiers = {
			-- métier stocké sans identifiant (API ancienne) : retrouvé par son nom
			["alchimie"] = { nom = "Alchimie", niveau = 10, recettes = { 2329 } },
			[333] = { id = 333, nom = "Enchantement", niveau = 5, recettes = { 7418 } },
		},
	},
}

describe("Catalogue", function()
	local Catalogue = charger()
	local c

	before_each(function()
		c = Catalogue.nouveau(donnees, personnages)
	end)

	it("normalise casse et accents", function()
		assert.are.equal("elixir de force mineure", Catalogue.normaliser("Élixir de Force mineure"))
		assert.are.equal("poussiere d'ame", Catalogue.normaliser("Poussière d’âme"))
		assert.are.equal("", Catalogue.normaliser(nil))
	end)

	it("trie par niveau puis par nom", function()
		assert.are.same({ 2329, 7418, 2331, 3000 }, c:Chercher())
		-- niveau 1 : « elixir » < « enchanter » < « potion »
	end)

	it("cherche dans le nom, sans accent ni casse", function()
		assert.are.same({ 2329 }, c:Chercher({ texte = "ELIXIR" }))
		assert.are.same({ 2329 }, c:Chercher({ texte = "élixir force" }))
	end)

	it("cherche aussi dans les composants", function()
		assert.are.same({ 2329, 2331 }, c:Chercher({ texte = "fiole" }))
		assert.are.same({ 2329, 3000 }, c:Chercher({ texte = "terrestrine" }))
		assert.are.same({ 2329 }, c:Chercher({ texte = "terrestrine fiole" }))
		assert.are.same({ 7418 }, c:Chercher({ texte = "poussiere ame" }))
	end)

	it("filtre par métier", function()
		assert.are.same({ 7418 }, c:Chercher({ metier = 333 }))
		assert.are.same({ 2329, 2331, 3000 }, c:Chercher({ metier = 171 }))
	end)

	it("filtre craftable / inconnue", function()
		assert.are.same({ 2329, 7418, 2331 }, c:Chercher({ craftable = true }))
		assert.are.same({ 3000 }, c:Chercher({ inconnue = true }))
	end)

	it("filtre les crafteurs en ligne", function()
		local enLigne = { ["Brumefer-Royaume"] = true }
		local r = c:Chercher({ enLigne = true, estEnLigne = function(cle) return enLigne[cle] end })
		assert.are.same({ 2329, 7418 }, r)
		assert.are.same({}, c:Chercher({ enLigne = true })) -- sans fonction : personne
	end)

	it("liste les crafteurs triés, avec le métier retrouvé par son nom", function()
		local liste = c:Crafteurs(2329)
		assert.are.equal(2, #liste)
		assert.are.equal("Brumefer-Royaume", liste[1].cle)
		assert.are.equal("WARRIOR", liste[1].classe)
		assert.are.equal(60, liste[2].niveau)
		assert.are.same({}, c:Crafteurs(3000))
	end)

	it("ignore les recettes inconnues de la base", function()
		assert.are.same({}, c:Crafteurs(424242))
	end)

	it("compte les recettes par métier", function()
		local m = c:Metiers()
		assert.are.equal(2, #m)
		assert.are.equal("Alchimie", m[1].nom)
		assert.are.equal(3, m[1].total)
		assert.are.equal(1, m[2].total)
	end)

	it("détaille les composants", function()
		local comps = c:Composants(2329)
		assert.are.equal(2, #comps)
		assert.are.equal("Terrestrine", comps[1].nom)
		assert.are.equal(2449, comps[1].itemID)
		assert.are.same({}, c:Composants(1))
	end)

	it("se met à jour quand les personnages changent", function()
		assert.are.same({ 3000 }, c:Chercher({ inconnue = true }))
		personnages["Jean-Royaume"].metiers[171].recettes[#personnages["Jean-Royaume"].metiers[171].recettes + 1] = 3000
		c:Actualiser()
		assert.are.same({}, c:Chercher({ inconnue = true }))
		personnages["Jean-Royaume"].metiers[171].recettes[4] = nil
	end)
end)
