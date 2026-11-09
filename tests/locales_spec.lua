-- Cohérence des textes de l'interface : mêmes clés, mêmes %s / %d, aucune clé manquante ou inutilisée. busted tests
local function charger(fichiers, langue)
	local ns = {}
	rawset(_G, "GetLocale", function() return langue end)
	for _, f in ipairs(fichiers) do assert(loadfile(f))("Compagnons", ns) end
	rawset(_G, "GetLocale", nil)
	return ns
end

local FICHIERS = { "Locales/enUS.lua", "Locales/frFR.lua", "Core/Locales.lua" }
local LANGUES = { "frFR" } -- à compléter quand on ajoute une langue (avec son fichier)

--- Suite des spécificateurs de format d'une chaîne : "%d × %s" -> "d s".
local function formats(texte)
	local suite = {}
	for spec in texte:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([sdxXfgqc])") do suite[#suite + 1] = spec end
	return table.concat(suite, " ")
end

local function lire(chemin)
	local f = assert(io.open(chemin, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

--- Fichiers de code de l'addon, lus dans le .toc (portable, et toujours à jour).
local function fichiersSource()
	local liste = {}
	for ligne in lire("Compagnons.toc"):gmatch("[^\r\n]+") do
		local chemin = ligne:gsub("\\", "/")
		if chemin:match("%.lua$") and not chemin:match("^#") and not chemin:match("^Data/") and not chemin:match("^Locales/") then
			liste[#liste + 1] = chemin
		end
	end
	assert(#liste > 10, "le .toc ne liste pas les fichiers attendus")
	return liste
end

describe("Textes de l'interface", function()
	local ns = charger(FICHIERS, "enUS")
	local anglais = ns.Textes.enUS

	it("l'anglais est complet et sans chaîne vide", function()
		local n = 0
		for cle, texte in pairs(anglais) do
			n = n + 1
			assert.is_true(type(texte) == "string" and texte ~= "")
			assert.is_true(cle:match("^[A-Z][A-Z0-9_]*$") ~= nil)
		end
		assert.is_true(n > 100)
	end)

	for _, langue in ipairs(LANGUES) do
		describe(langue, function()
			local traduction = ns.Textes[langue]

			it("a exactement les mêmes clés que l'anglais", function()
				for cle in pairs(anglais) do assert.is_not_nil(traduction[cle], "clé absente en " .. langue .. " : " .. cle) end
				for cle in pairs(traduction) do assert.is_not_nil(anglais[cle], "clé inconnue de l'anglais : " .. cle) end
			end)

			it("garde les mêmes %s et %d, dans le même ordre", function()
				for cle, texte in pairs(anglais) do
					assert.are.equal(formats(texte), formats(traduction[cle]), "formats différents pour " .. cle)
				end
			end)

			it("n'a aucune chaîne vide", function()
				for cle, texte in pairs(traduction) do assert.is_true(texte ~= "", "chaîne vide : " .. cle) end
			end)
		end)
	end

	it("toute clé utilisée dans le code existe en anglais", function()
		local inconnues = {}
		for _, chemin in ipairs(fichiersSource()) do
			if chemin ~= "Core/Locales.lua" then
				for cle in lire(chemin):gmatch("%f[%w_]L%.([A-Z][A-Z0-9_]*)") do
					if anglais[cle] == nil then inconnues[#inconnues + 1] = chemin .. " : L." .. cle end
				end
			end
		end
		assert.are.same({}, inconnues)
	end)

	it("aucune clé d'anglais n'est inutilisée", function()
		local code = {}
		for _, chemin in ipairs(fichiersSource()) do code[#code + 1] = lire(chemin) end
		code = table.concat(code, "\n")
		local inutiles = {}
		for cle in pairs(anglais) do
			if not code:find("L." .. cle, 1, true) then inutiles[#inutiles + 1] = cle end
		end
		table.sort(inutiles)
		assert.are.same({}, inutiles)
	end)

	it("le sélecteur utilise la langue du client, avec repli sur l'anglais", function()
		local fr = charger(FICHIERS, "frFR")
		assert.are.equal("Commander", fr.L.COMMANDER)
		assert.are.equal("frFR", fr.langue)

		local en = charger(FICHIERS, "enUS")
		assert.are.equal("Order", en.L.COMMANDER)

		-- langue sans traduction : tout en anglais
		local de = charger(FICHIERS, "deDE")
		assert.are.equal("Order", de.L.COMMANDER)

		-- une clé retirée d'une traduction retombe sur l'anglais, pas sur la clé
		local avec = charger(FICHIERS, "enUS")
		avec.Textes.frFR.COMMANDER = nil
		avec.chargerTextes(avec.Textes, "frFR")
		assert.are.equal("Order", avec.L.COMMANDER)
	end)

	it("une clé inconnue renvoie la clé elle-même", function()
		assert.are.equal("CLE_INEXISTANTE", ns.L.CLE_INEXISTANTE)
	end)
end)
