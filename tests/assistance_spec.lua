-- Tests hors jeu de l'assistance à l'envoi (Core/Assistance.lua). busted tests
local ns = {}
assert(loadfile("Core/Livraison.lua"))("Compagnons", ns)
assert(loadfile("Core/Assistance.lua"))("Compagnons", ns)
local Assistance = ns.Assistance

local donnees = { recettes = {
	[1] = { objet = 500, qte = 1, composants = { { 10, 2 }, { 11, 1 } } },
	[2] = { qte = 1, composants = { { 10, 1 } } }, -- enchantement
} }

local function commande(id, extra)
	local o = { id = id, client = "Alice Durand", spell = 1, qte = 3, mats = "tout", statut = "prise",
		assigne = "Jean Vialjean", cree = 1 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function table_(...) local t = {} for _, c in ipairs({ ... }) do t[c.id] = c end return t end

describe("Assistance.requis", function()
	it("le client doit fournir les composants de ses commandes prises au crafteur", function()
		local requis, ids = Assistance.requis(table_(commande("a")), donnees, "Alice Durand", "Jean")
		assert.are.equal(6, requis[10])
		assert.are.equal(3, requis[11])
		assert.are.same({ "a" }, ids)
	end)

	it("le crafteur doit livrer l'objet fabriqué, pas pour un enchantement", function()
		local cmds = table_(commande("a", { statut = "mats" }), commande("b", { spell = 2, cree = 2 }))
		local requis, ids = Assistance.requis(cmds, donnees, "Jean Vialjean", "Alice")
		assert.are.equal(3, requis[500])
		assert.is_nil(requis[10])
		assert.are.same({ "a" }, ids)
	end)

	it("cumule plusieurs commandes du même couple, sans les autres personnes", function()
		local cmds = table_(commande("a"), commande("b", { cree = 2 }), commande("c", { client = "Zed Zorro" }))
		local requis = Assistance.requis(cmds, donnees, "Alice Durand", "Jean")
		assert.are.equal(12, requis[10])
		local autres = Assistance.requis(cmds, donnees, "Jean Vialjean", "Zed")
		assert.are.equal(3, autres[500])
	end)

	it("ne demande rien si le crafteur fournit tout, ou si la commande n'est pas prise", function()
		local cmds = table_(commande("a", { mats = "crafteur" }), commande("b", { statut = "ouverte", assigne = nil }))
		assert.is_nil(next((Assistance.requis(cmds, donnees, "Alice Durand", "Jean"))))
	end)
end)

describe("Assistance.partenaires", function()
	it("liste les personnes concernées, la plus ancienne commande d'abord, sans doublon", function()
		local cmds = table_(
			commande("a", { cree = 5 }),
			commande("b", { cree = 1, client = "Zed Zorro", assigne = "Alice Durand" }),
			commande("c", { cree = 9 }))
		-- Alice est crafteuse pour Zed (b, la plus ancienne) et cliente de Jean (a, c)
		assert.are.same({ "Zed Zorro", "Jean Vialjean" }, Assistance.partenaires(cmds, donnees, "Alice Durand"))
	end)
end)

describe("Assistance.restant et placements", function()
	it("déduit ce qui est déjà posé", function()
		local reste = Assistance.restant({ [10] = 6, [11] = 3 }, { [10] = 6, [11] = 1 })
		assert.is_nil(reste[10])
		assert.are.equal(2, reste[11])
	end)

	it("prend les plus gros tas d'abord et fractionne le dernier", function()
		local sacs = {
			{ bag = 0, slot = 1, itemID = 10, count = 5 },
			{ bag = 0, slot = 2, itemID = 10, count = 20 },
			{ bag = 1, slot = 1, itemID = 11, count = 2 },
		}
		local liste, manque = Assistance.placements({ [10] = 22, [11] = 1 }, sacs, 6)
		assert.is_nil(next(manque))
		assert.are.equal(3, #liste)
		assert.are.equal(20, liste[1].n)
		assert.is_false(liste[1].partiel)
		assert.are.equal(2, liste[2].n)   -- 5 en tas, 2 utilisés
		assert.is_true(liste[2].partiel)
		assert.is_true(liste[3].partiel)  -- 1 sur 2
	end)

	it("signale ce qui manque dans les sacs et respecte le nombre d'emplacements", function()
		local sacs = { { bag = 0, slot = 1, itemID = 10, count = 3 }, { bag = 0, slot = 2, itemID = 11, count = 1 },
			{ bag = 0, slot = 3, itemID = 12, count = 1 } }
		local liste, manque = Assistance.placements({ [10] = 5, [11] = 1, [12] = 1 }, sacs, 2)
		assert.are.equal(2, #liste)
		assert.are.equal(2, manque[10])
		assert.are.equal(1, manque[12])   -- plus de place
	end)
end)

describe("Assistance.ou", function()
	local detail = function(id)
		if id == 10 then return { { cle = "Jean Vialjean", n = 7 }, { cle = "Alt Deux", n = 3 } } end
		if id == 11 then return { { cle = "Jean Vialjean", n = 2 } } end
		return {}
	end

	it("sépare la banque du personnage connecté et les autres personnages", function()
		local r = Assistance.ou({ [10] = 5 }, detail, "Jean Vialjean", { [10] = 4 })
		assert.are.equal(3, r[10].banque) -- 7 en tout, 4 dans les sacs
		assert.are.equal(1, #r[10].autres)
		assert.are.equal("Alt Deux", r[10].autres[1].cle)
		assert.are.equal(3, r[10].autres[1].n)
	end)

	it("n'indique pas de banque quand tout est déjà dans les sacs", function()
		local r = Assistance.ou({ [11] = 1 }, detail, "Jean Vialjean", { [11] = 2 })
		assert.is_nil(r[11])
	end)

	it("ignore un objet introuvable partout", function()
		assert.is_nil(Assistance.ou({ [99] = 1 }, detail, "Jean Vialjean", {})[99])
	end)
end)
