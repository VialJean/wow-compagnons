-- Relevé du stock de composants de chaque personnage (sacs et banque), pour que « Manque N » et la liste de courses
-- comptent tous mes personnages. Voir Core/Stock.lua et docs/livraison.md (phase 1).
-- Message émis : COMPAGNONS_STOCK_MAJ
-- /cpg stock [on|off|now]
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Stocks = Compagnons:NewModule("Stocks", "AceEvent-3.0")
ns.Stocks = Stocks

local DELAI_REGROUPEMENT = 3   -- les changements de sacs arrivent en rafale : un seul relevé
local DELAI_CONNEXION = 6      -- laisse le temps au jeu de charger les objets

local function compter(itemID)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
	if GetItemCount then return GetItemCount(itemID, true) or 0 end
	return 0
end

function Stocks:OnEnable()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Programmer")
	self:RegisterEvent("BANKFRAME_CLOSED", "Programmer")
	self:RegisterEvent("PLAYER_LOGOUT", "Releve")
	C_Timer.After(DELAI_CONNEXION, function() self:Releve() end)
end

function Stocks:Actif()
	return ns.db.profile.stock.suivi
end

function Stocks:Programmer()
	if self.prevu or not self:Actif() then return end
	self.prevu = true
	C_Timer.After(DELAI_REGROUPEMENT, function()
		self.prevu = false
		self:Releve()
	end)
end

--- Relève le stock du personnage connecté et l'enregistre.
function Stocks:Releve()
	if not self:Actif() then return end
	ns.db.global.stock[ns.clePersonnage()] = ns.Stock.releve(ns.Recettes, compter, time())
	Compagnons:SendMessage("COMPAGNONS_STOCK_MAJ")
end

-- ---------------------------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------------------------

--- Quantité d'un composant sur tous mes personnages (le personnage connecté est lu en direct).
function Stocks:Total(itemID)
	return ns.Stock.total(ns.db.global.stock, itemID, ns.Atelier:Miens(), ns.clePersonnage(), compter)
end

--- Où se trouve un composant : { { cle, n, maj }, ... }.
function Stocks:Detail(itemID)
	return ns.Stock.detail(ns.db.global.stock, itemID, ns.Atelier:Miens(), ns.clePersonnage(), compter)
end

--- Liste de courses pour mes commandes en cours.
function Stocks:Courses()
	return ns.Stock.courses({
		commandes = ns.db.global.commandes,
		miens = ns.Atelier:Miens(),
		donnees = ns.Recettes,
		stocks = ns.db.global.stock,
		courant = ns.clePersonnage(),
		vivant = compter,
	})
end

-- ---------------------------------------------------------------------------------------------
-- /cpg stock
-- ---------------------------------------------------------------------------------------------

function Stocks:Commande(action)
	action = type(action) == "string" and action:lower() or ""
	if action == "on" then
		ns.db.profile.stock.suivi = true
		self:Releve()
	elseif action == "off" then
		ns.db.profile.stock.suivi = false
	elseif action == "now" then
		self:Releve()
	end
	local n = 0
	for _ in pairs(ns.db.global.stock) do n = n + 1 end
	Compagnons:Print(string.format(L.STOCK_ETAT, self:Actif() and L.INFO_ACTIVE or L.INFO_DESACTIVE, n))
end
