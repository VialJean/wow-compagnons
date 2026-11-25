-- Tests hors jeu du Catalogue (recherche, filtres, crafteurs) : busted tests
local function charger()
	local ns = {}
	for _, fichier in ipairs({ "Core/Bitset.lua", "Core/Catalogue.lua", "Core/Profil.lua" }) do
		assert(loadfile(fichier))("Compagnons", ns)
	end
	return ns.Catalogue, ns
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
			objet = 2455, qte = 1, qualite = 1, lie = true, composants = { { 3371, 1 } } },
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

	it("ignore aussi les accents et les majuscules des autres langues", function()
		assert.are.equal("pocion de curacion", Catalogue.normaliser("Poción de Curación"))   -- espagnol
		assert.are.equal("pocao", Catalogue.normaliser("POÇÃO"))                              -- portugais
		assert.are.equal("grosse", Catalogue.normaliser("Große"))                            -- allemand : ß -> ss
		assert.are.equal("pozione di mana", Catalogue.normaliser("Pozione di Mana"))         -- italien
		assert.are.equal("senor", Catalogue.normaliser("Señor"))                             -- ñ -> n
	end)

	it("met le cyrillique en minuscules", function()
		assert.are.equal("эликсир силы", Catalogue.normaliser("Эликсир Силы"))
		assert.are.equal("ёж", Catalogue.normaliser("Ёж"))
		assert.are.equal("яблоко", Catalogue.normaliser("ЯБЛОКО"))
		assert.are.equal("п", Catalogue.normaliser("П")) -- borne du premier bloc
		assert.are.equal("р", Catalogue.normaliser("Р")) -- début du second bloc
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

	it("filtre les objets liés quand équipés", function()
		-- 2331 porte `lie = true` dans les données ; 7418 (enchantement) n'a pas d'objet
		assert.are.same({ 2331 }, c:Chercher({ lieEquipe = true }))
		-- se combine aux autres filtres
		assert.are.same({}, c:Chercher({ lieEquipe = true, inconnue = true }))
		assert.are.same({ 2331 }, c:Chercher({ lieEquipe = true, metier = 171 }))
		assert.are.same({}, c:Chercher({ lieEquipe = true, metier = 333 }))
		assert.are.same({ 2331 }, c:Chercher({ lieEquipe = true, craftable = true, texte = "mana" }))
		-- sans le filtre : rien de changé
		assert.are.same(c:Chercher({}), c:Chercher({ lieEquipe = false }))
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

	it("lit les profils des autres membres (bitsets) et ignore ceux de nos propres personnages", function()
		local _, ns = charger()
		local guilde = {
			["Wilgar Rolpik"] = { cle = "Wilgar Rolpik", nom = "Wilgar Rolpik", classe = "MAGE", maj = 5, hash = 1,
				metiers = { [171] = { niveau = 30, max = 75, bits = ns.Bitset.encoder({ [3] = true }, 3) } } },
			-- version de la guilde d'un personnage qui est à nous : doit être ignorée
			["Jean-Royaume"] = { cle = "Jean-Royaume", nom = "Jean", maj = 1, hash = 2,
				metiers = { [171] = { niveau = 1, max = 75, bits = ns.Bitset.encoder({ [3] = true }, 3) } } },
		}
		local avec = ns.Catalogue.nouveau(donnees, personnages, guilde)
		local liste = avec:Crafteurs(3000)
		assert.are.equal(1, #liste)
		assert.are.equal("Wilgar Rolpik", liste[1].cle)
		assert.are.equal("MAGE", liste[1].classe)
		assert.are.equal(30, liste[1].niveau)
		assert.are.equal(2, #avec:Crafteurs(2329)) -- les nôtres, pas de doublon
	end)

	it("se met à jour quand les personnages changent", function()
		assert.are.same({ 3000 }, c:Chercher({ inconnue = true }))
		personnages["Jean-Royaume"].metiers[171].recettes[#personnages["Jean-Royaume"].metiers[171].recettes + 1] = 3000
		c:Actualiser()
		assert.are.same({}, c:Chercher({ inconnue = true }))
		personnages["Jean-Royaume"].metiers[171].recettes[4] = nil
	end)

	it("liste les membres qui ont l'addon avec leurs métiers, les miens compris, sans doublon", function()
		local _, ns = charger()
		local guilde = {
			["Wilgar Rolpik"] = { cle = "Wilgar Rolpik", nom = "Wilgar Rolpik", classe = "MAGE", maj = 5, hash = 1,
				metiers = {
					[333] = { niveau = 12, max = 75, bits = ns.Bitset.encoder({ [1] = true }, 1) },
					[171] = { niveau = 30, max = 75, bits = ns.Bitset.encoder({ [3] = true }, 3) },
				} },
			["Jean-Royaume"] = { cle = "Jean-Royaume", nom = "Jean", maj = 1, hash = 2,
				metiers = { [171] = { niveau = 1, max = 75, bits = ns.Bitset.encoder({ [3] = true }, 3) } } },
			["Sansmetier Nu"] = { cle = "Sansmetier Nu", nom = "Sansmetier Nu", maj = 1, hash = 3, metiers = {} },
		}
		local membres = ns.Catalogue.nouveau(donnees, personnages, guilde):Membres()
		local noms = {}
		for _, m in ipairs(membres) do noms[#noms + 1] = m.nom end
		assert.are.same({ "Brumefer", "Jean", "Wilgar Rolpik" }, noms)   -- triés, sans doublon ni membre sans métier
		assert.is_true(membres[2].moi)
		assert.is_false(membres[3].moi)
		local wilgar = membres[3]
		assert.are.equal("MAGE", wilgar.classe)
		assert.are.equal("Alchimie", wilgar.metiers[1].nom)          -- métiers triés par nom
		assert.are.equal(30, wilgar.metiers[1].niveau)
		assert.are.equal(75, wilgar.metiers[1].max)
		assert.are.equal(1, wilgar.metiers[1].recettes)
		assert.are.equal("Enchantement", wilgar.metiers[2].nom)
		assert.are.equal(2, #membres[2].metiers == 1 and 2 or 0)      -- Jean : un métier (nos données, pas celles de la guilde)
		assert.are.equal(2, membres[2].metiers[1].recettes)           -- 424242 n'est pas dans la base
	end)

	describe("favoris, composant et stock", function()
		local function chercher(options)
			local Cat = charger()
			return Cat.nouveau(donnees, personnages, {}):Chercher(options)
		end

		it("ne garde que les favoris quand on le demande", function()
			local liste = chercher({ soloFavoris = true, favoris = { [3000] = true } })
			assert.same({ 3000 }, liste)
			assert.same({}, (chercher({ soloFavoris = true, favoris = {} })))
			assert.same({}, (chercher({ soloFavoris = true })))
		end)

		it("ne garde que les recettes qui utilisent le composant", function()
			assert.same({ 2331, 2329 }, (function()
				local l = chercher({ composant = 3371 })
				table.sort(l, function(a, b) return a > b end)
				return l
			end)())
			assert.same({ 3000 }, chercher({ composant = 2449, texte = "huile" }))
		end)

		it("ne garde que les recettes dont tous les composants sont en stock", function()
			local stock = { [2449] = 1, [3371] = 1 }
			local liste = chercher({ avecStock = true, stock = function(id) return stock[id] or 0 end })
			table.sort(liste)
			assert.same({ 2329, 2331 }, liste) -- 3000 veut 2 terrestrines ; 7418 veut une poussière
			stock[2449] = 2
			liste = chercher({ avecStock = true, stock = function(id) return stock[id] or 0 end })
			table.sort(liste)
			assert.same({ 2329, 2331, 3000 }, liste)
		end)
	end)
end)
