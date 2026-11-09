-- Tests hors jeu du stock sur tous les personnages et de la liste de courses (Core/Stock.lua). busted tests
local function charger()
	local ns = {}
	for _, f in ipairs({ "Core/Stock.lua" }) do assert(loadfile(f))("Compagnons", ns) end
	return ns
end

local ns = charger()
local Stock = ns.Stock

local donnees = {
	objets = { [10] = { "Fiole vide", 1 }, [11] = { "Lotus pourpre", 1 }, [12] = { "", 1 } },
	recettes = {
		[1] = { composants = { { 10, 1 }, { 11, 3 } } },
		[2] = { composants = { { 11, 2 } } },
		[3] = { composants = { { 12, 1 } } },
	},
}

local miens = { ["Jean Vialjean"] = true, ["Brumefer Hautrocher"] = true }

describe("Stock : relevé et total", function()
	it("relève les composants de la base, quantités non nulles seulement", function()
		local quantites = { [10] = 4, [11] = 0 }
		local r = Stock.releve(donnees, function(id) return quantites[id] end, 1000)
		assert.are.equal(1000, r.maj)
		assert.are.equal(4, r[10])
		assert.is_nil(r[11])
		assert.is_nil(r[12])
	end)

	it("lit le personnage connecté en direct et les autres dans leur dernier relevé", function()
		local stocks = { ["Brumefer Hautrocher"] = { maj = 500, [11] = 7 }, ["Jean Vialjean"] = { maj = 100, [11] = 999 } }
		local vivant = function(id) return id == 11 and 5 or 0 end
		assert.are.equal(12, Stock.total(stocks, 11, miens, "Jean Vialjean", vivant)) -- 5 en direct + 7, pas 999
		local detail = Stock.detail(stocks, 11, miens, "Jean Vialjean", vivant)
		assert.are.equal("Brumefer Hautrocher", detail[1].cle)
		assert.are.equal(7, detail[1].n)
		assert.are.equal(500, detail[1].maj)
		assert.is_nil(detail[2].maj) -- le personnage connecté est lu en direct
	end)

	it("ignore les personnages qui ne sont pas à moi et ceux qui n'en ont pas", function()
		local stocks = { ["Wilgar Rolpik"] = { maj = 1, [11] = 50 } }
		assert.are.equal(0, Stock.total(stocks, 11, miens, "Jean Vialjean", function() return 0 end))
	end)

	it("signale un relevé de plus de sept jours", function()
		assert.is_false(Stock.ancien(1000, 1000 + 6 * 24 * 3600))
		assert.is_true(Stock.ancien(1000, 1000 + 8 * 24 * 3600))
		assert.is_false(Stock.ancien(nil, 5))
	end)
end)

describe("Stock : liste de courses", function()
	local function ctx(commandes, stocks, vivant)
		return { commandes = commandes, miens = miens, donnees = donnees, stocks = stocks or {},
			courant = "Jean Vialjean", vivant = vivant or function() return 0 end }
	end

	local function commande(id, client, spell, qte, extra)
		local o = { id = id, client = client, spell = spell, qte = qte, mats = "tout", statut = "ouverte" }
		for k, v in pairs(extra or {}) do o[k] = v end
		return o
	end

	it("regroupe les composants de mes commandes et compte le stock une seule fois", function()
		local liste = Stock.courses(ctx({
			a = commande("a", "Jean Vialjean", 1, 5),  -- 5 fioles, 15 lotus
			b = commande("b", "Jean Vialjean", 2, 5),  -- 10 lotus
		}, { ["Brumefer Hautrocher"] = { maj = 1, [11] = 8 } }, function(id) return id == 11 and 4 or 0 end))
		assert.are.equal(2, #liste)
		assert.are.equal("Lotus pourpre", liste[1].nom) -- le plus manquant d'abord
		assert.are.equal(25, liste[1].besoin)
		assert.are.equal(12, liste[1].stock)            -- 4 en direct + 8 chez Brumefer
		assert.are.equal(13, liste[1].manque)
		assert.are.equal(2, liste[1].commandes)
		assert.are.equal("Fiole vide", liste[2].nom)
		assert.are.equal(5, liste[2].manque)
	end)

	it("ne montre pas de manque quand le stock suffit", function()
		local liste = Stock.courses(ctx({ a = commande("a", "Jean Vialjean", 2, 1) }, {}, function() return 10 end))
		assert.are.equal(0, liste[1].manque)
		assert.are.equal("", Stock.resume(liste, "Manque :"))
	end)

	it("ignore les commandes des autres, finales, ou dont le crafteur fournit les composants", function()
		local liste = Stock.courses(ctx({
			a = commande("a", "Wilgar Rolpik", 1, 5),                                 -- pas à moi
			b = commande("b", "Jean Vialjean", 1, 5, { statut = "terminee", assigne = "Wilgar Rolpik" }),
			c = commande("c", "Jean Vialjean", 1, 5, { statut = "annulee" }),
			d = commande("d", "Jean Vialjean", 1, 5, { mats = "crafteur" }),          -- à fournir par le crafteur
		}))
		assert.are.equal(0, #liste)
	end)

	it("ajoute les commandes que j'ai prises quand c'est au crafteur de fournir", function()
		local liste = Stock.courses(ctx({
			a = commande("a", "Wilgar Rolpik", 1, 2, { mats = "crafteur", statut = "prise", assigne = "Brumefer Hautrocher" }),
			b = commande("b", "Wilgar Rolpik", 1, 2, { mats = "crafteur", statut = "ouverte" }), -- pas encore prise
			c = commande("c", "Wilgar Rolpik", 1, 2, { mats = "tout", statut = "prise", assigne = "Brumefer Hautrocher" }),
		}))
		assert.are.equal(2, #liste)
		assert.are.equal(6, liste[1].besoin) -- 3 lotus x 2
	end)

	it("garde la commande « partie » (au plus tout est à fournir) et nomme un objet sans nom par son identifiant", function()
		local liste = Stock.courses(ctx({
			a = commande("a", "Jean Vialjean", 3, 1, { mats = "partie" }),
		}))
		assert.are.equal("#12", liste[1].nom)
		assert.are.equal(1, liste[1].besoin)
	end)

	it("ignore une recette absente de la base", function()
		assert.are.equal(0, #Stock.courses(ctx({ a = commande("a", "Jean Vialjean", 99, 5) })))
	end)

	it("indique où se trouvent les composants", function()
		local liste = Stock.courses(ctx({ a = commande("a", "Jean Vialjean", 2, 1) },
			{ ["Brumefer Hautrocher"] = { maj = 5, [11] = 3 } }, function(id) return id == 11 and 1 or 0 end))
		assert.are.equal(2, #liste[1].detail)
		assert.are.equal("Brumefer Hautrocher", liste[1].detail[1].cle)
	end)

	it("résume le manque pour le chat", function()
		local liste = Stock.courses(ctx({ a = commande("a", "Jean Vialjean", 1, 5) }))
		assert.are.equal("Manque : 15 Lotus pourpre, 5 Fiole vide", Stock.resume(liste, "Manque :"))
	end)
end)
