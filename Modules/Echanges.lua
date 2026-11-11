-- Détection des livraisons par échange (phase 3 de docs/livraison.md), d'après le relevé en jeu :
--   * le contenu de l'échange n'est lisible qu'avant la fermeture : on garde un instantané à chaque TRADE_ACCEPT_UPDATE ;
--   * la réussite est le message système 251 (UI_INFO_MESSAGE), l'annulation le 250 ;
--   * la fenêtre n'affiche que le prénom du partenaire : le rapprochement se fait sur le prénom (Core/Livraison.lua).
-- Rien n'est jamais accepté ni envoyé automatiquement : on propose de faire avancer la commande, le joueur confirme.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Echanges = Compagnons:NewModule("Echanges", "AceEvent-3.0")
ns.Echanges = Echanges

local MESSAGE_REUSSI = 251
local MESSAGE_ANNULE = 250
local EMPLACEMENTS = 7

local function idObjet(lien)
	return type(lien) == "string" and tonumber(lien:match("item:(%d+)")) or nil
end

--- Lit un côté de l'échange : { [itemID] = quantité }.
local function lireCote(fonctionLien, fonctionInfo)
	local objets = {}
	for i = 1, EMPLACEMENTS do
		local ok, lien = pcall(fonctionLien, i)
		local id = ok and idObjet(lien)
		if id then
			local ok2, _, _, nombre = pcall(fonctionInfo, i)
			objets[id] = (objets[id] or 0) + ((ok2 and tonumber(nombre)) or 1)
		end
	end
	return objets
end

function Echanges:OnEnable()
	self.instantane = nil
	self:RegisterEvent("TRADE_SHOW", "SurOuverture")
	self:RegisterEvent("TRADE_ACCEPT_UPDATE", "SurAcceptation")
	self:RegisterEvent("UI_INFO_MESSAGE", "SurMessage")

	StaticPopupDialogs["COMPAGNONS_LIVRAISON"] = {
		text = "%s",
		button1 = L.LIVRAISON_OUI,
		button2 = L.LIVRAISON_NON,
		OnAccept = function(_, data) Echanges:Appliquer(data) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

function Echanges:Actif()
	return ns.db.profile.livraison.suivi
end

function Echanges:SurOuverture()
	self.instantane = nil
end

function Echanges:SurAcceptation()
	if not self:Actif() then return end
	local partenaire = UnitName and UnitName("NPC")
	if not partenaire then return end
	self.instantane = {
		partenaire = partenaire,
		donne = lireCote(GetTradePlayerItemLink, GetTradePlayerItemInfo),
		recu = lireCote(GetTradeTargetItemLink, GetTradeTargetItemInfo),
	}
end

function Echanges:SurMessage(_, code)
	if code == MESSAGE_ANNULE then
		self.instantane = nil
	elseif code == MESSAGE_REUSSI then
		local e = self.instantane
		self.instantane = nil
		if e and self:Actif() then self:Traiter(e.partenaire, e.recu, e.donne) end
	end
end

--- Rapproche un échange terminé des commandes que j'ai prises, puis propose (ou applique) les transitions.
function Echanges:Traiter(partenaire, recu, donne)
	local moi = ns.clePersonnage()
	local cumul = ns.db.global.livraisonCumul
	ns.Livraison.purger(cumul, ns.db.global.commandes, moi)
	local propositions, nouveau = ns.Livraison.rapprocher(ns.db.global.commandes, ns.Recettes, moi, partenaire, recu, donne, cumul)
	-- Remplace le contenu en place : la table appartient à la base de données.
	for id in pairs(cumul) do cumul[id] = nil end
	for id, fiche in pairs(nouveau) do cumul[id] = fiche end
	ns.log("sync", "livraison", "échange avec %s : %d proposition(s)", tostring(partenaire), #propositions)
	for _, p in ipairs(propositions) do
		if ns.db.profile.livraison.confirmer then
			self:Demander(p)
		else
			self:Appliquer(p)
		end
	end
end

function Echanges:Demander(p)
	local o = ns.db.global.commandes[p.id]
	local recette = o and ns.Recettes.recettes[o.spell]
	if not o or not recette then return end
	local modele = p.action == "mats" and L.LIVRAISON_MATS or L.LIVRAISON_TERMINER
	StaticPopup_Show("COMPAGNONS_LIVRAISON", string.format(modele, o.client, o.qte, recette.nom or "?"), nil, p)
end

function Echanges:Appliquer(p)
	local moteur = ns.Reseau and ns.Reseau.moteur
	local o = ns.db.global.commandes[p.id]
	if not moteur or not o or not o.assigne then return end
	if moteur:AgirCommande(p.id, p.action, o.assigne) then
		local recette = ns.Recettes.recettes[o.spell]
		local modele = p.action == "mats" and L.LIVRAISON_FAIT_MATS or L.LIVRAISON_FAIT_TERMINER
		Compagnons:Print(string.format(modele, recette and recette.nom or "?"))
		Compagnons:SendMessage("COMPAGNONS_COMMANDES_MAJ")
	end
end
