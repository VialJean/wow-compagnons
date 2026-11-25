-- Tests hors jeu du chercheur d'améliorations (Core/Ameliorations.lua), avec des équipements simulés. busted tests
local ns = {}
assert(loadfile("Core/Poids.lua"))("Compagnons", ns)
assert(loadfile("Core/Ameliorations.lua"))("Compagnons", ns)
local A = ns.Ameliorations

-- Armure : classe 4 ; sous-classes 1 étoffe, 2 cuir, 3 mailles, 4 plaques, 6 bouclier. Armes : classe 2.
local function recette(emplacement, ilvl, requis, classe, sous, stats, extra)
	local r = { metier = 164, lie = true,
		equip = { emplacement = emplacement, ilvl = ilvl, requis = requis, classe = classe, sous = sous, stats = stats } }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local donnees = { recettes = {
	[1] = recette(5, 30, 20, 4, 4, { { 4, 10 }, { 7, 8 } }),                -- plastron en plaques : force, endurance
	[2] = recette(5, 30, 20, 4, 1, { { 5, 12 }, { 6, 6 } }),                -- plastron d'étoffe : intelligence, esprit
	[3] = recette(5, 22, 15, 4, 4, { { 4, 6 }, { 7, 5 } }),                 -- plastron en plaques, plus faible
	[4] = recette(5, 40, 35, 4, 4, { { 4, 14 } }),                          -- trop haut niveau pour le joueur (30)
	[5] = recette(11, 25, 10, 4, 0, { { 4, 3 } }),                          -- anneau (emplacements doubles)
	[6] = recette(12, 26, 10, 4, 0, { { 3, 3 } }),                          -- bijou
	[7] = recette(13, 28, 10, 2, 7, { { 4, 5 } }),                          -- arme 1M : épée
	[8] = recette(13, 29, 10, 2, 19, { { 45, 9 } }),                        -- baguette : pas pour un guerrier
	[9] = recette(5, 35, 20, 4, 4, { { 4, 12 } }, { lie = false }),         -- lié quand ramassé
	[10] = recette(22, 27, 10, 2, 7, { { 4, 5 } }),                         -- arme de main gauche
	[11] = recette(14, 26, 10, 4, 6, { { 7, 9 } }),                         -- bouclier
	[12] = recette(7, 30, 10, 0, 0, { { 4, 4 } }),                          -- classe inconnue : accepté, non vérifié
	[13] = { metier = 164, lie = true },                                    -- pas d'équipement (potion…)
} }

local function ctx(extra)
	local c = {
		donnees = donnees, niveau = 30, classe = "WARRIOR",
		equipement = {},
		crafteurs = function() return 1 end,
		possede = function() return false end,
	}
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end

local function groupe(resultat, emplacement)
	for _, g in ipairs(resultat) do
		if g.emplacement == emplacement then return g end
	end
end

