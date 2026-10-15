local _, ns = ...

-- Taschen beim Öffnen einmal sortieren, genau wie Blizzards Sortier-Knopf (C_Container.SortBags).
-- „Einmal“ heißt: beim ersten Öffnen, nachdem alle Taschen zu waren. Taschen mit Blizzards
-- Einstellung „Beim Aufräumen ignorieren“ bleiben dabei wie gewohnt unberührt.

-- Gesperrte Items (z.B. gerade verkaufter Müll beim Händler) erst abwarten (Annahme: so lange
-- reicht immer)
local LOCK_RETRY_SECONDS = 0.3
local LOCK_RETRY_MAX = 10

local sortedThisOpen = false

local function S()
	return ns.db.settings.bags
end

local function AnyItemLocked()
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then
				return true
			end
		end
	end
	return false
end

local function TrySort(attempt)
	if not IsAnyBagOpen() or InCombatLockdown() then
		return
	end
	if GetCursorInfo() or AnyItemLocked() then
		if attempt < LOCK_RETRY_MAX then
			C_Timer.After(LOCK_RETRY_SECONDS, function()
				TrySort(attempt + 1)
			end)
		end
		return
	end
	C_Container.SortBags()
end

local function OnBagShown()
	if sortedThisOpen then
		return
	end
	sortedThisOpen = true
	if ns.Paused() or not S().autoSort then
		return
	end
	-- Erst nach dem Öffnen aller gleichzeitig geöffneten Taschen
	C_Timer.After(0, function()
		TrySort(1)
	end)
end

local function OnBagHidden()
	-- Beim Schließen aller Taschen gehen mehrere Fenster nacheinander zu
	C_Timer.After(0, function()
		if not IsAnyBagOpen() then
			sortedThisOpen = false
		end
	end)
end

local function Hook(frame)
	if frame then
		frame:HookScript("OnShow", OnBagShown)
		frame:HookScript("OnHide", OnBagHidden)
	end
end

ns.On("PLAYER_LOGIN", function()
	Hook(ContainerFrameCombinedBags)
	for i = 1, NUM_CONTAINER_FRAMES or 0 do
		Hook(_G["ContainerFrame" .. i])
	end
end)
