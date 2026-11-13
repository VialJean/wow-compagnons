-- Tests hors jeu du modèle des commandes (Core/Commandes.lua) : cycle de vie, droits, validation réseau. busted tests
local ns = { Profil = { adler = function(s) return #s end } }
assert(loadfile("Core/Commandes.lua"))("Compagnons", ns)
local Commandes = ns.Commandes

local CLIENT, CRAFTEUR, AUTRE = "Wilgar Rolpik", "Jean Vialjean", "Elias Legentillet"
local donnees = { recettes = { [2329] = {} } }
local T0 = 1731180000

local function nouvelle()
	return Commandes.nouvelle({ client = CLIENT, spell = 2329, qte = 3, mats = "partie", maintenant = T0 })
end

--- Fait passer une commande par une suite d'actions { { action, par }, ... } ; échoue si l'une est refusée.
local function enchainer(c, suite)
	for i, etape in ipairs(suite) do
		local n, raison = Commandes.appliquer(c, etape[1], etape[2], T0 + i)
		assert(n, string.format("%s par %s refusé (%s)", etape[1], etape[2], tostring(raison)))
		c = n
	end
	return c
end

local function livree()
	return enchainer(nouvelle(), { { "prendre", CRAFTEUR }, { "mats", CRAFTEUR }, { "livrer", CRAFTEUR } })
end

local function avec(c, champs)
	local n = {}
	for k, v in pairs(c) do n[k] = v end
	for k, v in pairs(champs) do n[k] = v end
	return n
end

describe("Commandes : livraison et confirmation", function()
	it("le crafteur livre : la commande est livrée, pas terminée", function()
		local c = livree()
		assert.are.equal("livree", c.statut)
		assert.are.equal(CRAFTEUR, c.par)
		assert.are.equal(CRAFTEUR, c.assigne)
	end)

	it("on peut livrer depuis « prise » sans passer par « mats »", function()
		local c = enchainer(nouvelle(), { { "prendre", CRAFTEUR }, { "livrer", CRAFTEUR } })
		assert.are.equal("livree", c.statut)
	end)

	it("le client confirme : la commande est terminée", function()
		local c = enchainer(livree(), { { "confirmer", CLIENT } })
		assert.are.equal("terminee", c.statut)
		assert.are.equal(CLIENT, c.par)
		assert.are.equal(CRAFTEUR, c.assigne)
		assert.is_true(Commandes.estFinale(c))
	end)

	it("le client conteste : la commande revient au même crafteur", function()
		local c = enchainer(livree(), { { "contester", CLIENT } })
		assert.are.equal("prise", c.statut)
		assert.are.equal(CRAFTEUR, c.assigne) -- et non le client
		assert.are.equal(CLIENT, c.par)
		-- le crafteur peut alors livrer de nouveau
		assert.are.equal("livree", enchainer(c, { { "livrer", CRAFTEUR } }).statut)
	end)

	it("si le client est son propre crafteur, la livraison termine la commande", function()
		local c = enchainer(nouvelle(), { { "prendre", CLIENT }, { "livrer", CLIENT } })
		assert.are.equal("terminee", c.statut)
	end)

	it("une commande livrée n'est pas finale, mais plus rien n'est à fabriquer", function()
		local c = livree()
		assert.is_false(Commandes.estFinale(c))
		assert.is_true(Commandes.estAchevee(c))
		assert.is_false(Commandes.estAchevee(nouvelle()))
	end)

	it("une commande livrée sans confirmation est oubliée après 7 jours, comme une commande finale", function()
		local c = livree()
		assert.is_false(Commandes.perimee(c, c.maj + Commandes.DUREE_CONSERVATION))
		assert.is_true(Commandes.perimee(c, c.maj + Commandes.DUREE_CONSERVATION + 1))
		assert.is_false(Commandes.perimee(nouvelle(), T0 + 365 * 86400)) -- une commande ouverte ne se périme pas
	end)
end)

describe("Commandes : droits", function()
	local function refuse(c, action, par)
		local n, raison = Commandes.appliquer(c, action, par, T0 + 50)
		assert.is_nil(n)
		assert.are.equal("interdit", raison)
	end

	it("seul le crafteur assigné livre", function()
		local c = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		refuse(c, "livrer", CLIENT)
		refuse(c, "livrer", AUTRE)
	end)

	it("on ne livre pas une commande qui n'est pas prise", function()
		refuse(nouvelle(), "livrer", CRAFTEUR)
	end)

	it("seul le client confirme ou conteste, et seulement une commande livrée", function()
		local l = livree()
		refuse(l, "confirmer", CRAFTEUR)
		refuse(l, "confirmer", AUTRE)
		refuse(l, "contester", CRAFTEUR)
		local prise = enchainer(nouvelle(), { { "prendre", CRAFTEUR }, { "mats", CRAFTEUR } })
		refuse(prise, "confirmer", CLIENT)
		refuse(prise, "contester", CLIENT)
		refuse(nouvelle(), "confirmer", CLIENT)
	end)

	it("une commande terminée ne bouge plus", function()
		local t = enchainer(livree(), { { "confirmer", CLIENT } })
		for _, action in ipairs({ "livrer", "confirmer", "contester", "mats", "liberer", "annuler", "prendre" }) do
			refuse(t, action, CLIENT)
			refuse(t, action, CRAFTEUR)
		end
	end)

	it("le crafteur ne libère plus une commande livrée, le client peut encore l'annuler", function()
		local l = livree()
		refuse(l, "liberer", CRAFTEUR)
		assert.are.equal("annulee", enchainer(l, { { "annuler", CLIENT } }).statut)
	end)

	it("la progression des fabrications n'avance plus une fois livrée", function()
		local c = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		assert.is_not_nil(Commandes.appliquer(c, "progres", CRAFTEUR, T0 + 9, { craftes = 2 }))
		refuse(livree(), "progres", CRAFTEUR)
	end)
end)

describe("Commandes.transitionLegale", function()
	local function suite(c, champs)
		local n = avec(c, champs)
		n.rev = c.rev + 1
		return n
	end

	it("accepte la suite normale d'une commande", function()
		local prise = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		local l = Commandes.appliquer(prise, "livrer", CRAFTEUR, T0 + 5)
		assert.is_true(Commandes.transitionLegale(prise, l))
		local t = Commandes.appliquer(l, "confirmer", CLIENT, T0 + 6)
		assert.is_true(Commandes.transitionLegale(l, t))
		local contestee = Commandes.appliquer(l, "contester", CLIENT, T0 + 6)
		assert.is_true(Commandes.transitionLegale(l, contestee))
	end)

	it("refuse un crafteur qui déclare la commande terminée lui-même", function()
		local prise = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		assert.is_false(Commandes.transitionLegale(prise, suite(prise, { statut = "terminee", par = CRAFTEUR })))
		local l = livree()
		assert.is_false(Commandes.transitionLegale(l, suite(l, { statut = "terminee", par = CRAFTEUR })))
	end)

	it("refuse une confirmation écrite par quelqu'un d'autre que le client", function()
		local l = livree()
		assert.is_false(Commandes.transitionLegale(l, suite(l, { statut = "terminee", par = AUTRE })))
	end)

	it("refuse une contestation qui change le crafteur assigné", function()
		local l = livree()
		assert.is_false(Commandes.transitionLegale(l, suite(l, { statut = "prise", par = CLIENT, assigne = CLIENT })))
	end)

	it("refuse un client qui livre à la place du crafteur", function()
		local prise = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		assert.is_false(Commandes.transitionLegale(prise, suite(prise, { statut = "livree", par = CLIENT })))
	end)

	it("une commande terminée d'emblée n'est légale que pour un client qui est son propre crafteur", function()
		local propre = enchainer(nouvelle(), { { "prendre", CLIENT } })
		assert.is_true(Commandes.transitionLegale(propre, suite(propre, { statut = "terminee", par = CLIENT })))
	end)
end)

describe("Commandes.valider (réseau)", function()
	it("accepte une commande livrée puis confirmée", function()
		local l = livree()
		assert.is_not_nil(Commandes.valider(avec(l, {}), donnees))
		assert.is_not_nil(Commandes.valider(avec(enchainer(l, { { "confirmer", CLIENT } }), {}), donnees))
	end)

	it("accepte une commande contestée (« prise » écrite par le client, crafteur inchangé)", function()
		local c = enchainer(livree(), { { "contester", CLIENT } })
		local v = Commandes.valider(avec(c, {}), donnees)
		assert.is_not_nil(v)
		assert.are.equal(CRAFTEUR, v.assigne)
	end)

	it("garde lisible le format d'avant : une commande terminée par son crafteur", function()
		assert.is_not_nil(Commandes.valider(avec(livree(), { statut = "terminee" }), donnees))
	end)

	it("refuse une commande livrée sans crafteur ou écrite par le client ou un tiers", function()
		local l = livree()
		assert.is_nil(Commandes.valider(avec(l, { assigne = false }), donnees))
		assert.is_nil(Commandes.valider(avec(l, { par = CLIENT }), donnees))
		assert.is_nil(Commandes.valider(avec(l, { par = AUTRE }), donnees))
	end)

	it("refuse une commande terminée ou « prise » par un tiers", function()
		local t = enchainer(livree(), { { "confirmer", CLIENT } })
		assert.is_nil(Commandes.valider(avec(t, { par = AUTRE }), donnees))
		local prise = enchainer(nouvelle(), { { "prendre", CRAFTEUR } })
		assert.is_nil(Commandes.valider(avec(prise, { par = AUTRE }), donnees))
	end)

	it("refuse un statut inconnu", function()
		assert.is_nil(Commandes.valider(avec(livree(), { statut = "livree2" }), donnees))
	end)
end)
