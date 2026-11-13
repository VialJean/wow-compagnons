-- Tests hors jeu du rapprochement échange / commandes (Core/Livraison.lua). busted tests
local ns = {}
assert(loadfile("Core/Livraison.lua"))("Compagnons", ns)
local Livraison = ns.Livraison

local donnees = { recettes = {
	[1] = { objet = 500, qte = 1, composants = { { 10, 2 }, { 11, 1 } } },
	[2] = { qte = 1, composants = { { 10, 1 } } }, -- enchantement : pas d'objet créé
} }

local function commande(id, extra)
	local o = { id = id, client = "Spellus Spamus", spell = 1, qte = 3, mats = "tout", statut = "prise",
		assigne = "Jean Vialjean", cree = 1 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function lister(cmds) local t = {} for _, c in ipairs(cmds) do t[c.id] = c end return t end

describe("Livraison.rapprocher", function()
	it("propose « mats » quand le client remet tous les matériaux", function()
		local p = Livraison.rapprocher(lister({ commande("a") }), donnees, "Jean Vialjean", "Spellus", { [10] = 6, [11] = 3 }, {})
		assert.are.equal(1, #p)
		assert.are.equal("mats", p[1].action)
	end)

	it("ne propose rien si les matériaux « tout » ne sont pas complets", function()
		local p = Livraison.rapprocher(lister({ commande("a") }), donnees, "Jean Vialjean", "Spellus", { [10] = 6, [11] = 2 }, {})
		assert.are.equal(0, #p)
	end)

	it("« partie » se contente d'un composant, « crafteur » n'attend rien", function()
		local cmds = lister({ commande("a", { mats = "partie" }), commande("b", { mats = "crafteur", cree = 2 }) })
		local p = Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", { [11] = 1 }, {})
		assert.are.equal(1, #p)
		assert.are.equal("a", p[1].id)
	end)

	it("propose « terminer » quand l'objet fabriqué est remis en quantité suffisante", function()
		local cmds = lister({ commande("a", { statut = "mats" }) })
		assert.are.equal("livrer", Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", {}, { [500] = 3 })[1].action)
		assert.are.equal(0, #Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", {}, { [500] = 2 }))
	end)

	it("une recette sans objet (enchantement) ne se termine pas par échange", function()
		local cmds = lister({ commande("a", { spell = 2, statut = "mats" }) })
		assert.are.equal(0, #Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", {}, { [500] = 9 }))
	end)

	it("ignore les autres clients, les autres crafteurs et les commandes ouvertes ou finales", function()
		local cmds = lister({
			commande("a", { client = "Brumefer Hautrocher" }),
			commande("b", { assigne = "Alice Durand" }),
			commande("c", { statut = "ouverte", assigne = nil }),
			commande("d", { statut = "terminee" }),
		})
		assert.are.equal(0, #Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", { [10] = 99, [11] = 99 }, { [500] = 99 }))
	end)

	it("ne compte pas deux fois les mêmes objets pour deux commandes", function()
		local cmds = lister({ commande("a", { qte = 2, cree = 1 }), commande("b", { qte = 2, cree = 2 }) })
		local p = Livraison.rapprocher(cmds, donnees, "Jean Vialjean", "Spellus", { [10] = 4, [11] = 2 }, {})
		assert.are.equal(1, #p)
		assert.are.equal("a", p[1].id) -- la plus ancienne d'abord
	end)

	it("reconnaît le partenaire par le prénom seul, sans confondre deux prénoms", function()
		assert.is_true(Livraison.memePersonne("Spellus Spamus", "Spellus"))
		assert.is_true(Livraison.memePersonne("Spellus Spamus", "Spellus Spamus"))
		assert.is_false(Livraison.memePersonne("Spellus Spamus", "Spell"))
		assert.is_false(Livraison.memePersonne("Spellus Spamus", nil))
	end)
end)

describe("Livraison.courriersRetires", function()
	local function courrier(de, sujet, objets) return { expediteur = de, sujet = sujet, objets = objets } end

	it("repère le courrier dont les pièces jointes ont été retirées", function()
		local a = courrier("Spellus", "Lin", { [10] = 6 })
		local retires = Livraison.courriersRetires({ a }, { courrier("Spellus", "Lin", {}) })
		assert.are.equal(1, #retires)
		assert.are.equal(6, retires[1].objets[10])
		assert.are.equal(0, #Livraison.courriersRetires({ a }, { a }))
	end)

	it("ne confond pas un décalage de position avec un retrait", function()
		local a, b = courrier("Spellus", "A", { [10] = 1 }), courrier("Brumefer", "B", { [11] = 2 })
		assert.are.equal(0, #Livraison.courriersRetires({ a, b }, { b, a }))
		local retires = Livraison.courriersRetires({ a, b }, { b })
		assert.are.equal("Spellus", retires[1].expediteur)
	end)

	it("compte les doublons et ignore les courriers sans pièce jointe", function()
		local a = courrier("Spellus", "Lin", { [10] = 1 })
		assert.are.equal(1, #Livraison.courriersRetires({ a, a }, { a }))
		assert.are.equal(0, #Livraison.courriersRetires({ courrier("X", "Y", {}) }, {}))
	end)

	it("reconnaît un expéditeur avec royaume", function()
		assert.is_true(Livraison.memePersonne("Spellus Spamus", "Spellus-CAMWOWEU5Realm10RP"))
	end)
end)

describe("Livraison.rapprocher : remises en plusieurs fois", function()
	local moi, partenaire = "Jean Vialjean", "Spellus"

	it("additionne les matériaux « tout » remis en deux échanges", function()
		local cmds = lister({ commande("a") }) -- 3 × (2 de 10 + 1 de 11) = 6 de 10 et 3 de 11
		local p1, cumul = Livraison.rapprocher(cmds, donnees, moi, partenaire, { [10] = 4, [11] = 1 }, {})
		assert.are.equal(0, #p1)
		assert.are.equal(4, cumul.a.recu[10])
		local p2, cumul2 = Livraison.rapprocher(cmds, donnees, moi, partenaire, { [10] = 2, [11] = 2 }, {}, cumul)
		assert.are.equal(1, #p2)
		assert.are.equal("mats", p2[1].action)
		assert.is_nil(cumul2.a)
	end)

	it("ne retient pas plus que ce qui manque", function()
		local cmds = lister({ commande("a") })
		local _, cumul = Livraison.rapprocher(cmds, donnees, moi, partenaire, { [10] = 50 }, {})
		assert.are.equal(6, cumul.a.recu[10])
	end)

	it("additionne l'objet fabriqué remis en deux fois", function()
		local cmds = lister({ commande("a", { statut = "mats" }) })
		local p1, cumul = Livraison.rapprocher(cmds, donnees, moi, partenaire, {}, { [500] = 2 })
		assert.are.equal(0, #p1)
		assert.are.equal(2, cumul.a.donne[500])
		local p2, cumul2 = Livraison.rapprocher(cmds, donnees, moi, partenaire, {}, { [500] = 1 }, cumul)
		assert.are.equal("livrer", p2[1].action)
		assert.is_nil(cumul2.a)
	end)

	it("garde le cumul des commandes que l'échange ne concerne pas", function()
		local cmds = lister({ commande("a") })
		local _, cumul = Livraison.rapprocher(cmds, donnees, moi, partenaire, { [10] = 2 }, {})
		local _, cumul2 = Livraison.rapprocher(cmds, donnees, moi, "Autre", {}, {}, cumul)
		assert.are.equal(2, cumul2.a.recu[10])
	end)

	it("purge le cumul des commandes annulées ou reprises par un autre", function()
		local cumul = { a = { recu = { [10] = 1 }, donne = {} }, b = { recu = {}, donne = { [500] = 1 } },
			c = { recu = { [10] = 1 }, donne = {} } }
		local cmds = lister({ commande("a", { statut = "annulee" }), commande("b", { assigne = "Autre" }), commande("c") })
		Livraison.purger(cumul, cmds, moi)
		assert.is_nil(cumul.a)
		assert.is_nil(cumul.b)
		assert.is_not_nil(cumul.c)
	end)
end)
