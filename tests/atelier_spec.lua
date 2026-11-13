-- Tests hors jeu de la logique des commandes côté utilisateur (Modules/Atelier.lua), avec une API minimale simulée. busted tests
local function charger(courant, personnages)
	local ns = {}
	ns.L = setmetatable({}, { __index = function(_, cle) return cle end })
	local messages = {}
	ns.addon = {
		NewModule = function() return { RegisterMessage = function() end } end,
		SendMessage = function(_, nom) messages[#messages + 1] = nom end,
		Print = function() end,
	}
	ns.log = function() end
	ns.clePersonnage = function() return courant end
	ns.db = { global = { personnages = personnages, commandes = {}, guilde = {} } }

	for _, fichier in ipairs({ "Core/Bitset.lua", "Core/Catalogue.lua", "Core/Profil.lua", "Core/Commandes.lua", "Core/Synchro.lua" }) do
		assert(loadfile(fichier))("Compagnons", ns)
	end

	ns.Recettes = {
		metiers = { [171] = { nom = "Alchimie", ordre = { 2329, 2331 } } },
		objets = {},
		recettes = {
			[2329] = { metier = 171, indice = 1, niveau = 1, nom = "Élixir", objet = 1, qte = 1, qualite = 1, composants = {} },
			[2331] = { metier = 171, indice = 2, niveau = 1, nom = "Potion", objet = 2, qte = 1, qualite = 1, composants = {} },
		},
	}
	ns.catalogue = ns.Catalogue.nouveau(ns.Recettes, personnages, {})
	ns.Reseau = {
		moteur = ns.Synchro.nouveau({
			donnees = ns.Recettes, profils = ns.db.global.guilde, commandes = ns.db.global.commandes,
			moi = function() return courant end,
			envoyer = function() end, maintenant = function() return 1000 end, planifier = function() end,
		}),
	}
	assert(loadfile("Modules/Atelier.lua"))("Compagnons", ns)
	return ns, ns.Atelier, messages
end

local function jeu(courant)
	return {
		["Jean Vialjean"] = { nom = "Jean Vialjean", classe = "SHAMAN",
			metiers = { [171] = { id = 171, nom = "Alchimie", niveau = 50, recettes = { 2329 } } } },
		["Brumefer Hautrocher"] = { nom = "Brumefer Hautrocher", classe = "WARRIOR",
			metiers = { [171] = { id = 171, nom = "Alchimie", niveau = 10, recettes = { 2331 } } } },
	}, courant
end

rawset(_G, "time", os.time)

describe("Atelier", function()
	local ns, atelier

	before_each(function()
		local persos = jeu()
		ns, atelier = charger("Jean Vialjean", persos)
	end)

	local function commandeDe(client, spell, options)
		options = options or {}
		options.client, options.spell, options.qte, options.maintenant = client, spell, options.qte or 1, 1000
		local c = ns.Commandes.nouvelle(options)
		ns.db.global.commandes[c.id] = c
		return c
	end

	it("une commande d'un autre pour une recette que je connais est « pour moi »", function()
		commandeDe("Wilgar Rolpik", 2329)
		commandeDe("Wilgar Rolpik", 2331)
		assert.are.equal(2, #atelier:Vue("ouvertes"))
		assert.are.equal(2, #atelier:Vue("pourmoi")) -- Jean connaît 2329, Brumefer (mon autre perso) connaît 2331
		assert.are.equal(2, atelier:CompterPourMoi())
	end)

	it("mes propres commandes ne sont pas « pour moi » mais dans « mes commandes »", function()
		commandeDe("Jean Vialjean", 2329)
		assert.are.equal(0, #atelier:Vue("pourmoi"))
		assert.are.equal(1, #atelier:Vue("mes"))
		assert.are.equal(1, #atelier:Vue("ouvertes"))
	end)

	it("une commande réservée à un autre crafteur n'est pas pour moi", function()
		commandeDe("Wilgar Rolpik", 2329, { crafteur = "Elias Legentillet" })
		assert.are.equal(0, #atelier:Vue("pourmoi"))
		commandeDe("Wilgar Rolpik", 2329, { crafteur = "Jean Vialjean" })
		assert.are.equal(1, #atelier:Vue("pourmoi"))
	end)

	it("propose « Je prends », puis le cycle jusqu'à livré", function()
		local c = commandeDe("Wilgar Rolpik", 2329)
		local actions = atelier:ActionsPossibles(c)
		assert.are.equal(1, #actions)
		assert.are.equal("prendre", actions[1].action)
		assert.is_nil(actions[1].raison)

		local prise = assert(atelier:Agir(c, "prendre"))
		assert.are.equal("prise", prise.statut)
		assert.are.equal("Jean Vialjean", prise.assigne)

		local suite = {}
		for _, a in ipairs(atelier:ActionsPossibles(prise)) do suite[a.action] = true end
		assert.is_true(suite.mats and suite.livrer and suite.liberer)
		assert.is_nil(suite.annuler) -- je ne suis pas le client

		local mats = assert(atelier:Agir(prise, "mats"))
		local fini = assert(atelier:Agir(mats, "livrer"))
		assert.are.equal("livree", fini.statut) -- le client doit encore confirmer
		assert.are.equal(0, #atelier:ActionsPossibles(fini))
	end)

	it("signale qu'il faut changer de personnage pour prendre avec un autre de mes personnages", function()
		local c = commandeDe("Wilgar Rolpik", 2331) -- seul Brumefer la connaît
		local actions = atelier:ActionsPossibles(c)
		assert.are.equal("prendre", actions[1].action)
		assert.is_not_nil(actions[1].raison)
		local ok, message = atelier:Agir(c, "prendre")
		assert.is_nil(ok)
		assert.is_not_nil(message)
		assert.are.equal("ouverte", ns.db.global.commandes[c.id].statut)
	end)

	it("le client peut annuler, pas les autres", function()
		local c = commandeDe("Jean Vialjean", 2329)
		local actions = atelier:ActionsPossibles(c)
		assert.are.equal("annuler", actions[#actions].action)
		local annulee = assert(atelier:Agir(c, "annuler"))
		assert.are.equal("annulee", annulee.statut)

		local autre = commandeDe("Wilgar Rolpik", 2329)
		assert.is_nil((atelier:Agir(autre, "annuler")))
	end)

	it("ne propose pas de prendre ses propres commandes", function()
		local c = commandeDe("Jean Vialjean", 2329)
		for _, a in ipairs(atelier:ActionsPossibles(c)) do assert.are_not.equal("prendre", a.action) end
	end)

	it("regroupe les commandes d'un métier pour le panneau, y compris celles que j'ai prises", function()
		local a = commandeDe("Wilgar Rolpik", 2329)
		local b = commandeDe("Elias Legentillet", 2329)
		atelier:Agir(b, "prendre")
		local liste = atelier:PourMetier(171)
		assert.are.equal(2, #liste)
		assert.are.equal(0, #atelier:PourMetier(999))
		assert.is_not_nil(a)
	end)

	describe("réception d'une commande livrée (je suis le client)", function()
		local function livree(extra)
			local c = commandeDe("Jean Vialjean", 2329, extra)
			ns.db.global.commandes[c.id] = ns.Commandes.appliquer(
				ns.Commandes.appliquer(c, "prendre", "Wilgar Rolpik", 1001), "livrer", "Wilgar Rolpik", 1002)
			return ns.db.global.commandes[c.id]
		end

		it("propose « Bien reçu » et « Pas reçu » au client, mais seulement une fois livrée", function()
			local c = commandeDe("Jean Vialjean", 2329)
			for _, a in ipairs(atelier:ActionsPossibles(c)) do assert.are_not.equal("confirmer", a.action) end
			local l = livree()
			assert.are.equal("livree", l.statut)
			local actions = {}
			for _, a in ipairs(atelier:ActionsPossibles(l)) do actions[a.action] = a end
			assert.is_true(actions.confirmer.principale)
			assert.is_not_nil(actions.contester)
			assert.is_not_nil(actions.annuler)
		end)

		it("le client confirme : la commande est terminée", function()
			local l = livree()
			local fini = assert(atelier:Agir(l, "confirmer"))
			assert.are.equal("terminee", fini.statut)
			assert.are.equal("Jean Vialjean", fini.par)
			assert.are.equal("Wilgar Rolpik", fini.assigne)
		end)

		it("le client conteste : la commande revient au même crafteur", function()
			local rendue = assert(atelier:Agir(livree(), "contester"))
			assert.are.equal("prise", rendue.statut)
			assert.are.equal("Wilgar Rolpik", rendue.assigne)
		end)

		it("compte mes commandes à confirmer, pas celles des autres", function()
			assert.are.equal(0, atelier:CompterAConfirmer())
			livree()
			assert.are.equal(1, atelier:CompterAConfirmer())
			local autre = commandeDe("Elias Legentillet", 2329)
			ns.db.global.commandes[autre.id] = ns.Commandes.appliquer(
				ns.Commandes.appliquer(autre, "prendre", "Wilgar Rolpik", 1001), "livrer", "Wilgar Rolpik", 1002)
			assert.are.equal(1, atelier:CompterAConfirmer())
		end)

		it("le crafteur n'a pas de bouton pour confirmer à la place du client", function()
			local c = commandeDe("Wilgar Rolpik", 2329)
			local prise = assert(atelier:Agir(c, "prendre"))
			local l = assert(atelier:Agir(prise, "livrer"))
			assert.are.equal("livree", l.statut)
			for _, a in ipairs(atelier:ActionsPossibles(l)) do
				assert.are_not.equal("confirmer", a.action)
				assert.are_not.equal("contester", a.action)
			end
		end)
	end)

	it("formate l'âge d'une commande", function()
		local maintenant = os.time()
		assert.are.equal("AGE_INSTANT", atelier.Age(maintenant))
		assert.are.equal("AGE_MINUTES", atelier.Age(maintenant - 300)) -- sans traduction, la clé est renvoyée telle quelle
	end)
end)
