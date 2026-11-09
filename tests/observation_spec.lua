-- Tests hors jeu du formatage et du tampon d'observation (Core/Observation.lua). busted tests
local ns = {}
assert(loadfile("Core/Observation.lua"))("Compagnons", ns)
local Observation = ns.Observation

describe("Observation", function()
	it("formate un événement et ses arguments", function()
		assert.are.equal("TRADE_SHOW", Observation.ligne("TRADE_SHOW"))
		assert.are.equal("UNIT_SPELLCAST_SUCCEEDED player abc 2329", Observation.ligne("UNIT_SPELLCAST_SUCCEEDED", "player", "abc", 2329))
	end)

	it("garde les arguments nil, car leur nombre compte", function()
		assert.are.equal("TRADE_ACCEPT_UPDATE 1 nil", Observation.ligne("TRADE_ACCEPT_UPDATE", 1, nil))
	end)

	it("ne détaille ni les tables ni les fonctions", function()
		assert.are.equal("{...}", Observation.texte({ 1, 2 }))
		assert.are.equal("<fonction>", Observation.texte(print))
		assert.are.equal("true", Observation.texte(true))
	end)

	it("coupe les longues chaînes et aplatit les sauts de ligne", function()
		local long = string.rep("a", 200)
		local t = Observation.texte(long)
		assert.is_true(#t < 100)
		assert.is_true(t:sub(-3) == "…")
		assert.are.equal("a b", Observation.texte("a\nb"))
	end)

	it("garde seulement les dernières entrées du tampon", function()
		local tampon = {}
		for i = 1, 10 do Observation.ajouter(tampon, 4, i, "e" .. i) end
		assert.are.equal(4, #tampon)
		assert.are.equal("e7", tampon[1][2])
		assert.are.equal("e10", tampon[4][2])
	end)

	it("renvoie les n dernières lignes dans l'ordre, avec l'heure formatée", function()
		local tampon = {}
		for i = 1, 5 do Observation.ajouter(tampon, 100, i, "e" .. i) end
		local l = Observation.dernieres(tampon, 3, function(t) return "h" .. t end)
		assert.are.same({ "h3 e3", "h4 e4", "h5 e5" }, l)
		assert.are.equal(5, #Observation.dernieres(tampon, 50))
		assert.are.same({}, Observation.dernieres({}, 5))
	end)
end)
