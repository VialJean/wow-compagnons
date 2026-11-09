-- Tests hors jeu des prix et de l'estimation de coût (Core/Prix.lua). busted tests
local ns = {}
assert(loadfile("Core/Prix.lua"))("Compagnons", ns)
local Prix = ns.Prix

local donnees = {
	recettes = {
		[1] = { composants = { { 10, 1 }, { 11, 3 } } },
		[2] = { composants = { { 12, 2 } } },
	},
}

describe("Prix : enregistrement", function()
	it("enregistre un prix unitaire arrondi au cuivre", function()
		local prix = {}
		assert.is_true(Prix.enregistrer(prix, 10, 250.4, 1000))
		assert.are.equal(250, prix[10].p)
		assert.are.equal(1000, prix[10].t)
	end)

	it("le plus récent gagne, un relevé plus ancien est refusé", function()
		local prix = {}
		Prix.enregistrer(prix, 10, 250, 1000)
		assert.is_true(Prix.enregistrer(prix, 10, 300, 2000))
		assert.is_false(Prix.enregistrer(prix, 10, 100, 1500)) -- plus ancien
		assert.are.equal(300, prix[10].p)
	end)

	it("refuse les valeurs aberrantes ou invalides", function()
		local prix = {}
		assert.is_false(Prix.enregistrer(prix, 10, 0, 1))
		assert.is_false(Prix.enregistrer(prix, 10, -5, 1))
		assert.is_false(Prix.enregistrer(prix, 10, 3e9, 1))
		assert.is_false(Prix.enregistrer(prix, 10, 0 / 0, 1))
		assert.is_false(Prix.enregistrer(prix, "x", 5, 1))
		assert.is_false(Prix.enregistrer(prix, 10, "5", 1))
		assert.is_nil(prix[10])
	end)

	it("garde le prix unitaire le plus bas d'une liste de lots, achat immédiat seulement", function()
		assert.are.equal(100, Prix.minimum({ { 5, 600 }, { 10, 1000 }, { 1, 150 } })) -- 120, 100, 150
		assert.are.equal(120, Prix.minimum({ { 5, 600 }, { 3, 0 }, { 0, 50 } }))      -- lots sans achat ou sans quantité ignorés
		assert.is_nil(Prix.minimum({ { 5, 0 } }))
		assert.is_nil(Prix.minimum({}))
	end)
end)

describe("Prix : coûts", function()
	local maintenant = 100000
	local prix

	before_each(function()
		prix = {}
		Prix.enregistrer(prix, 10, 500, maintenant - 100)
		Prix.enregistrer(prix, 11, 20000, maintenant - 200)
	end)

	it("calcule le coût d'une recette pour une quantité", function()
		local r = Prix.coutRecette(donnees, prix, 1, 5, maintenant) -- 5 x 500 + 15 x 20000
		assert.are.equal(5 * 500 + 15 * 20000, r.total)
		assert.are.equal(0, r.inconnus)
	end)

	it("compte les composants sans prix au lieu de les ignorer en silence", function()
		local r = Prix.coutRecette(donnees, prix, 2, 3, maintenant) -- 12 inconnu
		assert.are.equal(0, r.total)
		assert.are.equal(1, r.inconnus)
	end)

	it("somme les connus et signale les inconnus", function()
		prix[11] = nil
		local r = Prix.coutRecette(donnees, prix, 1, 2, maintenant)
		assert.are.equal(2 * 500, r.total)
		assert.are.equal(1, r.inconnus)
	end)

	it("signale les prix anciens (plus de trois jours)", function()
		prix[10].t = maintenant - 4 * 24 * 3600
		local r = Prix.coutRecette(donnees, prix, 1, 1, maintenant)
		assert.are.equal(1, r.anciens)
		assert.are.equal(maintenant - 4 * 24 * 3600, r.plusAncien)
	end)

	it("ignore une recette absente de la base", function()
		local r = Prix.coutRecette(donnees, prix, 99, 5, maintenant)
		assert.are.equal(0, r.total)
		assert.are.equal(0, r.inconnus)
	end)

	it("calcule le coût du manque d'une liste de courses et remplit chaque ligne", function()
		local liste = {
			{ itemID = 10, manque = 4 },
			{ itemID = 11, manque = 0 },    -- rien à acheter : coût nul, pas inconnu
			{ itemID = 12, manque = 2 },    -- prix inconnu
		}
		local r = Prix.coutListe(prix, liste, maintenant)
		assert.are.equal(2000, r.total)
		assert.are.equal(1, r.inconnus)
		assert.are.equal(2000, liste[1].cout)
		assert.are.equal(500, liste[1].prixUnitaire)
		assert.are.equal(0, liste[2].cout)
		assert.is_nil(liste[3].cout)
	end)
end)

describe("Prix : montants", function()
	it("décompose en or, argent et cuivre", function()
		local o, a, c = Prix.pieces(123456)
		assert.are.equal(12, o)
		assert.are.equal(34, a)
		assert.are.equal(56, c)
		assert.are.same({ 0, 0, 0 }, { Prix.pieces(nil) })
	end)

	it("écrit un montant lisible, sans détail inutile au-delà de dix pièces d'or", function()
		assert.are.equal("12g", Prix.texte(123456))
		assert.are.equal("1g 5s", Prix.texte(10500))
		assert.are.equal("1g 0s 5c", Prix.texte(10005))
		assert.are.equal("50c", Prix.texte(50))
		assert.are.equal("0c", Prix.texte(0))
		assert.are.equal("1 po", Prix.texte(10000, { or_ = " po", argent = " pa", cuivre = " pc" }))
	end)

	it("lit un montant saisi", function()
		assert.are.equal(120000, Prix.lire("12"))
		assert.are.equal(125000, Prix.lire("12.5"))
		assert.are.equal(125000, Prix.lire("12,5"))
		assert.are.equal(120503, Prix.lire("12g 5s 3c"))
		assert.are.equal(500, Prix.lire("5s"))
		assert.is_nil(Prix.lire("beaucoup"))
		assert.is_nil(Prix.lire(nil))
	end)
end)
