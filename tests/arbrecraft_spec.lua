-- Tests hors jeu de l'arbre de craft (Core/ArbreCraft.lua). busted tests
local ns = {}
assert(loadfile("Core/ArbreCraft.lua"))("Compagnons", ns)
local ArbreCraft = ns.ArbreCraft

-- Minerai (1) -> barre (2) -> plaque (3) -> épée (spell 400). Fil (4) est une matière première.
local donnees = { recettes = {
	[100] = { objet = 2, qte = 1, composants = { { 1, 2 } } },            -- 2 minerais -> 1 barre
	[200] = { objet = 3, qte = 1, composants = { { 2, 3 } } },            -- 3 barres -> 1 plaque
	[400] = { objet = 5, qte = 1, composants = { { 3, 2 }, { 4, 1 } } },  -- 2 plaques + 1 fil -> épée
	[500] = { objet = 6, qte = 2, composants = { { 1, 1 } } },            -- 1 minerai -> 2 lingots
	[600] = { objet = 7, qte = 1, composants = { { 6, 3 } } },            -- 3 lingots -> objet
	[700] = { objet = 8, qte = 1, composants = { { 9, 1 } } },            -- boucle : 8 <- 9
	[701] = { objet = 9, qte = 1, composants = { { 8, 1 } } },            --          9 <- 8
	[800] = { objet = 10, qte = 1, composants = { { 8, 1 } } },
} }

local function creant(itemID)
	local l = {}
	for spellID, r in pairs(donnees.recettes) do
		if r.objet == itemID then l[#l + 1] = spellID end
	end
	table.sort(l)
	return l
end

local function feuilles(arbre)
	local t = {}
	for _, f in ipairs(arbre.feuilles) do t[f.itemID] = f.qte end
	return t
end

describe("ArbreCraft", function()
	it("descend jusqu'aux matières premières et multiplie les quantités", function()
		local arbre = ArbreCraft.construire(donnees, creant, 400, 1)
		-- épée : 2 plaques = 6 barres = 12 minerais, plus 1 fil
		assert.same({ [1] = 12, [4] = 1 }, feuilles(arbre))
		assert.equal(2, ArbreCraft.etages(arbre))
		local plaque = arbre.racine.enfants[1]
		assert.equal(3, plaque.itemID)
		assert.equal(2, plaque.besoin)
		assert.equal(200, plaque.spell)
		assert.equal(2, plaque.fabrications)
		assert.equal(6, plaque.enfants[1].besoin) -- 6 barres
	end)

	it("multiplie par le nombre de fabrications demandées", function()
		local arbre = ArbreCraft.construire(donnees, creant, 400, 3)
		assert.same({ [1] = 36, [4] = 3 }, feuilles(arbre))
	end)

	it("arrondit les fabrications à l'entier supérieur et signale le surplus", function()
		-- 600 veut 3 lingots ; 500 en donne 2 par fabrication : 2 fabrications, 1 lingot en trop
		local arbre = ArbreCraft.construire(donnees, creant, 600, 1)
		local lingots = arbre.racine.enfants[1]
		assert.equal(2, lingots.fabrications)
		assert.equal(1, lingots.surplus)
		assert.same({ [1] = 2 }, feuilles(arbre))
	end)

	it("laisse en matière première un composant sans recette", function()
		local arbre = ArbreCraft.construire(donnees, creant, 100, 1)
		assert.equal(0, ArbreCraft.etages(arbre))
		assert.is_nil(arbre.racine.enfants[1].spell)
	end)

	it("ne boucle pas sur des recettes circulaires", function()
		local arbre = ArbreCraft.construire(donnees, creant, 800, 1)
		assert.is_table(arbre)
		local lignes = ArbreCraft.lignes(arbre)
		assert.is_true(#lignes <= 5)
	end)

	it("aplatit l'arbre dans l'ordre de lecture, racine d'abord", function()
		local lignes = ArbreCraft.lignes(ArbreCraft.construire(donnees, creant, 400, 1))
		assert.equal(400, lignes[1].spell)
		assert.equal(0, lignes[1].profondeur)
		assert.equal(3, lignes[2].itemID) -- plaque
		assert.equal(1, lignes[2].profondeur)
		assert.equal(2, lignes[3].itemID) -- barre
		assert.equal(2, lignes[3].profondeur)
		assert.equal(1, lignes[4].itemID) -- minerai
		assert.equal(3, lignes[4].profondeur)
		assert.equal(4, lignes[5].itemID) -- fil
	end)

	it("laisse l'appelant choisir entre plusieurs recettes", function()
		local variante = { recettes = {} }
		for k, v in pairs(donnees.recettes) do variante.recettes[k] = v end
		variante.recettes[101] = { objet = 2, qte = 1, composants = { { 4, 1 } } } -- autre barre, faite de fil
		local function creantV(itemID)
			local l = {}
			for spellID, r in pairs(variante.recettes) do if r.objet == itemID then l[#l + 1] = spellID end end
			table.sort(l)
			return l
		end
		local defaut = ArbreCraft.construire(variante, creantV, 200, 1)
		assert.same({ [1] = 6 }, feuilles(defaut)) -- 100, la plus petite
		local choisi = ArbreCraft.construire(variante, creantV, 200, 1, function(liste) return liste[#liste] end)
		assert.same({ [4] = 3 }, feuilles(choisi))
	end)

	it("renvoie nil pour une recette inconnue", function()
		assert.is_nil(ArbreCraft.construire(donnees, creant, 999, 1))
	end)
end)
