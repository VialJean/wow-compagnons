-- Bouton de minicarte (LibDataBroker + LibDBIcon).
-- Clic gauche : ouvre l'atelier. Clic droit : masque le bouton (/cpg minicarte le réaffiche).
local NOM, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Minicarte = Compagnons:NewModule("Minicarte", "AceEvent-3.0")
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
			local pourMoi = ns.Atelier and ns.Atelier:CompterPourMoi() or 0
			if pourMoi > 0 then
				tooltip:AddLine(string.format(L.MINICARTE_A_REMPLIR, pourMoi), 0.37, 0.82, 0.41)
			end
			local miennes = 0
			if ns.Atelier then
				for _, o in ipairs(ns.Atelier:Vue("mes")) do
					if not ns.Commandes.estFinale(o) then miennes = miennes + 1 end
				end
			end
			if miennes > 0 then tooltip:AddLine(string.format(L.MINICARTE_EN_COURS, miennes), 0.5, 0.7, 1) end
			tooltip:AddLine(L.MINICARTE_AIDE, 0.66, 0.61, 0.53)
		end,
	})

	dbicon:Register(NOM, objet, ns.db.profile.minimap)
	self.dbicon = dbicon

	-- Pastille : nombre de commandes que l'on peut remplir.
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "ActualiserPastille")
	self:RegisterMessage("COMPAGNONS_CATALOGUE_MAJ", "ActualiserPastille")
	C_Timer.After(3, function() self:ActualiserPastille() end)
end

function Minicarte:ActualiserPastille()
	if not self.dbicon or not ns.Atelier or not ns.catalogue then return end
	local bouton = self.dbicon.GetMinimapButton and self.dbicon:GetMinimapButton(NOM)
	if not bouton then return end
	if not self.pastille then
		local p = bouton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		p:SetPoint("TOPRIGHT", bouton, "TOPRIGHT", 3, 3)
		p:SetTextColor(1, 0.35, 0.3)
		self.pastille = p
	end
	local n = ns.Atelier:CompterPourMoi()
	self.pastille:SetText(n > 0 and tostring(n) or "")
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
