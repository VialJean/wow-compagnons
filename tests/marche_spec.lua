-- Tests hors jeu du relevé des prix à l'hôtel des ventes (Modules/Marche.lua), avec une API de jeu simulée. busted tests
local function monter()
	local ns = {}
	ns.L = setmetatable({}, { __index = function(_, cle) return cle end })
	ns.log = function() end
	local messages, imprime = {}, {}
	local module = {}
	function module:RegisterEvent(evenement) if evenement == "INCONNU" then error("inconnu") end end
	ns.addon = {
		NewModule = function() return module end,
		SendMessage = function(_, nom) messages[#messages + 1] = nom end,
		Print = function(_, texte) imprime[#imprime + 1] = texte end,
	}
	ns.db = { global = { prix = {} } }
	ns.Recettes = { objets = { [2449] = { "Terrestrine", 1 }, [3371] = { "Fiole vide", 1 } } }
	rawset(_G, "time", function() return 5000 end)
	rawset(_G, "GetCoinTextureString", nil)

	assert(loadfile("Core/Prix.lua"))("Compagnons", ns)
	assert(loadfile("Modules/Marche.lua"))("Compagnons", ns)
	return ns, module, messages, imprime
end

local function lots(liste)
	rawset(_G, "GetNumAuctionItems", function() return #liste, #liste end)
	rawset(_G, "GetAuctionItemLink", function(_, i) return "|Hitem:" .. liste[i].id .. "::|h[x]|h" end)
	rawset(_G, "GetAuctionItemInfo", function(_, i)
		return "x", 1, liste[i].n, 1, false, 1, 1, 10, 1, liste[i].achat
	end)
end

describe("Marche : ancienne API", function()
	after_each(function()
		for _, nom in ipairs({ "GetNumAuctionItems", "GetAuctionItemLink", "GetAuctionItemInfo" }) do rawset(_G, nom, nil) end
	end)

	it("garde le prix unitaire le plus bas de chaque composant affiché", function()
		local ns, module, messages = monter()
		lots({ { id = 2449, n = 5, achat = 600 }, { id = 2449, n = 10, achat = 1000 }, { id = 3371, n = 1, achat = 80 } })
		module:SurListe()
		assert.are.equal(100, ns.db.global.prix[2449].p)
		assert.are.equal(80, ns.db.global.prix[3371].p)
		assert.are.equal(5000, ns.db.global.prix[2449].t)
		assert.are.equal("COMPAGNONS_PRIX_MAJ", messages[1])
	end)

	it("ignore les objets qui ne sont pas des composants de la base et les lots sans achat immédiat", function()
		local ns, module = monter()
		lots({ { id = 99999, n = 1, achat = 5 }, { id = 2449, n = 3, achat = 0 } })
		module:SurListe()
		assert.is_nil(ns.db.global.prix[99999])
		assert.is_nil(ns.db.global.prix[2449])
	end)

	it("une API qui échoue ne casse rien", function()
		local ns, module = monter()
		rawset(_G, "GetNumAuctionItems", function() error("boum") end)
		module:SurListe()
		assert.is_nil(next(ns.db.global.prix))
	end)

	it("ne fait rien quand l'API n'existe pas", function()
		local ns, module = monter()
		module:SurListe()
		assert.is_nil(next(ns.db.global.prix))
	end)
end)

describe("Marche : API moderne", function()
	after_each(function() rawset(_G, "C_AuctionHouse", nil) end)

	it("lit le premier résultat, le moins cher, d'une marchandise", function()
		local ns, module = monter()
		rawset(_G, "C_AuctionHouse", {
			GetNumCommoditySearchResults = function() return 3 end,
			GetCommoditySearchResultInfo = function(_, i) return { unitPrice = i == 1 and 450 or 999 } end,
		})
		module:SurMarchandise("COMMODITY_SEARCH_RESULTS_UPDATED", 2449)
		assert.are.equal(450, ns.db.global.prix[2449].p)
	end)

	it("ignore une marchandise sans résultat ou hors base", function()
		local ns, module = monter()
		rawset(_G, "C_AuctionHouse", {
			GetNumCommoditySearchResults = function() return 0 end,
			GetCommoditySearchResultInfo = function() return { unitPrice = 5 } end,
		})
		module:SurMarchandise("x", 2449)
		module:SurMarchandise("x", 424242)
		assert.is_nil(next(ns.db.global.prix))
	end)
end)

describe("Marche : /cpg prix", function()
	it("fixe un prix à la main (nombre seul = pièces d'or) par identifiant ou par lien", function()
		local ns, module = monter()
		module:Commande("2449", "1.5")
		assert.are.equal(15000, ns.db.global.prix[2449].p)
		module:Commande("|Hitem:3371::|h[Fiole vide]|h", "5s")
		assert.are.equal(500, ns.db.global.prix[3371].p)
	end)

	it("refuse un objet hors base ou un montant illisible, avec le message d'usage", function()
		local ns, module, _, imprime = monter()
		module:Commande("424242", "5")
		module:Commande("2449", "beaucoup")
		assert.is_nil(next(ns.db.global.prix))
		assert.are.equal("PRIX_USAGE", imprime[1])
		assert.are.equal("PRIX_USAGE", imprime[2])
	end)

	it("indique le nombre de prix connus et peut tout effacer", function()
		local ns, module, _, imprime = monter()
		module:Commande("2449", "1")
		module:Commande()
		assert.is_true(imprime[#imprime]:find("PRIX_ETAT", 1, true) ~= nil)
		module:Commande("clear")
		assert.is_nil(next(ns.db.global.prix))
	end)

	it("le prix en or avec décimale ne perd pas de cuivre", function()
		local ns, module = monter()
		module:Commande("2449", "0.0033") -- 33 cuivres
		assert.are.equal(33, ns.db.global.prix[2449].p)
	end)
end)

describe("Marche : événements", function()
	it("ignore sans erreur un événement que le client ne connaît pas", function()
		local _, module = monter()
		module:OnEnable()
		assert.is_true(true)
	end)
end)

describe("Marche : marchand", function()
	local function marchand(articles)
		rawset(_G, "GetMerchantNumItems", function() return #articles end)
		rawset(_G, "GetMerchantItemLink", function(i) return "|Hitem:" .. articles[i].id .. "::|h[x]|h" end)
		rawset(_G, "GetMerchantItemInfo", function(i)
			local a = articles[i]
			return "x", 1, a.prix, a.quantite or 1, a.stock or -1, true, a.cout
		end)
	end
	after_each(function()
		for _, nom in ipairs({ "GetMerchantNumItems", "GetMerchantItemLink", "GetMerchantItemInfo" }) do rawset(_G, nom, nil) end
	end)

	it("retient le prix unitaire des composants vendus sans limite, marqués vendeur", function()
		local ns, module = monter()
		marchand({ { id = 3371, prix = 50, quantite = 5 } })
		module:SurMarchand()
		assert.are.equal(10, ns.db.global.prix[3371].p)
		assert.is_true(ns.db.global.prix[3371].v)
	end)

	it("ignore le stock limité, les prix en jetons, les objets hors base", function()
		local ns, module = monter()
		marchand({ { id = 3371, prix = 50, stock = 3 }, { id = 2449, prix = 50, cout = true }, { id = 99999, prix = 5 } })
		module:SurMarchand()
		assert.is_nil(next(ns.db.global.prix))
	end)

	it("une API absente ou qui échoue ne casse rien", function()
		local ns, module = monter()
		module:SurMarchand()
		rawset(_G, "GetMerchantNumItems", function() error("boum") end)
		module:SurMarchand()
		assert.is_nil(next(ns.db.global.prix))
	end)
end)
