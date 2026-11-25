-- Tests hors jeu des pourboires (Core/Pourboire.lua et leur place dans les commandes). busted tests
local ns = { Profil = { adler = function(s) return #s end } }
assert(loadfile("Core/Pourboire.lua"))("Compagnons", ns)
assert(loadfile("Core/Commandes.lua"))("Compagnons", ns)
local Pourboire, Commandes = ns.Pourboire, ns.Commandes

local donnees = { recettes = { [2329] = {} } }
local T0 = 1731180000

local function commande(pourboire)
	return Commandes.nouvelle({ client = "Wilgar Rolpik", spell = 2329, qte = 1, mats = "partie", maintenant = T0,
		pourboire = pourboire })
end

describe("Pourboire", function()
	it("n'accepte que des montants entiers de cuivre dans les bornes", function()
		assert.equal(0, Pourboire.normaliser(0))
		assert.equal(12345, Pourboire.normaliser(12345.7))
		assert.is_nil(Pourboire.normaliser(-1))
		assert.is_nil(Pourboire.normaliser(Pourboire.MAX + 1))
		assert.is_nil(Pourboire.normaliser(0 / 0))
		assert.is_nil(Pourboire.normaliser("500"))
		assert.is_nil(Pourboire.normaliser(nil))
	end)

	it("suggère 10 % du coût, arrondi à l'argent supérieur, et rien sans prix", function()
		assert.equal(0, Pourboire.suggere(0))
		assert.equal(0, Pourboire.suggere(nil))
		assert.equal(100, Pourboire.suggere(50))      -- au moins 1 pa
		assert.equal(1000, Pourboire.suggere(10000))  -- 1 po de composants -> 10 pa
		assert.equal(1100, Pourboire.suggere(10050))  -- 10,05 pa arrondi à 11 pa
		assert.equal(Pourboire.MAX, Pourboire.suggere(Pourboire.MAX * 100))
	end)

	it("compose or, argent et cuivre", function()
		assert.equal(125050, Pourboire.composer(12, 50, 50))
		assert.equal(30000, Pourboire.composer("3", nil, nil))
		assert.equal(0, Pourboire.composer(nil, nil, nil))
		assert.equal(0, Pourboire.composer(Pourboire.MAX, 1, 0)) -- hors borne : refusé
	end)
end)

describe("Pourboire d'une commande", function()
	it("est gardé à la création, absent s'il est nul ou invalide", function()
		assert.equal(25000, commande(25000).pourboire)
		assert.is_nil(commande(0).pourboire)
		assert.is_nil(commande(-5).pourboire)
		assert.is_nil(commande(nil).pourboire)
	end)

	it("ne change pas le hash : une ancienne version, qui ignore le champ, reste d'accord", function()
		local avec = commande(25000)
		local sans = {}
		for k, v in pairs(avec) do sans[k] = v end
		sans.pourboire = nil
		assert.equal(Commandes.hash(sans), Commandes.hash(avec))
	end)

	it("suit la commande à chaque transition", function()
		local c = commande(25000)
		local n = assert(Commandes.appliquer(c, "prendre", "Jean Vialjean", T0 + 1))
		assert.equal(25000, n.pourboire)
		n = assert(Commandes.appliquer(n, "livrer", "Jean Vialjean", T0 + 2))
		assert.equal(25000, n.pourboire)
	end)

	it("est validé à la réception", function()
		local brut = commande(25000)
		assert.equal(25000, Commandes.valider(brut, donnees).pourboire)
		brut.pourboire = -1
		assert.is_nil(Commandes.valider(brut, donnees).pourboire)
		brut.pourboire = "beaucoup"
		assert.is_nil(Commandes.valider(brut, donnees).pourboire)
		brut.pourboire = Pourboire.MAX * 2
		assert.is_nil(Commandes.valider(brut, donnees).pourboire)
	end)

	it("garde sa valeur à travers la validation d'une copie du réseau", function()
		local c = commande(1234)
		local v = Commandes.valider(c, donnees)
		assert.equal(1234, v.pourboire)
		assert.equal(c.hash, v.hash)
	end)
end)
