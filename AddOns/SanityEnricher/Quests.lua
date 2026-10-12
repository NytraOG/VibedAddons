local _, ns = ...

-- Quests automatisch annehmen und abgeben.
-- Bei mehreren Belohnungen zur Auswahl wird angehalten; die Wahl trifft der Spieler.

-- Dieselbe Quest wird innerhalb dieser Zeit nicht erneut aus einer NPC-Liste gewählt.
-- Schützt vor Schleifen, z.B. wenn der Spieler das Belohnungsfenster schließt und
-- der NPC sofort wieder seine Liste zeigt.
local RETRY_SECONDS = 10

local function S()
	return ns.db.settings.quests
end

local lastPicked = {}

local function MayPick(kind, questID)
	questID = ns.SafeID(questID)
	if not questID then
		return false
	end
	local key = kind .. ":" .. questID
	local now = GetTime()
	if lastPicked[key] and now - lastPicked[key] < RETRY_SECONDS then
		return false
	end
	lastPicked[key] = now
	return true
end

local function WantAvailable(isTrivial, frequency, isRepeatable, isIgnored)
	local s = S()
	if not s.accept or isIgnored then
		return false
	end
	if isTrivial and not s.trivial then
		return false
	end
	local recurring = isRepeatable or (frequency and frequency ~= Enum.QuestFrequency.Default)
	if recurring and not s.repeatable then
		return false
	end
	return true
end

-- ---- NPC mit Gesprächsmenü -------------------------------------------------

ns.On("GOSSIP_SHOW", function()
	if ns.Paused() then
		return
	end
	-- Erst abgeben, dann annehmen; pro Event nur eine Quest; der NPC zeigt danach die Liste erneut
	if S().turnIn then
		for _, info in ipairs(C_GossipInfo.GetActiveQuests()) do
			if info.isComplete and MayPick("active", info.questID) then
				C_GossipInfo.SelectActiveQuest(info.questID)
				return
			end
		end
	end
	for _, info in ipairs(C_GossipInfo.GetAvailableQuests()) do
		if WantAvailable(info.isTrivial, info.frequency, info.repeatable, info.isIgnored)
			and MayPick("available", info.questID) then
			C_GossipInfo.SelectAvailableQuest(info.questID)
			return
		end
	end
end)

-- ---- NPC mit reiner Questliste ---------------------------------------------

ns.On("QUEST_GREETING", function()
	if ns.Paused() then
		return
	end
	if S().turnIn then
		for i = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(i)
			if isComplete and MayPick("active", GetActiveQuestID(i)) then
				SelectActiveQuest(i)
				return
			end
		end
	end
	for i = 1, GetNumAvailableQuests() do
		local isTrivial, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(i)
		if WantAvailable(isTrivial, frequency, isRepeatable, false) and MayPick("available", questID) then
			SelectAvailableQuest(i)
			return
		end
	end
end)

-- ---- Annehmen --------------------------------------------------------------

ns.On("QUEST_DETAIL", function(questStartItemID)
	if ns.Paused() or not S().accept then
		return
	end
	-- Diese Fälle schließt Blizzard selbst und zeigt ein Popup im Quest-Tracker
	if (questStartItemID and questStartItemID ~= 0) or QuestIsFromAdventureMap() then
		return
	end
	if QuestGetAutoAccept() then
		if not QuestIsFromAreaTrigger() then
			AcknowledgeAutoAcceptQuest()
		end
		return
	end
	-- PvP-Quests brauchen eine Bestätigung
	if QuestFlagsPVP() then
		return
	end
	local questID = ns.SafeID(GetQuestID())
	if not S().trivial and questID and C_QuestLog.IsQuestTrivial(questID) then
		return
	end
	AcceptQuest()
end)

-- Gruppenmitglied startet eine Eskort-/Gruppenquest
ns.On("QUEST_ACCEPT_CONFIRM", function()
	if ns.Paused() or not S().confirm then
		return
	end
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	if numQuests >= MAX_QUESTS then
		return
	end
	ConfirmAcceptQuest()
	-- Blizzard zeigt den Dialog im selben Event; je nach Reihenfolge erst danach schließen
	StaticPopup_Hide("QUEST_ACCEPT")
	C_Timer.After(0, function()
		StaticPopup_Hide("QUEST_ACCEPT")
	end)
end)

-- ---- Abgeben ---------------------------------------------------------------

ns.On("QUEST_PROGRESS", function()
	if ns.Paused() or not S().turnIn then
		return
	end
	if not IsQuestCompletable() then
		return
	end
	if GetQuestMoneyToGet() > 0 then
		ns.Print("Quest kostet Gold, bitte selbst abgeben.")
		return
	end
	CompleteQuest()
end)

ns.On("QUEST_COMPLETE", function()
	if ns.Paused() or not S().turnIn then
		return
	end
	local numChoices = GetNumQuestChoices()
	if numChoices > 1 or GetQuestMoneyToGet() > 0 then
		return
	end
	GetQuestReward(numChoices == 1 and 1 or 0)
end)
