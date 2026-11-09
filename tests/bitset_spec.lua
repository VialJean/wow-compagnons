-- Tests hors jeu du module Bitset : busted tests
local function charger()
	local ns = {}
	local chunk = assert(loadfile("Core/Bitset.lua"))
	chunk("Compagnons", ns)
	return ns.Bitset
end

describe("Bitset", function()
	local Bitset = charger()

	it("encode un ensemble vide en octets nuls", function()
		local s = Bitset.encoder({}, 20)
		assert.are.equal(3, #s)
		assert.are.equal(0, Bitset.compter(s))
	end)

	it("fait un aller-retour sans perte", function()
		local ensemble = { [1] = true, [8] = true, [9] = true, [42] = true, [600] = true }
		local s = Bitset.encoder(ensemble, 600)
		assert.are.equal(75, #s)
		assert.are.same(ensemble, Bitset.decoder(s))
		assert.are.equal(5, Bitset.compter(s))
	end)

	it("place le plus petit indice sur le bit de poids faible", function()
		assert.are.equal(string.char(1), Bitset.encoder({ [1] = true }, 8))
		assert.are.equal(string.char(128), Bitset.encoder({ [8] = true }, 8))
	end)

	it("ignore les indices hors bornes", function()
		local s = Bitset.encoder({ [0] = true, [5] = true, [17] = true }, 16)
		assert.are.same({ [5] = true }, Bitset.decoder(s))
	end)

	it("gère un métier complet sans dépasser la limite d'arguments", function()
		local tout = {}
		for i = 1, 4000 do tout[i] = true end
		local s = Bitset.encoder(tout, 4000)
		assert.are.equal(500, #s)
		assert.are.equal(4000, Bitset.compter(s))
	end)
end)
