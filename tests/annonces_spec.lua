-- Tests hors jeu du modèle des petites annonces (Core/Annonces.lua). busted tests
local ns = { Profil = { adler = function(s) return #s .. s:sub(1, 12) end } }
assert(loadfile("Core/Annonces.lua"))("Compagnons", ns)
local Annonces = ns.Annonces

local T0 = 1731180000
local JOUR = 24 * 3600

local function annonce(extra)
	local o = { auteur = "Jean Vialjean", texte = "Cherche enchanteur", maintenant = T0 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return Annonces.nouvelle(o)
end

describe("Annonces", function()
	it("crée une annonce à partir d'un texte libre, et refuse un texte vide", function()
		assert.is_table(annonce())
		assert.is_nil(annonce({ texte = "" }))
		assert.is_nil(annonce({ texte = "   " }))
		assert.is_nil(Annonces.nouvelle({ auteur = "A B", maintenant = T0 }))
	end)

	it("tronque le texte à 200 caractères", function()
		assert.equal(200, #annonce({ texte = string.rep("x", 300) }).texte)
	end)

	it("seul l'auteur reconduit, modifie ou retire", function()
		local a = annonce()
		assert.is_nil(Annonces.appliquer(a, "retirer", "Autre Membre", T0 + 1))
		local n = assert(Annonces.appliquer(a, "modifier", a.auteur, T0 + 5, { texte = "Sacs" }))
		assert.equal(1, n.rev)
		assert.equal("Sacs", n.texte)
		assert.is_nil(Annonces.appliquer(a, "modifier", a.auteur, T0 + 5, { texte = " " })) -- texte vide refusé
		local r = assert(Annonces.appliquer(n, "retirer", a.auteur, T0 + 9))
		assert.is_true(r.retire)
		assert.equal(2, r.rev)
		assert.is_nil(Annonces.appliquer(r, "reconduire", a.auteur, T0 + 10)) -- plus rien à faire sur une annonce retirée
		assert.is_nil(Annonces.appliquer(a, "inconnue", a.auteur, T0 + 1))
	end)

	it("la révision la plus haute gagne, puis la reconduction la plus récente", function()
		local a = annonce()
		local b = assert(Annonces.appliquer(a, "reconduire", a.auteur, T0 + 100))
		assert.is_true(Annonces.meilleure(b, a))
		assert.is_false(Annonces.meilleure(a, b))
	end)

	it("expire 30 jours après la dernière reconduction, et oublie les retraits après 7 jours", function()
		local a = annonce()
		assert.is_false(Annonces.perimee(a, T0 + 29 * JOUR))
		assert.is_true(Annonces.perimee(a, T0 + 31 * JOUR))
		local r = assert(Annonces.appliquer(a, "retirer", a.auteur, T0))
		assert.is_false(Annonces.perimee(r, T0 + 6 * JOUR))
		assert.is_true(Annonces.perimee(r, T0 + 8 * JOUR))
	end)

	it("valide une annonce reçue : id de l'auteur, texte, bornes", function()
		local a = annonce()
		assert.is_table(Annonces.valider(a))
		local function avec(champ, valeur)
			local x = {}
			for k, v in pairs(a) do x[k] = v end
			x[champ] = valeur
			return Annonces.valider(x)
		end
		assert.is_nil(avec("texte", ""))
		assert.is_nil(avec("texte", 12))
		assert.is_nil(avec("id", "Autre Membre#1#1"))
		assert.is_nil(avec("rev", 1e9))
		assert.is_nil(avec("maj", "hier"))
	end)

	it("compte les annonces actives d'un auteur", function()
		local a, b = annonce(), annonce()
		local retiree = assert(Annonces.appliquer(annonce(), "retirer", "Jean Vialjean", T0))
		local table_ = { [a.id] = a, [b.id] = b, [retiree.id] = retiree }
		assert.equal(2, Annonces.nombreActives(table_, "Jean Vialjean", T0 + 1))
		assert.equal(0, Annonces.nombreActives(table_, "Autre Membre", T0 + 1))
		assert.equal(0, Annonces.nombreActives(table_, "Jean Vialjean", T0 + 40 * JOUR))
	end)

	it("liste les annonces actives, les auteurs en ligne d'abord, puis les plus récentes", function()
		local a = annonce()
		local b = annonce({ auteur = "Elias Legentillet", maintenant = T0 + 50 })
		local retiree = assert(Annonces.appliquer(annonce({ auteur = "Wilgar Rolpik" }), "retirer", "Wilgar Rolpik", T0))
		local t = { [a.id] = a, [b.id] = b, [retiree.id] = retiree }
		local l = Annonces.liste(t, {}, T0 + 60)
		assert.same({ b.id, a.id }, { l[1].id, l[2].id }) -- la plus récente d'abord, la retirée absente
		assert.equal(2, #l)
		l = Annonces.liste(t, { estEnLigne = function(cle) return cle == "Jean Vialjean" end }, T0 + 60)
		assert.equal(a.id, l[1].id)
	end)

	it("purge les annonces des auteurs qui ont quitté la guilde", function()
		local a, b = annonce(), annonce({ auteur = "Parti Loin" })
		local t = { [a.id] = a, [b.id] = b }
		assert.equal(1, Annonces.purgerAbsents(t, function(cle) return cle == "Jean Vialjean" end))
		assert.is_nil(t[b.id])
		assert.is_not_nil(t[a.id])
	end)
end)
