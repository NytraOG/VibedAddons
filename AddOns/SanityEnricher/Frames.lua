local _, ns = ...

-- Standardfenster frei verschieben: Taschen, Berufe, Auktionshaus, Charakter, Post, Händler usw.
-- Ziehen mit der linken Maustaste am Fensterhintergrund oder Titel.
--
-- Erfasst werden alle Fenster aus Blizzards Fenster-Register UIPanelWindows (auch aus nachgeladenen
-- Addons) sowie die Taschenfenster. Blizzard setzt diese Fenster beim Öffnen und Umordnen neu
-- (FramePositionDelegate:UpdateUIPanelPositions, UpdateContainerFrameAnchors); danach wird die
-- gemerkte Position wieder angewandt. Edit-Mode-Elemente (frame.system) bleiben unberührt.

-- Vollbild-, Menü- und Edit-Mode-Fenster sowie Fenster, die Blizzard selbst verschiebbar macht
local EXCLUDED = {
	GameMenuFrame = true,
	EditModeManagerFrame = true,
	SettingsPanel = true,
	CinematicFrame = true,
	BarberShopFrame = true,
	HouseEditorFrame = true,
	PerksProgramFrame = true,
	SubscriptionInterstitialFrame = true,
	LootFrame = true,
}

-- Fenster außerhalb von UIPanelWindows
local EXTRA = { "ContainerFrameCombinedBags", "OpenMailFrame" }

local hooked = {} -- frame -> Name
local session = {} -- Positionen, wenn sie nicht gespeichert werden sollen
local pendingApply, pendingSetup = {}, {}

local function S()
	return ns.db.settings.frames
end

local function Active()
	return ns.db and ns.db.settings.enabled and S().move
end

-- Positionen in Bildschirm-Koordinaten (unabhängig von der Skalierung des Fensters)
local function Positions()
	if S().remember then
		ns.db.framePositions = ns.db.framePositions or {}
		return ns.db.framePositions
	end
	return session
end

-- Geschützte Fenster dürfen im Kampf nicht bewegt werden
local function Blocked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

local function Apply(frame)
	local pos = Active() and Positions()[hooked[frame]]
	-- Maximierte Weltkarte bleibt, wie Blizzard sie setzt
	if not pos or not frame:IsShown() or frame.isMaximized then
		return
	end
	if Blocked(frame) then
		pendingApply[frame] = true
		return
	end
	local scale = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x / scale, pos.y / scale)
end

local function ApplyAll()
	for frame in pairs(hooked) do
		Apply(frame)
	end
end

local function OnDragStart(frame)
	if not Active() or frame.isMaximized or Blocked(frame) then
		return
	end
	frame.sanityMoving = true
	frame:StartMoving()
end

local function OnDragStop(frame)
	if not frame.sanityMoving then
		return
	end
	frame.sanityMoving = nil
	frame:StopMovingOrSizing()
	-- Die Position verwaltet das Addon, nicht Blizzards Layout-Speicher
	frame:SetUserPlaced(false)
	local scale = frame:GetEffectiveScale()
	Positions()[hooked[frame]] = { x = frame:GetLeft() * scale, y = frame:GetTop() * scale }
	Apply(frame)
end

local function Setup(frame, name)
	if hooked[frame] or EXCLUDED[name] or type(frame) ~= "table" or not frame.GetObjectType then
		return
	end
	-- Edit-Mode-Elemente tragen ihr System in frame.system; Fenster mit eigener Zieh-Funktion lässt man in Ruhe
	if frame.system or frame:GetScript("OnDragStart") then
		return
	end
	if Blocked(frame) then
		pendingSetup[frame] = name
		return
	end
	hooked[frame] = name
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", OnDragStart)
	frame:HookScript("OnDragStop", OnDragStop)
	frame:HookScript("OnHide", OnDragStop)
	frame:HookScript("OnShow", Apply)
end

local function SetupByName(name)
	local frame = _G[name]
	if frame then
		local ok, err = pcall(Setup, frame, name)
		if not ok then
			ns.Print("Fenster %s nicht verschiebbar: %s", name, tostring(err))
			hooked[frame] = nil
		end
	end
end

-- Alle bekannten Fenster erfassen; nachgeladene Addons registrieren ihre Fenster erst später
local function Scan()
	for name in pairs(UIPanelWindows or {}) do
		SetupByName(name)
	end
	for i = 1, NUM_CONTAINER_FRAMES or 0 do
		SetupByName("ContainerFrame" .. i)
	end
	for _, name in ipairs(EXTRA) do
		SetupByName(name)
	end
end

ns.On("ADDON_LOADED", Scan)
ns.On("PLAYER_LOGIN", Scan)

ns.On("PLAYER_REGEN_ENABLED", function()
	for frame, name in pairs(pendingSetup) do
		pendingSetup[frame] = nil
		Setup(frame, name)
	end
	for frame in pairs(pendingApply) do
		pendingApply[frame] = nil
		Apply(frame)
	end
end)

-- Nach Blizzards Neupositionierung die gemerkten Positionen wieder anwenden
local function Hook(target, name)
	local ok, err
	if name then
		ok, err = pcall(hooksecurefunc, target, name, ApplyAll)
	else
		ok, err = pcall(hooksecurefunc, target, ApplyAll)
	end
	if not ok then
		ns.Print("Hook %s nicht möglich: %s", tostring(name or target), tostring(err))
	end
end

if FramePositionDelegate then
	Hook(FramePositionDelegate, "UpdateUIPanelPositions")
end
Hook("UpdateContainerFrameAnchors")

function ns.ResetFramePositions()
	wipe(session)
	ns.db.framePositions = {}
	ns.Print("Fensterpositionen zurückgesetzt. Gilt beim nächsten Öffnen.")
end

ns.commands.fenster = ns.ResetFramePositions
