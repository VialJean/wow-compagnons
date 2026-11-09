-- Simulateur de synchro hors jeu : de 2 à 50 clients autour d'un réseau virtuel (latence, horloge simulée),
-- avec connexions, déconnexions et scans aléatoires. Vérifie que tous les clients convergent. busted tests
local function charger()
	local ns = {}
	for _, fichier in ipairs({ "Core/Bitset.lua", "Core/Catalogue.lua", "Core/Profil.lua", "Core/Commandes.lua", "Core/Synchro.lua" }) do
		assert(loadfile(fichier))("Compagnons", ns)
	end
	return ns
end

local ns = charger()
local Synchro, Profil, Bitset = ns.Synchro, ns.Profil, ns.Bitset

-- Base de recettes factice : 2 métiers de 64 recettes.
local donnees = { metiers = {}, recettes = {}, objets = {} }
for _, def in ipairs({ { 171, "Alchimie", 1000 }, { 164, "Forge", 2000 } }) do
	local ordre = {}
	for i = 1, 64 do
		local spellID = def[3] + i
		ordre[i] = spellID
		donnees.recettes[spellID] = { metier = def[1], indice = i, niveau = i, nom = "R" .. spellID,
			objet = 1, qte = 1, qualite = 1, composants = {} }
	end
	donnees.metiers[def[1]] = { nom = def[2], ordre = ordre }
end

