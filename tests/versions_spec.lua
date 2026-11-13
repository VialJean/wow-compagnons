-- Tests hors jeu du suivi des versions de protocole des pairs (Core/Versions.lua). busted tests
local ns = {}
assert(loadfile("Core/Versions.lua"))("Compagnons", ns)
local Versions = ns.Versions

local P = 3
local T0 = 1731180000
local JOUR = Versions.JOUR

local function etat() return Versions.nouveau() end

describe("Versions.noter", function()
	it("signale un pair en protocole 2 comme nouveau, puis comme déjà connu", function()
		local e = etat()
		assert.are.equal("nouveau", Versions.noter(e, "Bastien Roux", 2, T0, P, "Bastien-Roux"))
		assert.are.equal("obsolete", Versions.noter(e, "Bastien Roux", 2, T0 + 60, P, "Bastien-Roux"))
		assert.are.equal(T0 + 60, e.pairs["Bastien Roux"].vu)
		assert.are.equal("Bastien-Roux", e.pairs["Bastien Roux"].brut)
	end)

	it("ne retient rien d'un pair à la même version", function()
		local e = etat()
		assert.are.equal("ajour", Versions.noter(e, "Alice Durand", 3, T0, P))
		assert.is_nil(next(e.pairs))
	end)

	it("un pair qui se met à jour sort de la liste", function()
		local e = etat()
		Versions.noter(e, "Bastien Roux", 2, T0, P)
		assert.are.equal("misajour", Versions.noter(e, "Bastien Roux", 3, T0 + 10, P))
		assert.is_nil(e.pairs["Bastien Roux"])
	end)

	it("signale une version plus récente que la nôtre, une seule fois par version", function()
		local e = etat()
		assert.are.equal("plusrecente", Versions.noter(e, "Zed Zorro", 4, T0, P))
		assert.are.equal("plusrecent", Versions.noter(e, "Zed Zorro", 4, T0 + 5, P))
		assert.are.equal("plusrecent", Versions.noter(e, "Alice Durand", 4, T0 + 6, P))
		assert.are.equal("plusrecente", Versions.noter(e, "Zed Zorro", 5, T0 + 7, P)) -- une version encore plus récente
		assert.are.equal(5, Versions.plusRecente(e, P))
		assert.is_nil(next(e.pairs)) -- ce n'est pas un pair obsolète
	end)

	it("ignore une version illisible", function()
		local e = etat()
		for _, v in ipairs({ 0, -1, 2.5, 0 / 0 }) do assert.is_nil(Versions.noter(e, "Bastien Roux", v, T0, P)) end
		assert.is_nil(Versions.noter(e, "Bastien Roux", "2", T0, P))
		assert.is_nil(Versions.noter(e, "Bastien Roux", nil, T0, P))
		assert.is_nil(Versions.noter(e, "", 2, T0, P))
		assert.is_nil(Versions.noter(e, nil, 2, T0, P))
		assert.is_nil(next(e.pairs))
	end)

	it("limite le nombre de pairs retenus (messages forgés en masse)", function()
		local e = etat()
		for i = 1, 300 do Versions.noter(e, "Faux" .. i .. " Pair", 2, T0, P) end
		local n = 0
		for _ in pairs(e.pairs) do n = n + 1 end
		assert.are.equal(200, n)
		-- un pair déjà connu reste mis à jour malgré la limite
		assert.are.equal("obsolete", Versions.noter(e, "Faux1 Pair", 2, T0 + 5, P))
	end)

	it("tronque un nom d'expéditeur démesuré", function()
		local e = etat()
		Versions.noter(e, "Bastien Roux", 2, T0, P, string.rep("x", 500))
		assert.are.equal(64, #e.pairs["Bastien Roux"].brut)
	end)
end)

describe("Versions.obsoletes", function()
	it("liste les pairs obsolètes par ordre alphabétique", function()
		local e = etat()
		Versions.noter(e, "Camille Petit", 2, T0, P)
		Versions.noter(e, "Alice Durand", 1, T0, P)
		local l = Versions.obsoletes(e, T0 + 1, P)
		assert.are.equal(2, #l)
		assert.are.equal("Alice Durand", l[1].cle)
		assert.are.equal(1, l[1].v)
		assert.are.equal("Camille Petit", l[2].cle)
	end)

	it("oublie un pair qu'on n'a pas vu depuis 14 jours", function()
		local e = etat()
		Versions.noter(e, "Bastien Roux", 2, T0, P)
		assert.are.equal(1, #Versions.obsoletes(e, T0 + Versions.OUBLI, P))
		assert.are.equal(0, #Versions.obsoletes(e, T0 + Versions.OUBLI + 1, P))
	end)

	it("oublie tout quand notre propre protocole a rattrapé la version vue", function()
		local e = etat()
		Versions.noter(e, "Zed Zorro", 4, T0, P)
		assert.are.equal(4, Versions.plusRecente(e, P))
		-- la 0.6 sort : notre protocole passe à 4
		assert.is_nil(Versions.plusRecente(e, 4))
		Versions.purger(e, T0 + 5, 4)
		assert.is_nil(e.plusRecente)
	end)
end)

describe("Versions.aPrevenir", function()
	it("la première détection se prévient une seule fois", function()
		local e = etat()
		Versions.noter(e, "Bastien Roux", 2, T0, P, "Bastien-Roux")
		local l = Versions.aPrevenir(e, T0, P, true)
		assert.are.equal(1, #l)
		assert.are.equal("Bastien-Roux", l[1].brut)
		Versions.marquer(e, "Bastien Roux", T0)
		assert.are.equal(0, #Versions.aPrevenir(e, T0 + 3 * JOUR, P, true)) -- l'automatique ne revient jamais
	end)

	it("le bouton ne reprévient personne avant un jour", function()
		local e = etat()
		Versions.noter(e, "Bastien Roux", 2, T0, P)
		Versions.noter(e, "Camille Petit", 2, T0, P)
		Versions.marquer(e, "Bastien Roux", T0)
		assert.are.equal(1, #Versions.aPrevenir(e, T0 + 60, P, false)) -- Camille seulement
		assert.are.equal("Camille Petit", Versions.aPrevenir(e, T0 + 60, P, false)[1].cle)
		assert.are.equal(2, #Versions.aPrevenir(e, T0 + JOUR, P, false)) -- un jour plus tard : les deux
		assert.are.equal(1, #Versions.aPrevenir(e, T0 + JOUR - 1, P, false))
	end)

	it("marquer un pair inconnu ne fait rien", function()
		local e = etat()
		Versions.marquer(e, "Personne Ici", T0)
		assert.is_nil(next(e.pairs))
	end)
end)
