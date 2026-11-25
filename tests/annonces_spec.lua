-- Tests hors jeu du modèle des petites annonces (Core/Annonces.lua). busted tests
local ns = { Profil = { adler = function(s) return #s .. s:sub(1, 12) end } }
assert(loadfile("Core/Annonces.lua"))("Compagnons", ns)
local Annonces = ns.Annonces

local donnees = { recettes = { [2329] = { metier = 171 }, [3000] = { metier = 333 } }, objets = { [2449] = {} } }
local T0 = 1731180000
local JOUR = 24 * 3600

local function offre(extra)
	local o = { auteur = "Jean Vialjean", genre = "offre", spell = 2329, maintenant = T0 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return Annonces.nouvelle(o)
end

describe("Annonces", function()
	it("crée une offre sur une recette et une demande sur une recette ou un composant", function()
		assert.is_table(offre())
		assert.is_table(Annonces.nouvelle({ auteur = "A B", genre = "demande", item = 2449, maintenant = T0 }))
		assert.is_table(Annonces.nouvelle({ auteur = "A B", genre = "demande", spell = 2329, maintenant = T0 }))
	end)

	it("refuse une offre sur un simple objet, ou une cible absente ou double", function()
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", genre = "offre", item = 2449, maintenant = T0 }))
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", genre = "demande", maintenant = T0 }))
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", genre = "demande", note = "   ", maintenant = T0 }))
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", genre = "demande", spell = 2329, item = 2449, maintenant = T0 }))
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", genre = "troc", spell = 2329, maintenant = T0 }))
	end)

	it("accepte une annonce de texte seul, offre ou demande, à condition d'avoir une note", function()
		for _, genre in ipairs({ "offre", "demande" }) do
			local a = assert(Annonces.nouvelle({ auteur = "A B", genre = genre, note = "Je cherche une guilde de métiers", maintenant = T0 }))
			assert.is_nil(a.spell)
			assert.is_nil(a.item)
			local v = assert(Annonces.valider(a, donnees))
			assert.equal(a.hash, v.hash)
		end
		local a = Annonces.nouvelle({ auteur = "A B", genre = "offre", note = "Fiole", maintenant = T0 })
		assert.is_nil(Annonces.appliquer(a, "modifier", "A B", T0 + 1, { note = "  " }))
		assert.equal("Autre", assert(Annonces.appliquer(a, "modifier", "A B", T0 + 1, { note = "Autre" })).note)
		-- sans note, une annonce reçue est refusée
		local sans = {}
		for k, v in pairs(a) do sans[k] = v end
		sans.note = ""
		assert.is_nil(Annonces.valider(sans, donnees))
	end)

	it("une annonce de texte seul n'a pas de métier : le filtre par métier l'écarte", function()
		local t = Annonces.nouvelle({ auteur = "A B", genre = "offre", note = "Texte", maintenant = T0 })
		local liste = Annonces.liste({ [t.id] = t }, { genre = "offre", metier = 164, donnees = donnees }, T0)
		assert.equal(0, #liste)
		assert.equal(1, #Annonces.liste({ [t.id] = t }, { genre = "offre", donnees = donnees }, T0))
	end)

	it("tronque la note à 100 caractères", function()
		assert.equal(100, #offre({ note = string.rep("x", 300) }).note)
	end)

	it("seul l'auteur reconduit, modifie ou retire", function()
		local a = offre()
		assert.is_nil(Annonces.appliquer(a, "retirer", "Autre Membre", T0 + 1))
		local n = assert(Annonces.appliquer(a, "modifier", a.auteur, T0 + 5, { note = "Sacs", mats = "tout" }))
		assert.equal(1, n.rev)
		assert.equal("Sacs", n.note)
		assert.equal("tout", n.mats)
		local r = assert(Annonces.appliquer(n, "retirer", a.auteur, T0 + 9))
		assert.is_true(r.retire)
		assert.equal(2, r.rev)
		assert.is_nil(Annonces.appliquer(r, "reconduire", a.auteur, T0 + 10)) -- plus rien à faire sur une annonce retirée
		assert.is_nil(Annonces.appliquer(a, "inconnue", a.auteur, T0 + 1))
	end)

	it("la révision la plus haute gagne, puis la reconduction la plus récente", function()
		local a = offre()
		local b = assert(Annonces.appliquer(a, "reconduire", a.auteur, T0 + 100))
		assert.is_true(Annonces.meilleure(b, a))
		assert.is_false(Annonces.meilleure(a, b))
	end)

	it("expire 30 jours après la dernière reconduction, et oublie les retraits après 7 jours", function()
		local a = offre()
		assert.is_false(Annonces.perimee(a, T0 + 29 * JOUR))
		assert.is_true(Annonces.perimee(a, T0 + 31 * JOUR))
		local r = assert(Annonces.appliquer(a, "retirer", a.auteur, T0))
		assert.is_false(Annonces.perimee(r, T0 + 6 * JOUR))
		assert.is_true(Annonces.perimee(r, T0 + 8 * JOUR))
	end)

	it("valide une annonce reçue : id de l'auteur, cible connue, bornes", function()
		local a = offre()
		assert.is_table(Annonces.valider(a, donnees))
		local function avec(champ, valeur)
			local x = {}
			for k, v in pairs(a) do x[k] = v end
			x[champ] = valeur
			return Annonces.valider(x, donnees)
		end
		assert.is_nil(avec("spell", 123456))
		assert.is_nil(avec("id", "Autre Membre#1#1"))
		assert.is_nil(avec("genre", "x"))
		assert.is_nil(avec("rev", 1e9))
		assert.is_nil(avec("maj", "hier"))
	end)

	it("compte les annonces actives d'un auteur", function()
		local a, b = offre(), offre({ spell = 3000 })
		local retiree = assert(Annonces.appliquer(offre(), "retirer", "Jean Vialjean", T0))
		local table_ = { [a.id] = a, [b.id] = b, [retiree.id] = retiree }
		assert.equal(2, Annonces.nombreActives(table_, "Jean Vialjean", T0 + 1))
		assert.equal(0, Annonces.nombreActives(table_, "Autre Membre", T0 + 1))
		assert.equal(0, Annonces.nombreActives(table_, "Jean Vialjean", T0 + 40 * JOUR))
	end)

	it("liste un genre, les auteurs en ligne d'abord, avec filtre par métier", function()
		local a = offre()
		local b = offre({ auteur = "Elias Legentillet", spell = 3000, maintenant = T0 + 50 })
		local c = Annonces.nouvelle({ auteur = "Wilgar Rolpik", genre = "demande", spell = 2329, maintenant = T0 })
		local t = { [a.id] = a, [b.id] = b, [c.id] = c }
		local l = Annonces.liste(t, { genre = "offre" }, T0 + 60)
		assert.same({ b.id, a.id }, { l[1].id, l[2].id }) -- la plus récente d'abord
		l = Annonces.liste(t, { genre = "offre", estEnLigne = function(cle) return cle == "Jean Vialjean" end }, T0 + 60)
		assert.equal(a.id, l[1].id)
		assert.equal(1, #Annonces.liste(t, { genre = "offre", metier = 333, donnees = donnees }, T0 + 60))
		assert.equal(1, #Annonces.liste(t, { genre = "demande" }, T0 + 60))
	end)

	it("purge les annonces des auteurs qui ont quitté la guilde", function()
		local a, b = offre(), offre({ auteur = "Parti Loin" })
		local t = { [a.id] = a, [b.id] = b }
		assert.equal(1, Annonces.purgerAbsents(t, function(cle) return cle == "Jean Vialjean" end))
		assert.is_nil(t[b.id])
		assert.is_not_nil(t[a.id])
	end)
end)
