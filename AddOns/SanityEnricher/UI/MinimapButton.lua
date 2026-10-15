local _, ns = ...

-- Runder Button am Minimap-Rand. Linksklick: an/aus. Rechtsklick: Optionen.
-- Ziehen: Position am Rand verschieben.

local DEFAULT_ANGLE = 190 -- Grad, gegen den Uhrzeigersinn ab "rechts"
local ICON = "Interface\\Icons\\INV_Misc_Note_02"

local button, icon

local function Settings()
	local s = ns.db.settings
	s.minimap = s.minimap or { angle = DEFAULT_ANGLE, hide = false }
	return s.minimap
end

local function UpdatePosition()
	local angle = math.rad(Settings().angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateIcon()
	icon:SetDesaturated(not ns.db.settings.enabled)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	UpdatePosition()
end

local function CreateButton()
	button = CreateFrame("Button", "SanityEnricherMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.commands.options()
		else
			ns.Toggle()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Sanity Enricher")
		GameTooltip:AddLine(ns.db.settings.enabled and "An" or "Aus", 1, 1, 1)
		GameTooltip:AddLine("Linksklick: an/aus", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Rechtsklick: Optionen", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	UpdatePosition()
	UpdateIcon()
	button:SetShown(not Settings().hide)
end

ns.On("PLAYER_LOGIN", CreateButton)

ns.OnToggle(function()
	if icon then
		UpdateIcon()
	end
end)

ns.commands.minimap = function()
	local s = Settings()
	s.hide = not s.hide
	button:SetShown(not s.hide)
	ns.Print(s.hide and "Minimap-Button ausgeblendet." or "Minimap-Button eingeblendet.")
end
