-- Tests hors jeu du module Observateur avec une API de jeu simulée (Modules/Observateur.lua). busted tests
local function monter(options)
	options = options or {}
	local ns = {}
	ns.L = setmetatable({}, { __index = function(_, cle) return cle end })
	local inconnus = options.inconnus or {}
	local enregistres = {}
	local module = {}
	function module:RegisterEvent(evenement)
		if inconnus[evenement] then error("événement inconnu") end
		enregistres[evenement] = true
	end
	function module:UnregisterAllEvents() for k in pairs(enregistres) do enregistres[k] = nil end end
	ns.addon = { NewModule = function() return module end, Print = function() end }
	ns.db = { global = { observation = {} }, profile = { observer = false } }
	ns.Recettes = { recettes = { [2329] = { nom = "Élixir" } } }

	rawset(_G, "time", function() return 1000 end)
	rawset(_G, "date", os.date)
	rawset(_G, "GetBuildInfo", function() return "1.60.1", "70862" end)
	rawset(_G, "UnitName", function() return "Orvanne" end)
	rawset(_G, "GetPlayerTradeMoney", function() return 0 end)
	rawset(_G, "GetTargetTradeMoney", function() return 0 end)
	rawset(_G, "GetTradePlayerItemInfo", function(i)
		if i == 1 then return "Terrestrine", 1, 10 end
	end)
	rawset(_G, "GetTradeTargetItemInfo", function(i)
		if i == 1 then return "Fiole vide", 2, 5 end
	end)
	rawset(_G, "GetInboxNumItems", function() return 1 end)
	rawset(_G, "GetInboxHeaderInfo", function() return 1, 2, "Brumefer", "Commande", 0, 0, 30, true end)
	rawset(_G, "GetInboxItem", function(_, j) if j == 1 then return "Potion", 118, 3, 5 end end)
	rawset(_G, "GetSendMailItem", function(i) if i == 1 then return "Élixir", 2454, 4, 3 end end)
	rawset(_G, "GetSendMailMoney", function() return 0 end)

	assert(loadfile("Core/Observation.lua"))("Compagnons", ns)
	assert(loadfile("Modules/Observateur.lua"))("Compagnons", ns)
	return ns, module, enregistres
end

local function lignes(ns)
	local t = {}
	for i, e in ipairs(ns.db.global.observation) do t[i] = e[2] end
	return t
end

local function contient(ns, fragment)
	for _, l in ipairs(lignes(ns)) do
		if l:find(fragment, 1, true) then return true end
	end
	return false
end

describe("Observateur", function()
	it("enregistre les événements et mémorise l'activation", function()
		local ns, module, enregistres = monter()
		module:Demarrer()
		assert.is_true(enregistres.TRADE_ACCEPT_UPDATE)
		assert.is_true(enregistres.MAIL_INBOX_UPDATE)
		assert.is_true(enregistres.UNIT_SPELLCAST_SUCCEEDED)
		assert.is_true(ns.db.profile.observer)
		assert.is_true(contient(ns, "observation démarrée, build 70862"))
	end)

	it("signale les événements que le client ne connaît pas, sans planter", function()
		local ns, module, enregistres = monter({ inconnus = { TRADE_SKILL_CRAFT_BEGIN = true, ITEM_PUSH = true } })
		module:Demarrer()
		assert.is_nil(enregistres.TRADE_SKILL_CRAFT_BEGIN)
		assert.is_true(enregistres.TRADE_SHOW)
		assert.is_true(contient(ns, "événements inconnus du client : "))
		assert.is_true(contient(ns, "TRADE_SKILL_CRAFT_BEGIN"))
		assert.is_true(contient(ns, "ITEM_PUSH"))
	end)

	it("ne garde des lancers de sorts que ceux d'une recette de la base, pour le personnage", function()
		local ns, module = monter()
		module:Demarrer()
		module:SurEvenement("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2329)
		module:SurEvenement("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 999)   -- pas une recette
		module:SurEvenement("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 2329)  -- pas le personnage
		local n = 0
		for _, l in ipairs(lignes(ns)) do if l:find("UNIT_SPELLCAST", 1, true) then n = n + 1 end end
		assert.are.equal(1, n)
		assert.is_true(contient(ns, "[recette Élixir]"))
	end)

	it("prend un instantané du contenu de l'échange", function()
		local ns, module = monter()
		module:Demarrer()
		module:SurEvenement("TRADE_ACCEPT_UPDATE", 1, 0)
		assert.is_true(contient(ns, "TRADE_ACCEPT_UPDATE 1 0"))
		assert.is_true(contient(ns, "partenaire=Orvanne"))
		assert.is_true(contient(ns, "moi[1]=Terrestrine x10"))
		assert.is_true(contient(ns, "lui[1]=Fiole vide x5"))
	end)

	it("prend un instantané du courrier reçu et du courrier envoyé", function()
		local ns, module = monter()
		module:Demarrer()
		module:SurEvenement("MAIL_INBOX_UPDATE")
		assert.is_true(contient(ns, "courrier reçu : 1"))
		assert.is_true(contient(ns, "de Brumefer « Commande »"))
		assert.is_true(contient(ns, "Potion(118) x5"))
		module:SurEvenement("MAIL_SEND_INFO_UPDATE")
		assert.is_true(contient(ns, "pj[1]=Élixir(2454) x3"))
	end)

	it("une API absente ou qui échoue est notée, jamais une erreur", function()
		local ns, module = monter()
		rawset(_G, "GetInboxHeaderInfo", function() error("boum") end)
		rawset(_G, "GetTradePlayerItemInfo", nil)
		module:Demarrer()
		module:SurEvenement("MAIL_INBOX_UPDATE")
		module:SurEvenement("TRADE_SHOW")
		assert.is_true(contient(ns, "courrier reçu : 1"))
		assert.is_true(contient(ns, "erreur"))
	end)

	it("s'arrête et se vide sur demande", function()
		local ns, module, enregistres = monter()
		module:Demarrer()
		module:Arreter()
		assert.is_nil(enregistres.TRADE_SHOW)
		assert.is_false(ns.db.profile.observer)
		module:Commande("clear")
		assert.are.equal(0, #ns.db.global.observation)
	end)

	it("garde au plus 400 lignes", function()
		local ns, module = monter()
		module:Demarrer()
		for i = 1, 500 do module:SurEvenement("CHAT_MSG_SYSTEM", "message " .. i) end
		assert.are.equal(400, #ns.db.global.observation)
		assert.is_true(contient(ns, "message 500"))
		assert.is_false(contient(ns, "message 10 "))
	end)
end)
