-- Tests hors jeu des noms par langue (Core/Noms.lua) et cohérence des données générées. busted tests
local function charger(fichiers)
	local ns = {}
	for _, f in ipairs(fichiers) do assert(loadfile(f))("Compagnons", ns) end
	return ns
end

local function base()
	return {
		metiers = { [171] = { ordre = { 1 } }, [185] = { ordre = { 2 } } },
		objets = { [10] = { "", 1 }, [11] = { "", 2 } },
		recettes = { [1] = { metier = 171, objet = 10 }, [2] = { metier = 185, objet = 11 } },
	}
end

local tables = {
	enUS = { metiers = { [171] = "Alchemy", [185] = "Cooking" }, recettes = { [1] = "Elixir", [2] = "Stew" },
		objets = { [10] = "Vial", [11] = "Meat" } },
	frFR = { metiers = { [171] = "Alchimie" }, recettes = { [1] = "Élixir" }, objets = { [10] = "Fiole" } },
}

describe("Noms.appliquer", function()
	local ns = charger({ "Core/Noms.lua" })

	it("applique les noms de la langue du client", function()
		local d = base()
		assert.is_true(ns.Noms.appliquer(d, tables, "frFR"))
		assert.are.equal("Alchimie", d.metiers[171].nom)
		assert.are.equal("Élixir", d.recettes[1].nom)
		assert.are.equal("Fiole", d.objets[10][1])
	end)

	it("garde la qualité et le reste de la structure", function()
		local d = base()
		ns.Noms.appliquer(d, tables, "frFR")
		assert.are.equal(1, d.objets[10][2])
		assert.are.equal(171, d.recettes[1].metier)
		assert.are.same({ 1 }, d.metiers[171].ordre)
	end)

	it("retombe sur l'anglais, nom par nom, quand une traduction manque", function()
		local d = base()
		ns.Noms.appliquer(d, tables, "frFR")
		assert.are.equal("Cooking", d.metiers[185].nom) -- pas traduit en français
		assert.are.equal("Stew", d.recettes[2].nom)
		assert.are.equal("Meat", d.objets[11][1])
	end)

	it("utilise l'anglais pour une langue sans fichier de noms", function()
		local d = base()
		assert.is_true(ns.Noms.appliquer(d, tables, "deDE"))
		assert.are.equal("Alchemy", d.metiers[171].nom)
		assert.are.equal("Elixir", d.recettes[1].nom)
	end)

	it("met l'identifiant à la place d'un nom introuvable, sans champ vide", function()
		local d = base()
		assert.is_false(ns.Noms.appliquer(d, {}, "frFR"))
		assert.are.equal("#171", d.metiers[171].nom)
		assert.are.equal("#1", d.recettes[1].nom)
		assert.are.equal("", d.objets[10][1]) -- l'interface affiche alors « #identifiant »
	end)

	it("accepte une langue de repli différente", function()
		local d = base()
		ns.Noms.appliquer(d, tables, "deDE", "frFR")
		assert.are.equal("Alchimie", d.metiers[171].nom)
		assert.are.equal("#185", d.metiers[185].nom)
	end)
end)

describe("Données générées (Data/)", function()
	-- Les fichiers de noms se sautent seuls si le client n'est pas dans leur langue : on simule frFR.
	local function chargerDonnees(langue)
		rawset(_G, "GetLocale", function() return langue end)
		local ns = charger({ "Core/Noms.lua", "Data/Recettes.lua", "Data/Noms.enUS.lua", "Data/Noms.frFR.lua" })
		rawset(_G, "GetLocale", nil)
		return ns
	end

	it("charge la langue de repli et celle du client seulement", function()
		local fr = chargerDonnees("frFR")
		assert.is_not_nil(fr.NomsDonnees.enUS)
		assert.is_not_nil(fr.NomsDonnees.frFR)
		local de = chargerDonnees("deDE")
		assert.is_not_nil(de.NomsDonnees.enUS)
		assert.is_nil(de.NomsDonnees.frFR)
	end)

	it("Recettes.lua ne contient aucun nom avant l'application", function()
		local ns = chargerDonnees("frFR")
		for _, r in pairs(ns.Recettes.recettes) do assert.is_nil(r.nom) end
		for _, m in pairs(ns.Recettes.metiers) do assert.is_nil(m.nom) end
	end)

	it("chaque recette et chaque métier a un nom dans les deux langues livrées", function()
		for _, langue in ipairs({ "enUS", "frFR" }) do
			local ns = chargerDonnees("frFR")
			local t = ns.NomsDonnees[langue]
			for spellID in pairs(ns.Recettes.recettes) do assert.is_not_nil(t.recettes[spellID]) end
			for id in pairs(ns.Recettes.metiers) do assert.is_not_nil(t.metiers[id]) end
		end
	end)

	it("applique le français puis l'anglais au chargement", function()
		local fr = chargerDonnees("frFR")
		fr.Noms.appliquer(fr.Recettes, fr.NomsDonnees, "frFR")
		assert.are.equal("Alchimie", fr.Recettes.metiers[171].nom)
		assert.are.equal("Élixir de Force mineure", fr.Recettes.recettes[2329].nom)

		local en = chargerDonnees("enUS")
		en.Noms.appliquer(en.Recettes, en.NomsDonnees, "enUS")
		assert.are.equal("Alchemy", en.Recettes.metiers[171].nom)
		assert.are.equal("Elixir of Minor Strength", en.Recettes.recettes[2329].nom)
	end)

	it("la grande majorité des composants a un nom", function()
		local ns = chargerDonnees("enUS")
		ns.Noms.appliquer(ns.Recettes, ns.NomsDonnees, "enUS")
		local total, nommes = 0, 0
		for _, o in pairs(ns.Recettes.objets) do
			total = total + 1
			if o[1] ~= "" then nommes = nommes + 1 end
		end
		assert.is_true(nommes / total > 0.9)
	end)
end)
