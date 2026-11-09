-- Tests hors jeu des prix et de l'estimation de coût (Core/Prix.lua). busted tests
local ns = {}
assert(loadfile("Core/Profil.lua"))("Compagnons", ns)
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

describe("Prix partagés", function()
	local objets = { objets = { [10] = {}, [11] = {} } }

	it("à date égale, le moins cher gagne, dans les deux sens", function()
		local a, b = {}, {}
		Prix.enregistrer(a, 10, 100, 50) ; Prix.enregistrer(a, 10, 80, 50)
		Prix.enregistrer(b, 10, 80, 50) ; Prix.enregistrer(b, 10, 100, 50)
		assert.are.equal(80, a[10].p)
		assert.are.equal(80, b[10].p)
	end)

	it("valide : garde les objets connus aux valeurs plausibles, refuse le futur et les lots trop gros", function()
		local v = Prix.valider({ [10] = { p = 5.4, t = 10 }, [99] = { p = 5, t = 10 }, [11] = { p = 5, t = 9999 } }, objets, 100)
		assert.are.equal(5, v[10].p)
		assert.is_nil(v[99])
		assert.is_nil(v[11])
		local gros = {}
		for i = 1, Prix.MAX_LOT + 1 do gros[i] = { p = 1, t = 1 } end
		assert.is_nil(next(Prix.valider(gros, { objets = setmetatable({}, { __index = function() return {} end }) }, 100)))
		assert.is_nil(next(Prix.valider("x", objets, 100)))
	end)

	it("fusionne en renvoyant les identifiants modifiés", function()
		local prix = { [10] = { p = 5, t = 20 } }
		local changes = Prix.fusionner(prix, { [10] = { p = 9, t = 10 }, [11] = { p = 7, t = 10 } })
		assert.are.same({ 11 }, changes)
		assert.are.equal(5, prix[10].p)
	end)

	it("le hash ne dépend pas de l'ordre et change avec le contenu", function()
		local a = { [10] = { p = 5, t = 1 }, [11] = { p = 6, t = 2 } }
		local b = { [11] = { p = 6, t = 2 }, [10] = { p = 5, t = 1 } }
		assert.are.equal(Prix.hash(a), Prix.hash(b))
		b[10].p = 6
		assert.are_not.equal(Prix.hash(a), Prix.hash(b))
		assert.are.same({ [10] = { 1, 5, 0 }, [11] = { 2, 6, 0 } }, Prix.horodatages(a))
	end)
end)

describe("Prix de vendeur", function()
	it("un prix de vendeur l'emporte sur l'hôtel des ventes, même plus ancien, et ne se fait pas écraser", function()
		local prix = {}
		Prix.enregistrer(prix, 10, 50, 900)
		assert.is_true(Prix.enregistrer(prix, 10, 20, 100, true))
		assert.are.equal(20, prix[10].p)
		assert.is_true(prix[10].v)
		assert.is_false(Prix.enregistrer(prix, 10, 5, 2000))   -- un relevé de l'hôtel des ventes plus récent ne gagne pas
		assert.are.equal(20, prix[10].p)
	end)

	it("entre deux prix de vendeur, le plus haut gagne (la réputation ne fait que baisser le prix)", function()
		local a, b = {}, {}
		Prix.enregistrer(a, 10, 80, 1, true) ; Prix.enregistrer(a, 10, 100, 2, true)
		Prix.enregistrer(b, 10, 100, 2, true) ; Prix.enregistrer(b, 10, 80, 1, true)
		assert.are.equal(100, a[10].p)
		assert.are.equal(100, b[10].p)
		assert.is_false(Prix.enregistrer(a, 10, 100, 9, true))  -- même prix : rien ne change
	end)

	it("le drapeau survit à la validation, au hash et au résumé; un vendeur n'est jamais « ancien »", function()
		local v = Prix.valider({ [10] = { p = 7, t = 5, v = true }, [11] = { p = 7, t = 5, v = "oui" } },
			{ objets = { [10] = {}, [11] = {} } }, 100)
		assert.is_true(v[10].v)
		assert.is_nil(v[11].v)
		assert.are_not.equal(Prix.hash({ [10] = { p = 7, t = 5, v = true } }), Prix.hash({ [10] = { p = 7, t = 5 } }))
		assert.are.same({ [10] = { 5, 7, 1 } }, Prix.horodatages({ [10] = { p = 7, t = 5, v = true } }))
		assert.is_false(Prix.ancien(1, 10 ^ 9, true))
		assert.is_true(Prix.ancien(1, 10 ^ 9, false))
	end)

	it("compare un résumé distant, y compris sans drapeau (ancien format)", function()
		assert.is_nil(Prix.depuisResume("x"))
		local d = Prix.depuisResume({ 5, 7 })
		assert.is_nil(d.v)
		assert.is_true(Prix.bat({ p = 1, t = 9, v = true }, Prix.depuisResume({ 99, 1, 0 })))
	end)
end)
