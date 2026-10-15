local _, ns = ...

-- Lernbare Zauber: Liste aller Zauber, die der Charakter noch lernen kann, mit Stufe und Preis.
--
-- Preise kennt der Client nur bei offenem Lehrerfenster. Beim Lehrer wird deshalb die ganze
-- Liste pro Charakter in SanityEnricherDB.trainer gespeichert. Annahme: Die Preise bleiben bis zum
-- nächsten Besuch gleich (Ruf-Rabatte o.Ä. werden erst dann aktualisiert).
-- Zusätzlich kommen die zukünftigen Zauber aus dem Zauberbuch dazu (ohne Preis), damit die Liste
-- auch vor dem ersten Lehrerbesuch etwas zeigt.
-- Was der Lehrer nur bei aktivem Filter „Nicht verfügbar“ zeigt, wird auch nur dann erfasst.

local BANK = Enum.SpellBookSpellBank.Player

-- Wartezeit, um mehrere TRAINER_UPDATE hintereinander zusammenzufassen
local TRAINER_READ_DELAY = 0.2

-- Reihenfolge innerhalb einer Stufe: Lehrer-Einträge vor reinen Zauberbuch-Einträgen
local SPELLBOOK_ORDER_OFFSET = 10000

local listeners = {}
local levelOverride

function ns.OnLearnableChanged(fn)
	table.insert(listeners, fn)
end

local function Fire()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- UnitLevel liefert bei PLAYER_LEVEL_UP teils noch die alte Stufe
function ns.PlayerLevel()
	return math.max(UnitLevel("player"), levelOverride or 0)
end

local function CharStore()
	local key = UnitName("player") .. "-" .. GetRealmName()
	ns.db.trainer = ns.db.trainer or {}
	local store = ns.db.trainer[key]
	if not store then
		store = { spells = {} }
		ns.db.trainer[key] = store
	end
	return store
end

function ns.TrainerDataTime()
	return ns.db and CharStore().updated
end

-- ---- Lehrer ------------------------------------------------------------------

local function IsSpellTrainer()
	local trainerType = C_Trainer.GetTrainerType()
	if trainerType == Enum.TrainerType.Tradeskills or trainerType == Enum.TrainerType.Pet then
		return false
	end
	return not (IsTradeskillTrainer and IsTradeskillTrainer())
end

-- Annahme: Der Tooltip eines Lehrer-Eintrags trägt die spellID in data.id
local function ServiceSpellID(index)
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	local id = ok and data and ns.SafeID(data.id)
	if type(id) == "number" and id > 0 then
		return id
	end
end

local function NameKey(name, rank)
	return name .. "|" .. (rank or "")
end

local function ReadTrainer()
	if not ns.db or not IsSpellTrainer() then
		return
	end
	local store = CharStore()
	local spells = store.spells
	for index = 1, GetNumTrainerServices() do
		local name, serviceType, icon, level, rank = GetTrainerServiceInfo(index)
		if name and name ~= "" and serviceType ~= "header" then
			local spellID = ServiceSpellID(index)
			local key = spellID or NameKey(name, rank)
			if serviceType == "used" then
				spells[key] = nil
			else
				spells[key] = {
					spellID = spellID,
					name = name,
					rank = rank ~= "" and rank or nil,
					icon = icon,
					level = level or 0,
					cost = GetTrainerServiceCost(index) or 0,
					order = index,
				}
			end
		end
	end
	store.updated = time()
	Fire()
end

local readPending = false

local function ScheduleRead()
	if readPending then
		return
	end
	readPending = true
	C_Timer.After(TRAINER_READ_DELAY, function()
		readPending = false
		ReadTrainer()
	end)
end

ns.On("TRAINER_SHOW", ScheduleRead)
ns.On("TRAINER_UPDATE", ScheduleRead)

-- ---- Zauberbuch ---------------------------------------------------------------

-- Zukünftige Zauber aus allen sichtbaren Bereichen des Zauberbuchs (ohne andere Spezialisierungen)
local function FutureSpells()
	local result = {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if lineInfo and not lineInfo.shouldHide and not lineInfo.offSpecID then
			for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
				local spellID = item and ns.SafeID(item.spellID)
				if spellID and item.itemType == Enum.SpellBookItemType.FutureSpell then
					local level = ns.SafeID(C_SpellBook.GetSpellBookItemLevelLearned(slot, BANK))
					table.insert(result, {
						spellID = spellID,
						name = item.name,
						rank = item.subName ~= "" and item.subName or nil,
						icon = item.iconID,
						level = level or 0,
						order = SPELLBOOK_ORDER_OFFSET + slot,
					})
				end
			end
		end
	end
	return result
end

-- ---- Liste ----------------------------------------------------------------------

local function IsKnown(spellID)
	return spellID and C_SpellBook.IsSpellKnown(spellID, BANK)
end

local function SortEntries(a, b)
	if a.level ~= b.level then
		return a.level < b.level
	end
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.name < b.name
end

-- Liefert die sortierte Liste sowie Gesamtpreis, Anzahl und Anzahl ohne Preis der jetzt lernbaren
function ns.GetLearnableSpells()
	local list, byID, byName = {}, {}, {}
	if not ns.db then
		return list, 0, 0, 0
	end

	for _, saved in pairs(CharStore().spells) do
		if not IsKnown(saved.spellID) then
			local entry = CopyTable(saved)
			table.insert(list, entry)
			if entry.spellID then
				byID[entry.spellID] = entry
			end
			byName[NameKey(entry.name, entry.rank)] = entry
		end
	end

	for _, future in ipairs(FutureSpells()) do
		local known = byID[future.spellID] or byName[NameKey(future.name, future.rank)]
		if known then
			known.spellID = known.spellID or future.spellID
		elseif not IsKnown(future.spellID) then
			table.insert(list, future)
		end
	end

	table.sort(list, SortEntries)

	local playerLevel = ns.PlayerLevel()
	local total, count, unknown = 0, 0, 0
	for _, entry in ipairs(list) do
		entry.available = entry.level <= playerLevel
		if entry.available then
			count = count + 1
			if entry.cost then
				total = total + entry.cost
			else
				unknown = unknown + 1
			end
		end
	end
	return list, total, count, unknown
end

-- ---- Änderungen melden ------------------------------------------------------------

ns.On("LEARNED_SPELL_IN_SKILL_LINE", Fire)
ns.On("SPELLS_CHANGED", Fire)
ns.On("PLAYER_LEVEL_UP", function(level)
	levelOverride = level
	Fire()
end)
