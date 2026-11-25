-- Tests hors jeu du chercheur d'améliorations (Core/Ameliorations.lua), avec des équipements simulés. busted tests
local ns = {}
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

describe("Ameliorations : stats et spécialisation", function()
	it("le poids d'une stat dépend de la classe et de l'arbre de talents", function()
		local tank, degats = A.poids("WARRIOR", 3), A.poids("WARRIOR", 1)
		assert.is_true(tank[12] > (degats[12] or 0))           -- défense
		assert.is_true(degats[38] > (tank[38] or 0))           -- puissance d'attaque
		assert.is_true(A.poids("PRIEST", 3)[42] > 0)    -- dégâts des sorts pour l'ombre
		assert.equal(0, A.poids("PRIEST", 2)[42] or 0)  -- pas pour le soin
		-- spécialisation inconnue : la liste des stats utiles de la classe, à égalité
		assert.equal(1, A.poids("WARRIOR", nil)[4])
		assert.is_nil(A.poids("INCONNUE", 1))
	end)

	it("l'utilité est la part du budget qui tombe dans les stats recherchées, rapport seul", function()
		local p = { [4] = 1, [7] = 0.5 }
		assert.is_near(1, A.utilite(p, { { 4, 100 } }), 1e-9)
		assert.is_near(0.75, A.utilite(p, { { 4, 5000 }, { 7, 5000 } }), 1e-9)
		assert.is_near(A.utilite(p, { { 4, 1 }, { 7, 1 } }), A.utilite(p, { { 4, 9000 }, { 7, 9000 } }), 1e-9)
		-- armure supplémentaire, résistances et types inconnus ne comptent pas
		assert.is_near(1, A.utilite(p, { { 4, 100 }, { 50, 900000 }, { 51, 7000 }, { 85, 5000 } }), 1e-9)
		assert.is_nil(A.utilite(p, { { 50, 100 } }))
		assert.is_nil(A.utilite(p, {}))
	end)

	it("convertit les stats du jeu en types", function()
		local l = A.statsDuJeu({ ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_INCONNU_SHORT = 3 })
		assert.same({ { 4, 7 }, { 7, 12 } }, l)
		assert.is_nil(A.statsDuJeu({}))
		assert.is_nil(A.statsDuJeu(nil))
	end)

	it("une grosse armure supplémentaire ne rend pas un objet inutile à la classe", function()
		assert.is_true(A.pertinent("WARRIOR", { { 7, 2800 }, { 50, 40000 }, { 51, 7200 } }))
	end)

	local function etoffes(role)
		-- deux plastrons de même niveau : un à intelligence et puissance des sorts, un à force
		local d = { recettes = {
			[1] = recette(5, 30, 20, 4, 1, { { 5, 10000 }, { 45, 10000 } }),
			[2] = recette(5, 30, 20, 4, 1, { { 4, 10000 }, { 7, 5000 } }),
		} }
		return A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = role }))
	end

	it("classe d'abord ce qui sert la spécialisation du joueur", function()
		-- prêtre : l'étoffe force/endurance est écartée par la classe, seul le premier reste
		assert.same({ 1 }, candidats(etoffes(2), 5))
	end)

	it("à niveau égal, la spécialisation départage les candidats", function()
		local d = { recettes = {
			[1] = recette(5, 30, 20, 4, 1, { { 5, 10000 }, { 41, 10000 } }),   -- soins
			[2] = recette(5, 30, 20, 4, 1, { { 5, 10000 }, { 42, 8000 } }),    -- dégâts
		} }
		local soin = candidats(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 2 })), 5)
		local ombre = candidats(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 3 })), 5)
		assert.same({ 1, 2 }, soin)
		assert.same({ 2, 1 }, ombre)
	end)

	it("un objet de niveau plus haut mais aux stats inutiles ne bat plus un objet porté bien adapté", function()
		local d = { recettes = {
			[1] = recette(5, 34, 20, 4, 1, { { 5, 10000 }, { 41, 10000 } }),  -- niveau 34, soins
		} }
		local equip = { [5] = { itemID = 9, ilvl = 30, stats = { { 5, 20 }, { 42, 25 } } } } -- niveau 30, dégâts
		-- ombre : porté très adapté (30 × 0,96 environ), candidat de soins mal adapté : pas proposé
		assert.same({}, candidats(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 3, equipement = equip })), 5))
		-- soin : le candidat est adapté, le porté ne l'est pas : proposé, même avec un niveau voisin
		assert.same({ 1 }, candidats(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 2, equipement = equip })), 5))
	end)

	it("sans stats connues sur l'objet porté, le niveau d'objet décide", function()
		local d = { recettes = { [1] = recette(5, 31, 20, 4, 1, { { 5, 10000 }, { 41, 1000 }, { 42, 9000 } }) } }
		local equip = { [5] = { itemID = 9, ilvl = 30 } }
		assert.same({ 1 }, candidats(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 2, equipement = equip })), 5))
		local c = groupe(A.chercher(ctx({ donnees = d, classe = "PRIEST", spec = 2, equipement = equip })), 5).candidats[1]
		assert.is_number(c.utilite)
		assert.equal(1, c.gain)
	end)
end)

describe("Ameliorations.donneesPresentes", function()
	it("détecte une base sans équipement (générée avant la 0.6)", function()
		assert.is_true(A.donneesPresentes(donnees))
		assert.is_false(A.donneesPresentes({ recettes = { [1] = { metier = 1 }, [2] = { metier = 1, lie = true } } }))
	end)
end)
