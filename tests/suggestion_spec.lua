-- Tests hors jeu de la suggestion de crafteur (Core/Suggestion.lua). busted tests
local ns = {}
assert(loadfile("Core/Suggestion.lua"))("Compagnons", ns)
local Suggestion = ns.Suggestion

local function c(cle, niveau) return { cle = cle, nom = cle, niveau = niveau } end
local function en(...)
	local ensemble = {}
	for _, cle in ipairs({ ... }) do ensemble[cle] = true end
	return function(cle) return ensemble[cle] == true end
end

describe("Suggestion.classer", function()
	it("met les personnages en ligne devant les autres", function()
		local l = Suggestion.classer({ c("Alice Durand", 300), c("Bastien Roux", 100) }, en("Bastien Roux"), {})
		assert.are.equal("Bastien Roux", l[1].cle)
		assert.is_true(l[1].enLigne)
		assert.is_false(l[2].enLigne)
	end)

	it("à présence égale, préfère le moins chargé", function()
		local charges = { ["Alice Durand"] = 3, ["Bastien Roux"] = 1 }
		local l = Suggestion.classer({ c("Alice Durand", 300), c("Bastien Roux", 100) }, en("Alice Durand", "Bastien Roux"), charges)
		assert.are.equal("Bastien Roux", l[1].cle)
		assert.are.equal(1, l[1].enCours)
		assert.are.equal(3, l[2].enCours)
	end)

	it("à charge égale, préfère le niveau de métier le plus élevé", function()
		local l = Suggestion.classer({ c("Alice Durand", 100), c("Bastien Roux", 285) }, en("Alice Durand", "Bastien Roux"), {})
		assert.are.equal("Bastien Roux", l[1].cle)
	end)

	it("départage le reste par l'ordre alphabétique : un ordre total", function()
		local l = Suggestion.classer({ c("Camille Petit", 100), c("Alice Durand", 100), c("Bastien Roux", 100) }, en(), {})
		assert.are.same({ "Alice Durand", "Bastien Roux", "Camille Petit" }, { l[1].cle, l[2].cle, l[3].cle })
	end)

	it("la présence l'emporte sur la charge, la charge sur le niveau", function()
		local charges = { ["Alice Durand"] = 0, ["Bastien Roux"] = 5 }
		-- Bastien est en ligne : il passe devant Alice, même chargé et de niveau inférieur
		local l = Suggestion.classer({ c("Alice Durand", 300), c("Bastien Roux", 10) }, en("Bastien Roux"), charges)
		assert.are.equal("Bastien Roux", l[1].cle)
	end)

	it("écarte mes propres personnages", function()
		local l = Suggestion.classer({ c("Jean Vialjean", 300), c("Bastien Roux", 100) }, en("Jean Vialjean"), {}, { ["Jean Vialjean"] = true })
		assert.are.equal(1, #l)
		assert.are.equal("Bastien Roux", l[1].cle)
	end)

	it("ne modifie pas la liste d'origine et gère l'absence de candidats", function()
		local origine = { c("Bastien Roux", 1), c("Alice Durand", 2) }
		Suggestion.classer(origine, en(), {})
		assert.are.equal("Bastien Roux", origine[1].cle)
		assert.are.equal(0, #Suggestion.classer({}, en(), {}))
		assert.are.equal(0, #Suggestion.classer(nil, nil, nil))
		assert.is_nil(Suggestion.meilleur({}, en(), {}))
	end)

	it("supporte une fonction de présence absente et des niveaux manquants", function()
		local l = Suggestion.classer({ { cle = "Zed Zorro" }, { cle = "Alice Durand", niveau = 5 } }, nil, nil)
		assert.are.equal("Alice Durand", l[1].cle)
		assert.are.equal(0, l[2].niveau)
	end)
end)

describe("Suggestion.charges", function()
	it("compte les commandes prises et à matériaux reçus par crafteur, pas les autres", function()
		local cmds = {
			{ assigne = "Alice Durand", statut = "prise" },
			{ assigne = "Alice Durand", statut = "mats" },
			{ assigne = "Alice Durand", statut = "livree" },
			{ assigne = "Alice Durand", statut = "terminee" },
			{ assigne = "Bastien Roux", statut = "prise" },
			{ statut = "ouverte" },
		}
		local ch = Suggestion.charges(cmds)
		assert.are.equal(2, ch["Alice Durand"])
		assert.are.equal(1, ch["Bastien Roux"])
		assert.is_nil(ch["Camille Petit"])
	end)
end)
