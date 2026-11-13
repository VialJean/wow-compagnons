-- Tests hors jeu des rappels de commandes (Core/Rappels.lua). busted tests
local ns = {}
assert(loadfile("Core/Rappels.lua"))("Compagnons", ns)
local Rappels = ns.Rappels

local JOUR = 86400
local MAINTENANT = 1731180000 + 100 * JOUR
local MIENS = { ["Jean Vialjean"] = true, ["Brumefer Hautrocher"] = true }

local function cmd(id, statut, joursPasses, extra)
	local o = { id = id, client = "Wilgar Rolpik", assigne = nil, statut = statut, maj = MAINTENANT - joursPasses * JOUR }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function genres(liste)
	local t = {}
	for i, r in ipairs(liste) do t[i] = r.genre .. ":" .. r.commande.id end
	return t
end

describe("Rappels.calculer", function()
	it("rappelle au client une commande livrée à confirmer, dès un jour", function()
		local c = { a = cmd("a", "livree", 1, { client = "Jean Vialjean", assigne = "Wilgar Rolpik" }),
			b = cmd("b", "livree", 0.5, { client = "Jean Vialjean", assigne = "Wilgar Rolpik" }) }
		assert.are.same({ "a_confirmer:a" }, genres(Rappels.calculer(c, MIENS, MAINTENANT)))
	end)

	it("rappelle au client une commande ouverte sans preneur, dès trois jours", function()
		local c = { a = cmd("a", "ouverte", 3, { client = "Jean Vialjean" }), b = cmd("b", "ouverte", 2.9, { client = "Jean Vialjean" }) }
		assert.are.same({ "sans_preneur:a" }, genres(Rappels.calculer(c, MIENS, MAINTENANT)))
	end)

	it("rappelle au crafteur une commande prise sans avancée, dès cinq jours", function()
		local c = { a = cmd("a", "prise", 5, { assigne = "Jean Vialjean" }), b = cmd("b", "mats", 4, { assigne = "Jean Vialjean" }),
			c = cmd("c", "mats", 6, { assigne = "Brumefer Hautrocher" }) }
		local l = Rappels.calculer(c, MIENS, MAINTENANT)
		assert.are.same({ "sans_progres:c", "sans_progres:a" }, genres(l)) -- la plus ancienne d'abord
		assert.are.equal(6, l[1].jours)
	end)

	it("informe le crafteur d'une livraison que le client n'a pas confirmée, dès trois jours", function()
		local c = { a = cmd("a", "livree", 3, { assigne = "Jean Vialjean" }), b = cmd("b", "livree", 2, { assigne = "Jean Vialjean" }) }
		assert.are.same({ "en_attente:a" }, genres(Rappels.calculer(c, MIENS, MAINTENANT)))
	end)

	it("ne rappelle rien pour les commandes des autres, ni pour les commandes finales", function()
		local c = {
			a = cmd("a", "ouverte", 40),                                             -- ouverte par un autre
			b = cmd("b", "prise", 40, { assigne = "Alice Durand" }),                  -- prise par un autre
			c = cmd("c", "terminee", 40, { client = "Jean Vialjean", assigne = "Alice Durand" }),
			d = cmd("d", "annulee", 40, { client = "Jean Vialjean" }),
		}
		assert.are.equal(0, #Rappels.calculer(c, MIENS, MAINTENANT))
	end)

	it("classe par genre puis par ancienneté", function()
		local c = {
			a = cmd("a", "ouverte", 10, { client = "Jean Vialjean" }),
			b = cmd("b", "livree", 2, { client = "Jean Vialjean", assigne = "Alice Durand" }),
			c = cmd("c", "ouverte", 20, { client = "Brumefer Hautrocher" }),
			d = cmd("d", "prise", 9, { assigne = "Jean Vialjean" }),
		}
		assert.are.same({ "a_confirmer:b", "sans_preneur:c", "sans_preneur:a", "sans_progres:d" },
			genres(Rappels.calculer(c, MIENS, MAINTENANT)))
	end)

	it("applique les délais réglés, et retombe sur les défauts pour une valeur invalide", function()
		local c = { a = cmd("a", "ouverte", 1, { client = "Jean Vialjean" }) }
		assert.are.equal(0, #Rappels.calculer(c, MIENS, MAINTENANT))
		assert.are.equal(1, #Rappels.calculer(c, MIENS, MAINTENANT, { sansPreneur = 1 }))
		assert.are.equal(0, #Rappels.calculer(c, MIENS, MAINTENANT, { sansPreneur = "x" })) -- défaut : 3 jours
		assert.are.equal(0, #Rappels.calculer(c, MIENS, MAINTENANT, { sansPreneur = -5 }))
		assert.are.equal(0, #Rappels.calculer(c, MIENS, MAINTENANT, { sansPreneur = 0 / 0 }))
	end)

	it("supporte une liste vide ou absente", function()
		assert.are.equal(0, #Rappels.calculer({}, MIENS, MAINTENANT))
		assert.are.equal(0, #Rappels.calculer(nil, MIENS, MAINTENANT))
	end)
end)

describe("Rappels.resumer", function()
	it("compte par genre et retient la plus ancienne", function()
		local c = {
			a = cmd("a", "ouverte", 10, { client = "Jean Vialjean" }),
			b = cmd("b", "ouverte", 4, { client = "Jean Vialjean" }),
			c = cmd("c", "livree", 2, { client = "Jean Vialjean", assigne = "Alice Durand" }),
		}
		local g = Rappels.resumer(Rappels.calculer(c, MIENS, MAINTENANT))
		assert.are.equal(2, g.sans_preneur.n)
		assert.are.equal(10, g.sans_preneur.jours)
		assert.are.equal(1, g.a_confirmer.n)
		assert.is_nil(g.sans_progres)
	end)
end)

describe("Rappels.anciennes", function()
	it("liste mes commandes ouvertes depuis 30 jours, la plus ancienne d'abord", function()
		local c = {
			a = cmd("a", "ouverte", 30, { client = "Jean Vialjean" }),
			b = cmd("b", "ouverte", 29, { client = "Jean Vialjean" }),
			c = cmd("c", "ouverte", 45, { client = "Brumefer Hautrocher" }),
			d = cmd("d", "ouverte", 60),                                   -- celle d'un autre : je ne peux pas l'annuler
			e = cmd("e", "prise", 60, { client = "Jean Vialjean", assigne = "Alice Durand" }), -- prise : pas concernée
		}
		local l = Rappels.anciennes(c, MIENS, MAINTENANT)
		assert.are.equal(2, #l)
		assert.are.equal("c", l[1].id)
		assert.are.equal("a", l[2].id)
	end)

	it("accepte un autre seuil, en jours", function()
		local c = { a = cmd("a", "ouverte", 10, { client = "Jean Vialjean" }) }
		assert.are.equal(1, #Rappels.anciennes(c, MIENS, MAINTENANT, 7))
		assert.are.equal(0, #Rappels.anciennes(c, MIENS, MAINTENANT, 11))
	end)
end)
