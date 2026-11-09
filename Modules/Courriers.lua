-- Détection des livraisons par courrier (phase 4 de docs/livraison.md), d'après le relevé en jeu :
--   envoi      MAIL_SEND_INFO_UPDATE à chaque changement du brouillon (destinataire, pièces jointes), puis
--              MAIL_SEND_SUCCESS une fois le destinataire déjà vide : on garde le dernier brouillon et on l'exploite
--              à la réussite ;
--   réception  MAIL_INBOX_UPDATE : retirer une pièce jointe la fait disparaître du relevé de la boîte, on compare donc
--              le relevé avant/après (Core/Livraison.lua) pour savoir quels courriers ont été vidés.
-- Le retrait des pièces jointes reste un clic du joueur ; on ne fait que le constater. Même confirmation que pour les
-- échanges (module Echanges).
local _, ns = ...
local Compagnons = ns.addon

local Courriers = Compagnons:NewModule("Courriers", "AceEvent-3.0")
ns.Courriers = Courriers

local MAX_PIECES = 12
local MAX_COURRIERS = 50

function Courriers:OnEnable()
	self.brouillon = nil
	self.boite = nil
	self:RegisterEvent("MAIL_SHOW", "SurOuverture")
	self:RegisterEvent("MAIL_CLOSED", "SurFermeture")
	self:RegisterEvent("MAIL_INBOX_UPDATE", "SurBoite")
	self:RegisterEvent("MAIL_SEND_INFO_UPDATE", "SurBrouillon")
	self:RegisterEvent("MAIL_SEND_SUCCESS", "SurEnvoi")
	self:RegisterEvent("MAIL_FAILED", "SurEchec")
end

function Courriers:Actif()
	return ns.db.profile.livraison.suivi
end

-- ---------------------------------------------------------------------------------------------
-- Envoi
-- ---------------------------------------------------------------------------------------------

function Courriers:SurBrouillon()
	if not self:Actif() then return end
	local champ = _G.SendMailNameEditBox
	local destinataire = champ and champ.GetText and champ:GetText()
	if not destinataire or destinataire == "" then return end
	local objets = {}
	for i = 1, MAX_PIECES do
		local ok, nom, itemID, _, nombre = pcall(GetSendMailItem, i)
		if ok and nom and tonumber(itemID) then
			objets[itemID] = (objets[itemID] or 0) + (tonumber(nombre) or 1)
		end
	end
	self.brouillon = { destinataire = destinataire, objets = objets }
end

function Courriers:SurEnvoi()
	local b = self.brouillon
	self.brouillon = nil
	if b and next(b.objets) and self:Actif() and ns.Echanges then
		ns.Echanges:Traiter(b.destinataire, {}, b.objets)
	end
end

function Courriers:SurEchec()
	self.brouillon = nil
end

-- ---------------------------------------------------------------------------------------------
-- Réception
-- ---------------------------------------------------------------------------------------------

--- Relevé de la boîte : les courriers qui ont des pièces jointes.
local function lireBoite()
	local courriers = {}
	local total = GetInboxNumItems and GetInboxNumItems() or 0
	for i = 1, math.min(total, MAX_COURRIERS) do
		local ok, _, _, expediteur, sujet, _, _, _, avecObjet = pcall(GetInboxHeaderInfo, i)
		if ok and avecObjet and expediteur then
			local objets = {}
			for j = 1, MAX_PIECES do
				local ok2, nom, itemID, _, nombre = pcall(GetInboxItem, i, j)
				if ok2 and nom and tonumber(itemID) then
					objets[itemID] = (objets[itemID] or 0) + (tonumber(nombre) or 1)
				end
			end
			courriers[#courriers + 1] = { expediteur = expediteur, sujet = sujet, objets = objets }
		end
	end
	return courriers
end

function Courriers:SurOuverture()
	self.boite = nil
end

function Courriers:SurFermeture()
	self.boite, self.brouillon = nil, nil
end

function Courriers:SurBoite()
	if not self:Actif() then return end
	local apres = lireBoite()
	local avant = self.boite
	self.boite = apres
	if not avant or not ns.Echanges then return end
	for _, c in ipairs(ns.Livraison.courriersRetires(avant, apres)) do
		ns.Echanges:Traiter(c.expediteur, c.objets, {})
	end
end
