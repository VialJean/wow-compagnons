-- Tests hors jeu de la répartition des fabrications (Core/Progres.lua) et du module Fabrication (API de jeu simulée). busted tests
local function charger(fichiers)
	local ns = {}
	for _, f in ipairs(fichiers) do assert(loadfile(f))("Compagnons", ns) end
	return ns
end

local ns0 = charger({ "Core/Profil.lua", "Core/Commandes.lua", "Core/Progres.lua" })
local Progres = ns0.Progres

local function commande(id, cree, extra)
	local o = { id = id, spell = 2963, qte = 5, statut = "prise", assigne = "Jean Vialjean", cree = cree }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

describe("Progres.repartir", function()
	it("rattache les fabrications à la commande la plus ancienne d'abord", function()
		local commandes = { a = commande("a", 100, { qte = 3 }), b = commande("b", 50, { qte = 3 }) }
		local parts, reste = Progres.repartir(commandes, "Jean Vialjean", 2963, 4)
		assert.are.equal(3, parts.b) -- la plus ancienne se remplit d'abord
		assert.are.equal(1, parts.a)
		assert.are.equal(0, reste)
	end)

	it("ne dépasse pas ce qu'il reste à fabriquer, et signale le surplus", function()
		local commandes = { a = commande("a", 1, { qte = 2, progres = { craftes = 1 } }) }
		local parts, reste = Progres.repartir(commandes, "Jean Vialjean", 2963, 4)
		assert.are.equal(1, parts.a)
		assert.are.equal(3, reste)
	end)

	it("compte ce qui est déjà en attente d'enregistrement", function()
		local commandes = { a = commande("a", 1, { qte = 3 }) }
		local parts = Progres.repartir(commandes, "Jean Vialjean", 2963, 5, { a = 2 })
		assert.are.equal(1, parts.a)
	end)

	it("ignore les commandes des autres crafteurs, d'une autre recette, ouvertes ou finales", function()
		local commandes = {
			a = commande("a", 1, { assigne = "Brumefer Hautrocher" }),
			b = commande("b", 2, { spell = 9999 }),
			c = commande("c", 3, { statut = "ouverte", assigne = nil }),
			d = commande("d", 4, { statut = "terminee" }),
			e = commande("e", 5, { statut = "mats" }),
		}
		local parts = Progres.repartir(commandes, "Jean Vialjean", 2963, 2)
		assert.is_nil(parts.a)
		assert.is_nil(parts.b)
		assert.is_nil(parts.c)
		assert.is_nil(parts.d)
		assert.are.equal(2, parts.e)
	end)

	it("compte un lancer par exemplaire créé, un seul pour un enchantement", function()
		assert.are.equal(1, Progres.parLancer({ qte = 1 }))
		assert.are.equal(2, Progres.parLancer({ qte = 2 }))
		assert.are.equal(1, Progres.parLancer({ qte = 0 }))
		assert.are.equal(1, Progres.parLancer({}))
	end)

	it("écrit le libellé « 3/5 craftés » seulement pour une commande en cours avec des fabrications", function()
		local modele = "%d/%d craftés"
		assert.are.equal("3/5 craftés", Progres.libelle(commande("a", 1, { progres = { craftes = 3 } }), modele))
		assert.is_nil(Progres.libelle(commande("a", 1), modele))
		assert.is_nil(Progres.libelle(commande("a", 1, { statut = "ouverte", progres = { craftes = 3 } }), modele))
		assert.is_nil(Progres.libelle(commande("a", 1, { statut = "terminee", progres = { craftes = 5 } }), modele))
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- Module Fabrication
-- ---------------------------------------------------------------------------------------------

local function monter()
	local ns = charger({ "Core/Profil.lua", "Core/Commandes.lua", "Core/Progres.lua" })
	local module = {}
	function module:RegisterEvent() end
	local messages = {}
	ns.addon = { NewModule = function() return module end, SendMessage = function(_, nom) messages[#messages + 1] = nom end }
	ns.clePersonnage = function() return "Jean Vialjean" end
	ns.Recettes = { recettes = { [2963] = { qte = 1 }, [2964] = { qte = 2 } } }
	ns.db = { global = { commandes = {} }, profile = { livraison = { suivi = true } } }

	local temps, taches = 0, {}
	rawset(_G, "GetTime", function() return temps end)
	rawset(_G, "C_Timer", { After = function(delai, fn) taches[#taches + 1] = { t = temps + delai, fn = fn } end })

	local envois = {}
	ns.Reseau = { moteur = { AgirCommande = function(_, id, action, par, extra)
		envois[#envois + 1] = { id = id, action = action, par = par, craftes = extra.craftes }
		local o = ns.db.global.commandes[id]
		local n = {}
		for k, v in pairs(o) do n[k] = v end
		n.progres = { craftes = extra.craftes }
		ns.db.global.commandes[id] = n
		return n
	end } }

	assert(loadfile("Modules/Fabrication.lua"))("Compagnons", ns)
	module:OnEnable()

	local function avancer(secondes)
		temps = temps + secondes
		local restantes = {}
		for _, t in ipairs(taches) do
			if t.t <= temps then t.fn() else restantes[#restantes + 1] = t end
		end
		taches = restantes
	end
	return ns, module, envois, messages, avancer
end

local function ajouter(ns, id, cree, extra)
	ns.db.global.commandes[id] = commande(id, cree, extra)
end

describe("Fabrication", function()
	it("enregistre la progression une fois la série terminée, pas à chaque fabrication", function()
		local ns, module, envois, messages, avancer = monter()
		ajouter(ns, "a", 1)
		for i = 1, 4 do module:SurSort("UNIT_SPELLCAST_SUCCEEDED", "player", "cast" .. i, 2963) end
		assert.are.equal(0, #envois)       -- rien n'est envoyé pendant la série
		avancer(4)
		assert.are.equal(0, #envois)
		avancer(2)                         -- 5 s sans fabrication : on enregistre
		assert.are.equal(1, #envois)
		assert.are.equal(4, envois[1].craftes)
		assert.are.equal("progres", envois[1].action)
		assert.are.equal("Jean Vialjean", envois[1].par)
		assert.are.equal("COMPAGNONS_COMMANDES_MAJ", messages[1])
	end)

	it("ne compte pas deux fois le même lancer", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1)
		module:SurSort("x", "player", "cast1", 2963)
		module:SurSort("x", "player", "cast1", 2963)
		avancer(6)
		assert.are.equal(1, envois[1].craftes)
	end)

	it("ignore les lancers des autres, d'un sort qui n'est pas une recette, et le suivi coupé", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1)
		module:SurSort("x", "target", "c1", 2963)
		module:SurSort("x", "player", "c2", 12345)
		ns.db.profile.livraison.suivi = false
		module:SurSort("x", "player", "c3", 2963)
		avancer(10)
		assert.are.equal(0, #envois)
	end)

	it("ignore une fabrication qui ne correspond à aucune commande que j'ai prise", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1, { assigne = "Brumefer Hautrocher" })
		module:SurSort("x", "player", "c1", 2963)
		avancer(10)
		assert.are.equal(0, #envois)
	end)

	it("plafonne à la quantité commandée et passe aux commandes suivantes", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1, { qte = 2 })
		ajouter(ns, "b", 2, { qte = 2 })
		for i = 1, 5 do module:SurSort("x", "player", "c" .. i, 2963) end
		avancer(6)
		local parId = {}
		for _, e in ipairs(envois) do parId[e.id] = e.craftes end
		assert.are.equal(2, parId.a)
		assert.are.equal(2, parId.b) -- la cinquième fabrication n'a plus de commande à remplir
	end)

	it("compte plusieurs exemplaires par lancer, sans dépasser la commande", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1, { spell = 2964, qte = 5 })
		for i = 1, 3 do module:SurSort("x", "player", "c" .. i, 2964) end -- 2 + 2 + 1
		avancer(6)
		assert.are.equal(5, envois[1].craftes)
	end)

	it("enregistre par tranches pendant une très longue série", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1, { qte = 100 })
		for i = 1, 40 do
			module:SurSort("x", "player", "c" .. i, 2963)
			avancer(1) -- une fabrication par seconde : le silence de 5 s n'arrive jamais
		end
		assert.is_true(#envois >= 1) -- au bout de 30 s, une tranche est enregistrée
		avancer(6)
		assert.are.equal(40, envois[#envois].craftes)
	end)

	it("reprend là où la commande en était", function()
		local ns, module, envois, _, avancer = monter()
		ajouter(ns, "a", 1, { qte = 5, progres = { craftes = 2 } })
		module:SurSort("x", "player", "c1", 2963)
		avancer(6)
		assert.are.equal(3, envois[1].craftes)
	end)
end)