local function copie(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copie(x) end
	return c
end

-- Générateur pseudo-aléatoire déterministe (le même scénario à chaque exécution).
local function generateur(graine)
	local etat = graine
	return function()
		etat = (etat * 1103515245 + 12345) % 2147483648
		return etat / 2147483648
	end
end

local function nouveauReseau(graine)
	local alea = generateur(graine)
	local r = { t = 0, evenements = {}, sequence = 0, clients = {}, parNom = {}, messages = 0, alea = alea }

	function r:planifier(delai, fn)
		self.sequence = self.sequence + 1
		local e = { t = self.t + delai, n = self.sequence, fn = fn }
		local i = #self.evenements
		while i >= 1 and (self.evenements[i].t > e.t or (self.evenements[i].t == e.t and self.evenements[i].n > e.n)) do i = i - 1 end
		table.insert(self.evenements, i + 1, e)
	end

	function r:avancer(duree)
		local fin = self.t + duree
		while self.evenements[1] and self.evenements[1].t <= fin do
			local e = table.remove(self.evenements, 1)
			self.t = e.t
			e.fn()
		end
		self.t = fin
	end

	-- Le jeu nomme l'expéditeur « Prénom-Nom » (voir docs/protocole.md).
	local function brut(nom) return (nom:gsub(" ", "-")) end

	function r:livrer(source, canal, cible, genre, charge)
		self.messages = self.messages + 1
		local function vers(autre)
			self:planifier(0.1 + alea() * 0.4, function()
				if autre.enLigne then autre.moteur:Recevoir(genre, copie(charge), brut(source.nom)) end
			end)
		end
		if canal == "GUILD" then
			for _, autre in ipairs(self.clients) do
				if autre ~= source and autre.enLigne then vers(autre) end
			end
		else
			local autre = self.parNom[(cible:gsub("%-", " "))]
			if autre and autre.enLigne then vers(autre) end
		end
	end

	function r:client(nom)
		local c = { nom = nom, profils = {}, commandes = {}, enLigne = false }
		c.moteur = Synchro.nouveau({
			donnees = donnees,
			profils = c.profils,
			commandes = c.commandes,
			moi = function() return nom end,
			proprietaire = function(cle) return cle == nom end,
			envoyer = function(canal, cible, genre, charge) r:livrer(c, canal, cible, genre, charge) end,
			maintenant = function() return r.t end,
			planifier = function(delai, fn) r:planifier(delai, function() if c.enLigne then fn() end end) end,
			alea = alea,
		})
		self.clients[#self.clients + 1] = c
		self.parNom[nom] = c
		return c
	end

	return r
end

--- Profil aléatoire pour un personnage ; `maj` croissant d'un scan à l'autre.
local function profilAleatoire(alea, cle, maj)
	local metiers = {}
	for _, id in ipairs({ 171, 164 }) do
		if alea() < 0.7 then
			local ensemble = {}
			for i = 1, 64 do
				if alea() < 0.3 then ensemble[i] = true end
			end
			metiers[id] = { niveau = math.floor(alea() * 300), max = 300, bits = Bitset.encoder(ensemble, 64) }
		end
	end
	local p = { cle = cle, nom = cle, prenom = cle:match("^%S+"), classe = "MAGE", maj = maj, metiers = metiers }
	p.hash = Profil.hash(p)
	return p
end

local function connecter(c)
	c.enLigne = true
	c.moteur:Annoncer()
end

local function identiques(clients)
	local h = clients[1].moteur:HashGlobal()
	for _, c in ipairs(clients) do
		if c.moteur:HashGlobal() ~= h then return false end
	end
	return true
end

describe("Synchro", function()
	it("deux clients échangent leurs profils à la connexion", function()
		local r = nouveauReseau(1)
		local a, b = r:client("Alice Durand"), r:client("Bastien Roux")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 100)
		b.profils[b.nom] = profilAleatoire(r.alea, b.nom, 200)
		a.moteur:Annoncer() ; a.enLigne = true
		connecter(b)
		r:avancer(60)
		assert.is_true(identiques({ a, b }))
		assert.are.equal(2, a.moteur:Compter())
		assert.are.equal(200, a.profils["Bastien Roux"].maj)
	end)

	it("le profil le plus récent gagne, jamais l'inverse", function()
		local r = nouveauReseau(2)
		local a, b = r:client("Alice Durand"), r:client("Bastien Roux")
		local ancien = profilAleatoire(r.alea, "Camille Petit", 50)
		local recent = profilAleatoire(r.alea, "Camille Petit", 90)
		a.profils["Camille Petit"] = ancien
		b.profils["Camille Petit"] = recent
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		b.profils[b.nom] = profilAleatoire(r.alea, b.nom, 10)
		connecter(a) ; connecter(b)
		r:avancer(60)
		assert.are.equal(90, a.profils["Camille Petit"].maj)
		assert.are.equal(90, b.profils["Camille Petit"].maj)
		assert.is_true(identiques({ a, b }))
	end)

	it("départage de façon déterministe deux versions de même date", function()
		local r = nouveauReseau(3)
		local a, b = r:client("Alice Durand"), r:client("Bastien Roux")
		a.profils["Camille Petit"] = profilAleatoire(r.alea, "Camille Petit", 70)
		b.profils["Camille Petit"] = profilAleatoire(r.alea, "Camille Petit", 70)
		assert.are_not.equal(a.profils["Camille Petit"].hash, b.profils["Camille Petit"].hash)
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		b.profils[b.nom] = profilAleatoire(r.alea, b.nom, 10)
		connecter(a) ; connecter(b)
		r:avancer(60)
		assert.are.equal(a.profils["Camille Petit"].hash, b.profils["Camille Petit"].hash)
	end)

	it("un scan en ligne se diffuse tout de suite aux autres", function()
		local r = nouveauReseau(4)
		local a, b = r:client("Alice Durand"), r:client("Bastien Roux")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		b.profils[b.nom] = profilAleatoire(r.alea, b.nom, 10)
		connecter(a) ; connecter(b)
		r:avancer(60)
		assert.is_true(a.moteur:Publier(profilAleatoire(r.alea, a.nom, 500)))
		r:avancer(2)
		assert.are.equal(500, b.profils["Alice Durand"].maj)
	end)

	it("republier un profil identique n'envoie rien", function()
		local r = nouveauReseau(5)
		local a = r:client("Alice Durand")
		local p = profilAleatoire(r.alea, a.nom, 10)
		a.profils[a.nom] = p
		assert.is_false(a.moteur:Publier(copie(p)))
	end)

	it("refuse qu'un pair écrase nos propres personnages", function()
		local r = nouveauReseau(6)
		local a = r:client("Alice Durand")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		local avant = a.profils[a.nom].hash
		a.moteur:Recevoir("PROFILE", { v = Synchro.PROTOCOLE, profil = profilAleatoire(r.alea, a.nom, 9999) }, "Mallory-Evil")
		assert.are.equal(avant, a.profils[a.nom].hash)
	end)

	it("ignore les profils invalides ou démesurés", function()
		local r = nouveauReseau(7)
		local a = r:client("Alice Durand")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		local bon = profilAleatoire(r.alea, "Zed Zorro", 20)
		local trop = copie(bon) ; trop.metiers[171] = { niveau = 1, max = 1, bits = string.rep("x", 5000) }
		local sansCle = copie(bon) ; sansCle.cle = nil
		local dateFolle = copie(bon) ; dateFolle.maj = "demain"
		for _, mauvais in ipairs({ trop, sansCle, dateFolle, "texte", 42 }) do
			a.moteur:Recevoir("PROFILE_UPD", { v = Synchro.PROTOCOLE, profil = mauvais }, "Mallory-Evil")
		end
		assert.is_nil(a.profils["Zed Zorro"])
		a.moteur:Recevoir("PROFILE_UPD", { v = Synchro.PROTOCOLE, profil = bon }, "Zed-Zorro")
		assert.is_not_nil(a.profils["Zed Zorro"])
	end)

	it("recalcule le hash au lieu de croire celui du réseau", function()
		local r = nouveauReseau(8)
		local a = r:client("Alice Durand")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		local p = profilAleatoire(r.alea, "Zed Zorro", 20)
		local vrai = p.hash
		p.hash = 99999999
		a.moteur:Recevoir("PROFILE_UPD", { v = Synchro.PROTOCOLE, profil = p }, "Zed-Zorro")
		assert.are.equal(vrai, a.profils["Zed Zorro"].hash)
	end)

	it("ignore un autre numéro de protocole et ses propres messages", function()
		local r = nouveauReseau(9)
		local a = r:client("Alice Durand")
		a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
		a.moteur:Recevoir("PROFILE_UPD", { v = 99, profil = profilAleatoire(r.alea, "Zed Zorro", 20) }, "Zed-Zorro")
		a.moteur:Recevoir("PROFILE_UPD", { v = Synchro.PROTOCOLE, profil = profilAleatoire(r.alea, "Zed Zorro", 20) }, "Alice-Durand")
		assert.is_nil(a.profils["Zed Zorro"])
	end)

	for _, taille in ipairs({ 5, 25, 50 }) do
		it("converge avec " .. taille .. " clients, connexions et scans aléatoires", function()
			local r = nouveauReseau(100 + taille)
			local derniere = {}
			local maj = 1000
			for i = 1, taille do
				local c = r:client(string.format("Membre%02d Test%02d", i, i))
				maj = maj + 1
				c.profils[c.nom] = profilAleatoire(r.alea, c.nom, maj)
				derniere[c.nom] = maj
			end

			for _ = 1, taille * 12 do
				r:avancer(1 + r.alea() * 30)
				local c = r.clients[math.floor(r.alea() * taille) + 1]
				local tirage = r.alea()
				if not c.enLigne then
					connecter(c)
				elseif tirage < 0.25 then
					c.enLigne = false
				elseif tirage < 0.7 then
					maj = maj + 1
					c.moteur:Publier(profilAleatoire(r.alea, c.nom, maj))
					derniere[c.nom] = maj
				end
			end

			-- Tout le monde se connecte (ceux qui l'étaient déjà se ré-annoncent), puis on laisse le temps passer.
			for _, c in ipairs(r.clients) do
				if c.enLigne then c.moteur:Annoncer() else connecter(c) end
				r:avancer(3)
			end
			r:avancer(600)

			assert.is_true(identiques(r.clients))
			for _, c in ipairs(r.clients) do
				assert.are.equal(taille, c.moteur:Compter())
				for nom, m in pairs(derniere) do assert.are.equal(m, c.profils[nom].maj) end
			end
			local total = {}
			for _, c in ipairs(r.clients) do
				for genre, n in pairs(c.moteur.stats.parGenre) do total[genre] = (total[genre] or 0) + n end
			end
			print(string.format("    %d clients : %d messages (%.1f par client) HELLO %d, PRET %d, HASHES %d, PROFILE %d, REQ %d, UPD %d",
				taille, r.messages, r.messages / taille, total.HELLO or 0, total.PRET or 0, total.HASHES or 0, total.PROFILE or 0,
				total.PROFILE_REQ or 0, total.PROFILE_UPD or 0))
		end)
	end
end)

-- ---------------------------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------------------------

local Commandes = ns.Commandes

local function deuxClients(graine)
	local r = nouveauReseau(graine)
	local a, b = r:client("Alice Durand"), r:client("Bastien Roux")
	a.profils[a.nom] = profilAleatoire(r.alea, a.nom, 10)
	b.profils[b.nom] = profilAleatoire(r.alea, b.nom, 10)
	connecter(a) ; connecter(b)
	r:avancer(60)
	return r, a, b
end

describe("Synchro des commandes", function()
	it("une commande créée en ligne arrive chez les autres, puis suit son cycle de vie", function()
		local r, a, b = deuxClients(20)
		local c = a.moteur:CreerCommande({ client = a.nom, spell = 1001, qte = 5, mats = "tout", note = "ce soir" })
		r:avancer(2)
		assert.are.equal("ouverte", b.commandes[c.id].statut)
		assert.are.equal(5, b.commandes[c.id].qte)

		assert.is_not_nil(b.moteur:AgirCommande(c.id, "prendre", b.nom))
		r:avancer(2)
		assert.are.equal("prise", a.commandes[c.id].statut)
		assert.are.equal(b.nom, a.commandes[c.id].assigne)

		assert.is_not_nil(b.moteur:AgirCommande(c.id, "mats", b.nom))
		assert.is_not_nil(b.moteur:AgirCommande(c.id, "terminer", b.nom))
		r:avancer(2)
		assert.are.equal("terminee", a.commandes[c.id].statut)
		assert.are.equal(3, a.commandes[c.id].rev) -- trois transitions
		assert.is_true(identiques({ a, b }))
	end)

	it("refuse les actions interdites : seul le client annule, seul le crafteur assigné avance", function()
		local r, a, b = deuxClients(21)
		local c = a.moteur:CreerCommande({ client = a.nom, spell = 1001, qte = 1 })
		r:avancer(2)
		local ok, raison = b.moteur:AgirCommande(c.id, "annuler", b.nom)
		assert.is_nil(ok)
		assert.are.equal("interdit", raison)
		assert.is_nil((b.moteur:AgirCommande(c.id, "terminer", b.nom)))
		b.moteur:AgirCommande(c.id, "prendre", b.nom)
		r:avancer(2)
		assert.is_nil((a.moteur:AgirCommande(c.id, "terminer", a.nom))) -- le client ne peut pas terminer
		assert.is_not_nil(a.moteur:AgirCommande(c.id, "annuler", a.nom))
		r:avancer(2)
		assert.are.equal("annulee", b.commandes[c.id].statut)
		assert.is_nil((b.moteur:AgirCommande(c.id, "liberer", b.nom))) -- finale
	end)

	it("rejette un message forgé : annulation par un tiers, prise par un autre que le crafteur désigné", function()
		local r, a, b = deuxClients(22)
		local c = a.moteur:CreerCommande({ client = a.nom, spell = 1001, qte = 1, crafteur = b.nom })
		r:avancer(2)
		-- Mallory forge l'annulation de la commande d'Alice
		local forge = copie(c)
		forge.statut, forge.rev, forge.par, forge.maj = "annulee", 1, "Mallory Evil", c.maj + 1
		forge.hash = Commandes.hash(forge)
		b.moteur:Recevoir("ORDER_UPD", { v = Synchro.PROTOCOLE, commande = forge }, "Mallory-Evil")
		assert.are.equal("ouverte", b.commandes[c.id].statut)
		-- Mallory prend une commande réservée à Bastien
		local prise = copie(c)
		prise.statut, prise.rev, prise.par, prise.assigne, prise.maj = "prise", 1, "Mallory Evil", "Mallory Evil", c.maj + 1
		prise.hash = Commandes.hash(prise)
		b.moteur:Recevoir("ORDER_UPD", { v = Synchro.PROTOCOLE, commande = prise }, "Mallory-Evil")
		assert.are.equal("ouverte", b.commandes[c.id].statut)
	end)

	it("départage deux crafteurs qui prennent en même temps de façon identique partout", function()
		local r = nouveauReseau(23)
		local a, b, c = r:client("Alice Durand"), r:client("Bastien Roux"), r:client("Camille Petit")
		for _, x in ipairs({ a, b, c }) do x.profils[x.nom] = profilAleatoire(r.alea, x.nom, 10) ; connecter(x) end
		r:avancer(60)
		local o = a.moteur:CreerCommande({ client = a.nom, spell = 1001, qte = 1 })
		r:avancer(2)
		-- Bastien et Camille prennent la commande dans la même seconde, chacun de son côté
		b.moteur:AgirCommande(o.id, "prendre", b.nom)
		c.moteur:AgirCommande(o.id, "prendre", c.nom)
		r:avancer(120)
		assert.is_true(identiques({ a, b, c }))
		local gagnant = a.commandes[o.id].assigne
		assert.is_true(gagnant == b.nom or gagnant == c.nom)
		assert.are.equal(gagnant, b.commandes[o.id].assigne)
		assert.are.equal(gagnant, c.commandes[o.id].assigne)
	end)

	it("synchronise les commandes manquées pendant une déconnexion", function()
		local r, a, b = deuxClients(24)
		b.enLigne = false
		local o = a.moteur:CreerCommande({ client = a.nom, spell = 1002, qte = 2 })
		a.moteur:AgirCommande(o.id, "annuler", a.nom)
		r:avancer(5)
		assert.is_nil(b.commandes[o.id])
		connecter(b)
		r:avancer(120)
		assert.are.equal("annulee", b.commandes[o.id].statut)
		assert.is_true(identiques({ a, b }))
	end)

	it("oublie les commandes finales après 7 jours, et ne les réimporte pas", function()
		local r, a, b = deuxClients(25)
		local o = a.moteur:CreerCommande({ client = a.nom, spell = 1001, qte = 1 })
		a.moteur:AgirCommande(o.id, "annuler", a.nom)
		r:avancer(5)
		assert.is_not_nil(b.commandes[o.id])
		local ancienne = copie(a.commandes[o.id])
		r:avancer(8 * 24 * 3600)
		a.moteur:Annoncer() ; b.moteur:Annoncer()
		r:avancer(60)
		assert.is_nil(a.commandes[o.id])
		assert.is_nil(b.commandes[o.id])
		-- Une copie périmée arrivant du réseau est refusée
		a.moteur:Recevoir("ORDER", { v = Synchro.PROTOCOLE, commande = ancienne }, "Bastien-Roux")
		assert.is_nil(a.commandes[o.id])
	end)

	it("ignore les commandes invalides", function()
		local r, a = deuxClients(26)
		local bonne = Commandes.nouvelle({ client = "Zed Zorro", spell = 1001, qte = 1, maintenant = r.t })
		local mauvaises = {}
		local function variante(f) local c = copie(bonne) ; f(c) ; mauvaises[#mauvaises + 1] = c end
		variante(function(c) c.spell = 424242 end)                 -- recette inconnue
		variante(function(c) c.qte = 0 end)
		variante(function(c) c.statut = "inventé" end)
		variante(function(c) c.id = nil end)
		variante(function(c) c.statut, c.rev, c.assigne = "ouverte", 1, "Zed Zorro" end) -- ouverte mais assignée
		variante(function(c) c.statut, c.rev = "prise", 1 end)     -- prise sans crafteur
		for _, m in ipairs(mauvaises) do
			a.moteur:Recevoir("ORDER_NEW", { v = Synchro.PROTOCOLE, commande = m }, "Zed-Zorro")
		end
		a.moteur:Recevoir("ORDER_NEW", { v = Synchro.PROTOCOLE, commande = "texte" }, "Zed-Zorro")
		assert.are.equal(0, a.moteur:CompterCommandes())
		a.moteur:Recevoir("ORDER_NEW", { v = Synchro.PROTOCOLE, commande = bonne }, "Zed-Zorro")
		assert.are.equal(1, a.moteur:CompterCommandes())
	end)

	it("converge avec 20 clients, profils et commandes mêlés, connexions aléatoires", function()
		local r = nouveauReseau(300)
		local taille = 20
		for i = 1, taille do
			local c = r:client(string.format("Membre%02d Test%02d", i, i))
			c.profils[c.nom] = profilAleatoire(r.alea, c.nom, 1000 + i)
		end
		local actions = { "prendre", "mats", "terminer", "liberer", "annuler" }
		for _ = 1, taille * 15 do
			r:avancer(1 + r.alea() * 30)
			local c = r.clients[math.floor(r.alea() * taille) + 1]
			local tirage = r.alea()
			if not c.enLigne then
				connecter(c)
			elseif tirage < 0.15 then
				c.enLigne = false
			elseif tirage < 0.45 then
				c.moteur:CreerCommande({ client = c.nom, spell = 1000 + math.floor(r.alea() * 64) + 1,
					qte = 1 + math.floor(r.alea() * 10), mats = "partie" })
			else
				local ids = {}
				for id in pairs(c.commandes) do ids[#ids + 1] = id end
				table.sort(ids)
				if #ids > 0 then
					local id = ids[math.floor(r.alea() * #ids) + 1]
					c.moteur:AgirCommande(id, actions[math.floor(r.alea() * #actions) + 1], c.nom)
				end
			end
		end
		for _, c in ipairs(r.clients) do
			if c.enLigne then c.moteur:Annoncer() else connecter(c) end
			r:avancer(3)
		end
		r:avancer(900)
		assert.is_true(identiques(r.clients))
		local n = r.clients[1].moteur:CompterCommandes()
		assert.is_true(n > 0)
		for _, c in ipairs(r.clients) do assert.are.equal(n, c.moteur:CompterCommandes()) end
		print(string.format("    20 clients : %d commandes, %d messages", n, r.messages))
	end)
end)
