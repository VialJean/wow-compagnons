-- Bouton de minicarte (LibDataBroker + LibDBIcon).
-- Clic gauche : ouvre l'atelier. Clic droit : masque le bouton (/cpg minicarte le réaffiche).
local NOM, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Minicarte = Compagnons:NewModule("Minicarte")
ns.Minicarte = Minicarte

local ICONE = "Interface\\Icons\\Trade_BlackSmithing"

function Minicarte:OnEnable()
	local ok, ldb = pcall(LibStub, "LibDataBroker-1.1")
	local ok2, dbicon = pcall(LibStub, "LibDBIcon-1.0")
	if not (ok and ok2 and ldb and dbicon) then
		ns.log("erreur", "ui", "minicarte : LibDataBroker ou LibDBIcon indisponible")
		return
	end

	local objet = ldb:NewDataObject(NOM, {
		type = "launcher",
		text = NOM,
		icon = ICONE,
		OnClick = function(_, bouton)
			if bouton == "RightButton" then
				Minicarte:Basculer()
			else
				Compagnons:GetModule("Fenetre"):Basculer()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(NOM, 0.88, 0.7, 0.32)
			local n = 0
			for _ in pairs(ns.db.global.personnages) do n = n + 1 end
			tooltip:AddLine(string.format(L.MINICARTE_PERSOS, n), 1, 1, 1)
			tooltip:AddLine(L.MINICARTE_AIDE, 0.66, 0.61, 0.53)
		end,
	})

	dbicon:Register(NOM, objet, ns.db.profile.minimap)
	self.dbicon = dbicon
end

--- Masque ou réaffiche le bouton.
function Minicarte:Basculer()
	if not self.dbicon then return end
	local reglage = ns.db.profile.minimap
	reglage.hide = not reglage.hide
	if reglage.hide then
		self.dbicon:Hide(NOM)
		Compagnons:Print(L.MINICARTE_MASQUEE)
	else
		self.dbicon:Show(NOM)
	end
end