local function candidats(resultat, emplacement)
	for _, g in ipairs(resultat) do
		if g.emplacement == emplacement then
			local l = {}
			for _, c in ipairs(g.candidats) do l[#l + 1] = c.spell end
			return l
		end
	end
	return {}
end

describe("Ameliorations.portable", function()
	it("une armure selon le type que la classe peut porter", function()
		assert.is_true((A.portable("WARRIOR", { emplacement = 5, classe = 4, sous = 4 })))
		assert.is_false((A.portable("WARRIOR", { emplacement = 5, classe = 4, sous = 0 })))
		assert.is_false((A.portable("MAGE", { emplacement = 5, classe = 4, sous = 4 })))
		assert.is_true((A.portable("MAGE", { emplacement = 5, classe = 4, sous = 1 })))
	end)

	it("bijoux, anneaux, cols et dos sont libres", function()
		for _, e in ipairs({ 2, 11, 12, 16 }) do
			assert.is_true((A.portable("MAGE", { emplacement = e, classe = 4, sous = 4 })))
		end
	end)

	it("une arme selon la classe, et la main gauche seulement pour qui manie deux armes", function()
		assert.is_true((A.portable("WARRIOR", { emplacement = 13, classe = 2, sous = 7 })))
		assert.is_false((A.portable("WARRIOR", { emplacement = 13, classe = 2, sous = 19 })))
		assert.is_true((A.portable("MAGE", { emplacement = 13, classe = 2, sous = 19 })))
		assert.is_true((A.portable("ROGUE", { emplacement = 22, classe = 2, sous = 15 })))
		assert.is_false((A.portable("MAGE", { emplacement = 22, classe = 2, sous = 15 })))
	end)

	it("un bouclier seulement pour les classes qui en portent", function()
		assert.is_true((A.portable("PALADIN", { emplacement = 14 })))
		assert.is_false((A.portable("MAGE", { emplacement = 14 })))
	end)

	it("dit quand le jugement n'est pas sûr (classe d'objet inconnue)", function()
		local ok, sur = A.portable("WARRIOR", { emplacement = 7, classe = 0, sous = 0 })
		assert.is_true(ok)
		assert.is_false(sur)
	end)
end)

describe("Ameliorations.pertinent", function()
	it("garde ce dont la majorité du budget est utile à la classe", function()
		assert.is_true(A.pertinent("WARRIOR", { { 4, 10 }, { 7, 8 } }))
		assert.is_false(A.pertinent("WARRIOR", { { 5, 12 }, { 6, 6 }, { 7, 2 } }))
		assert.is_true(A.pertinent("MAGE", { { 5, 12 }, { 45, 9 } }))
	end)

	it("ne s'oppose à rien sans stats", function()
		assert.is_true(A.pertinent("WARRIOR", {}))
		assert.is_true(A.pertinent("WARRIOR", nil))
		assert.is_true(A.pertinent("INCONNUE", { { 4, 1 } }))
	end)
end)

describe("Ameliorations.chercher", function()
	it("propose ce qui bat l'objet porté, trié par gain, sans faux positifs", function()
		local r = A.chercher(ctx({ equipement = { [5] = { itemID = 100, ilvl = 24 } } }))
		-- plastron en plaques de 30 (gain 6) ; le 22 ne bat pas 24 ; l'étoffe est refusée ; le 40 est trop haut niveau ; le lié ramassé
		-- est exclu
		assert.same({ 1 }, candidats(r, 5))
		local g = groupe(r, 5).candidats[1]
		assert.equal(6, g.gain)
		assert.equal(24, g.porteIlvl)
		assert.equal(100, g.porteItem)
		assert.is_true(g.verifie)
		-- la recette sans classe d'objet connue est acceptée, mais signalée non vérifiée
		assert.is_false(groupe(r, 7).candidats[1].verifie)
	end)

	it("un emplacement vide est toujours une amélioration", function()
		local r = A.chercher(ctx())
		assert.same({ 1, 3 }, candidats(r, 5))
		assert.equal(30, groupe(r, 5).candidats[1].gain)
	end)

	it("exclut les objets liés quand ramassés sauf si le joueur a le métier", function()
		assert.is_false((function()
			for _, s in ipairs(candidats(A.chercher(ctx()), 5)) do if s == 9 then return true end end
			return false
		end)())
		local avec = A.chercher(ctx({ possede = function(m) return m == 164 end }))
		assert.same({ 9, 1, 3 }, candidats(avec, 5)) -- 35 d'abord
	end)

	it("compare un anneau au moins bon des deux portés", function()
		local r = A.chercher(ctx({ equipement = { [11] = { itemID = 1, ilvl = 40 }, [12] = { itemID = 2, ilvl = 20 } } }))
		assert.same({ 5 }, candidats(r, 11))
		assert.equal(20, groupe(r, 11).candidats[1].porteIlvl)
		assert.equal(2, groupe(r, 11).candidats[1].porteItem)
		-- un seul anneau porté : le second emplacement est vide, donc toujours une amélioration
		r = A.chercher(ctx({ equipement = { [11] = { itemID = 1, ilvl = 40 } } }))
		assert.same({ 5 }, candidats(r, 11))
	end)

	it("ne propose pas une arme que la classe ne manie pas", function()
		local r = A.chercher(ctx())
		assert.same({ 7 }, candidats(r, 16))     -- l'épée, pas la baguette
		assert.same({ 10, 11 }, candidats(r, 17)) -- guerrier : main gauche et bouclier se comparent à la main gauche portée
	end)

	it("restreint par défaut à ce que la guilde sait fabriquer", function()
		local sans = A.chercher(ctx({ crafteurs = function(s) return s == 1 and 2 or 0 end }))
		assert.same({ 1 }, candidats(sans, 5))
		local tout = A.chercher(ctx({ crafteurs = function() return 0 end, options = { guilde = false } }))
		assert.same({ 1, 3 }, candidats(tout, 5))
		assert.same({}, A.chercher(ctx({ crafteurs = function() return 0 end })))
	end)

	it("peut ne garder que les crafteurs en ligne", function()
		local r = A.chercher(ctx({
			options = { enLigne = true }, crafteursEnLigne = function(s) return s == 12 and 1 or 0 end,
		}))
		assert.same({}, candidats(r, 5))
		assert.same({ 12 }, candidats(r, 7))
	end)

	it("classe les emplacements dans l'ordre", function()
		local r = A.chercher(ctx())
		local ordre = {}
		for _, g in ipairs(r) do ordre[#ordre + 1] = g.emplacement end
		local trie = {}
		for i, v in ipairs(ordre) do trie[i] = v end
		table.sort(trie)
		assert.same(trie, ordre)
	end)
end)

describe("Ameliorations avec une spécialisation", function()
	local plastrons = { recettes = {
		[1] = recette(5, 30, 20, 4, 4, { { 4, 10 }, { 7, 8 } }, { objet = 101 }),   -- ilvl 30
		[2] = recette(5, 24, 20, 4, 4, { { 7, 12 }, { 14, 6 } }, { objet = 102 }),  -- ilvl 24, mais bien meilleur pour un tank
		[3] = recette(5, 28, 20, 4, 4, {}, { objet = 103 }),                         -- sans stats : niveau d'objet
		[4] = recette(13, 28, 10, 2, 7, { { 4, 5 } }, { objet = 104 }),             -- arme : toujours le niveau d'objet
	} }
	-- Vraies stats lues dans le jeu (les `stats` des recettes ne sont que des parts de budget).
	local reelles = { [101] = { { 4, 10 }, { 7, 8 } }, [102] = { { 7, 12 }, { 14, 6 } }, [104] = { { 4, 500 } } }
	local function chercher(spec, equipement, stats)
		return A.chercher(ctx({ donnees = plastrons, spec = spec, equipement = equipement,
			statsObjet = function(id) return (stats or reelles)[id] end }))
	end
	-- Poids du guerrier protection avant le 60 : endurance 3, parade 0,6, force 0,25.
	local porte = { [5] = { itemID = 9, ilvl = 26, stats = { { 7, 10 }, { 14, 2 } } } } -- 30 + 1,2 = 31,2

	it("compare les scores de stats, pas les niveaux d'objet", function()
		local r = chercher("protection", porte)
		-- le 1 (ilvl 30) vaut 2,5 + 24 = 26,5 : moins que l'objet porté ; le 2 (ilvl 24) vaut 39,6 : gain de 8,4
		assert.same({ 2, 3 }, candidats(r, 5))
		local c = groupe(r, 5).candidats[1]
		assert.equal("stats", c.unite)
		assert.is_true(math.abs(c.gain - 8.4) < 1e-6)
		assert.equal(26, c.porteIlvl)
		assert.equal("ilvl", groupe(r, 5).candidats[2].unite) -- le 3, sans stats, retombe sur le niveau d'objet
	end)

	it("sans spécialisation, ou avec une inconnue, compare le niveau d'objet", function()
		assert.same({ 1, 3 }, candidats(chercher(nil, porte), 5))
		assert.same({ 1, 3 }, candidats(chercher("inconnue", porte), 5))
	end)

	it("retombe sur le niveau d'objet sans stats lisibles, pour l'objet porté comme pour le candidat", function()
		local r = chercher("protection", { [5] = { itemID = 9, ilvl = 26 } })
		assert.same({ 1, 3 }, candidats(r, 5))
		assert.equal("ilvl", groupe(r, 5).candidats[1].unite)
		assert.same({ 1, 3 }, candidats(chercher("protection", porte, {}), 5)) -- le jeu n'a pas encore les objets en cache
	end)

	it("un emplacement vide a un score de 0, les candidats par score passent en premier", function()
		assert.same({ 2, 1, 3 }, candidats(chercher("protection", {}), 5))
	end)

	it("les armes se comparent toujours par niveau d'objet", function()
		local r = chercher("protection", { [16] = { itemID = 8, ilvl = 20, stats = { { 4, 900 } } } })
		assert.same({ 4 }, candidats(r, 16)) -- 28 > 20 ; un score de stats aurait écarté l'arme (500 < 900)
		assert.equal("ilvl", groupe(r, 16).candidats[1].unite)
	end)

	it("propose les spécialisations de la classe et pèse avec leurs poids", function()
		assert.equal("arms", A.specs("WARRIOR")[1].cle)
		assert.equal(1, A.specs("WARRIOR")[1].id) -- numéro de l'arbre de talents
		assert.is_nil(A.specs("PALADIN")[4].id)    -- paladin choc : pas un arbre
		assert.same({}, A.specs("INCONNUE"))
		assert.equal(5, A.score({ { 7, 4 }, { 4, 2 } }, { [7] = 1, [4] = 0.5 }))
	end)
end)

describe("Ameliorations.donneesPresentes", function()
	it("détecte une base sans équipement (générée avant la 0.6)", function()
		assert.is_true(A.donneesPresentes(donnees))
		assert.is_false(A.donneesPresentes({ recettes = { [1] = { metier = 1 }, [2] = { metier = 1, lie = true } } }))
	end)
end)
