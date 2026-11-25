-- Tests hors jeu de l'historique des commandes (Core/Historique.lua). busted tests
local ns = {}
assert(loadfile("Core/Historique.lua"))("Compagnons", ns)
local Historique = ns.Historique

local JOUR = 24 * 3600
local T0 = 1731180000

local function commande(id, statut, extra)
	local c = { id = id, spell = 2329, qte = 2, client = "Wilgar Rolpik", assigne = "Jean Vialjean", statut = statut,
		cree = T0, maj = T0 + 100 }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end

describe("Historique", function()
	it("archive les commandes terminées et annulées, une seule fois", function()
		local h = {}
		assert.is_true(Historique.archiver(h, commande("a", "terminee"), false))
		assert.is_false(Historique.archiver(h, commande("a", "terminee"), false)) -- déjà vue
		assert.is_true(Historique.archiver(h, commande("b", "annulee", { assigne = false }), false))
		assert.equal(2, #h)
		assert.equal("terminee", h[1].issue)
		assert.equal(T0 + 100, h[1].fin)
	end)

	it("n'archive pas les commandes en cours", function()
		local h = {}
		for _, s in ipairs({ "ouverte", "prise", "mats", "livree" }) do
			assert.is_false(Historique.archiver(h, commande("x" .. s, s), false))
		end
		assert.equal(0, #h)
	end)

	it("archive « sans confirmation » une commande livrée qu'on oublie", function()
		local h = {}
		assert.is_true(Historique.archiver(h, commande("l", "livree"), true))
		assert.equal("sansconfirmation", h[1].issue)
	end)

	it("garde le pourboire de la commande", function()
		local h = {}
		Historique.archiver(h, commande("p", "terminee", { pourboire = 5000 }), false)
		assert.equal(5000, h[1].pourboire)
	end)

	it("balaye une table de commandes", function()
		local h = {}
		local n = Historique.balayer(h, {
			a = commande("a", "terminee"), b = commande("b", "prise"), c = commande("c", "annulee"),
		})
		assert.equal(2, n)
		assert.equal(0, Historique.balayer(h, { a = commande("a", "terminee") }))
	end)

	it("purge au-delà de 180 jours", function()
		local h = {}
		Historique.archiver(h, commande("vieille", "terminee", { maj = T0 }), false)
		Historique.archiver(h, commande("recente", "terminee", { maj = T0 + 170 * JOUR }), false)
		local retirees = Historique.purger(h, T0 + 181 * JOUR)
		assert.equal(1, retirees)
		assert.equal("recente", h[1].id)
	end)

	it("garde les 500 plus récentes", function()
		local h = {}
		for i = 1, 520 do
			Historique.archiver(h, commande("c" .. i, "terminee", { maj = T0 + i }), false)
		end
		assert.equal(20, Historique.purger(h, T0 + 1000))
		assert.equal(500, #h)
		assert.equal("c21", h[1].id)
		assert.equal("c520", h[500].id)
	end)

	it("compte crafté et passé par membre, sans les annulations", function()
		local h = {}
		Historique.archiver(h, commande("a", "terminee"), false)
		Historique.archiver(h, commande("b", "terminee"), false)
		Historique.archiver(h, commande("c", "annulee"), false)
		Historique.archiver(h, commande("d", "livree"), true)
		local c = Historique.compteurs(h)
		assert.equal(3, c["Jean Vialjean"].craftees)
		assert.equal(0, c["Jean Vialjean"].passees)
		assert.equal(3, c["Wilgar Rolpik"].passees)
	end)

	it("filtre par membre, métier et texte, du plus récent au plus ancien", function()
		local donnees = { recettes = { [2329] = { metier = 171, nom = "Élixir" }, [3000] = { metier = 333, nom = "Huile" } } }
		local h = {}
		Historique.archiver(h, commande("a", "terminee", { maj = T0 + 1 }), false)
		Historique.archiver(h, commande("b", "terminee", { spell = 3000, maj = T0 + 2, client = "Autre", assigne = "Troisième" }), false)
		Historique.archiver(h, commande("c", "terminee", { maj = T0 + 3 }), false)
		local tous = Historique.liste(h, { donnees = donnees })
		assert.same({ "c", "b", "a" }, { tous[1].id, tous[2].id, tous[3].id })
		assert.equal(2, #Historique.liste(h, { donnees = donnees, membre = "Jean Vialjean" }))
		assert.equal(1, #Historique.liste(h, { donnees = donnees, metier = 333 }))
		assert.equal(1, #Historique.liste(h, { donnees = donnees, texte = "huile" }))
		assert.equal(0, #Historique.liste(h, { donnees = donnees, texte = "absent" }))
	end)
end)
