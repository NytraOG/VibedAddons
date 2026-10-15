local _, ns = ...

-- Runder Button am Minimap-Rand. Linksklick: Journal. Ziehen: Position am Rand verschieben.

local DEFAULT_ANGLE = 210 -- Grad, gegen den Uhrzeigersinn ab "rechts"

local button

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

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	UpdatePosition()
end

local function CreateButton()
	button = CreateFrame("Button", "KontorMinimapButton", Minimap)
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

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.ToggleMargins()
		elseif IsShiftKeyDown() then
			ns.ToggleHistory()
		else
			ns.ToggleJournal()
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
		GameTooltip:AddLine("Kontor")
		GameTooltip:AddLine("Linksklick: Journal", 1, 1, 1)
		GameTooltip:AddLine("Rechtsklick: Margen-Liste", 1, 1, 1)
		GameTooltip:AddLine("Shift-Linksklick: Preisverlauf", 1, 1, 1)
		GameTooltip:AddLine("Ziehen: Button verschieben", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("/kontor minimap: Button ein-/ausblenden", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	UpdatePosition()
	button:SetShown(not Settings().hide)
end

ns.On("PLAYER_LOGIN", CreateButton)

function ns.IsMinimapButtonShown()
	return not Settings().hide
end

function ns.SetMinimapButtonShown(shown)
	Settings().hide = not shown
	if button then
		button:SetShown(shown)
	end
end

ns.commands.minimap = function()
	ns.SetMinimapButtonShown(not ns.IsMinimapButtonShown())
	ns.Print(ns.IsMinimapButtonShown() and "Minimap-Button eingeblendet." or "Minimap-Button ausgeblendet.")
end
