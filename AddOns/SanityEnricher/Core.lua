local ADDON_NAME, ns = ...

-- Standardwerte der Einstellungen. Jedes Modul hat einen eigenen Unterbereich.
ns.DEFAULTS = {
	enabled = true, -- Hauptschalter für alle Automatiken
	quests = {
		accept = true,     -- annehmen
		turnIn = true,     -- abgeben
		trivial = false,   -- graue Quests annehmen
		repeatable = true, -- wiederholbare/tägliche Quests annehmen
		confirm = true,    -- Gruppen-/Eskortquests bestätigen
	},
	vendor = {
		sellJunk = true,
		repair = true,
		guildRepair = true, -- zuerst aus der Gildenbank, sonst eigenes Gold
	},
	frames = {
		move = true,     -- Standardfenster frei verschieben
		remember = true, -- Positionen über Sitzungen hinweg merken
	},
}

-- Shift gedrückt = Automatiken pausieren
function ns.Paused()
	return not ns.db.settings.enabled or IsShiftKeyDown()
end

-- ---- Event-Verteiler -------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- Unbekannte Events werfen auf Forever einen Fehler, der die Datei abbrechen wuerde
		local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then
			ns.Print("Event %s nicht verfügbar: %s", event, tostring(err))
		end
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)

-- ---- SavedVariables --------------------------------------------------------

-- Fehlende Werte aus den Standardwerten ergänzen (auch in Unterbereichen)
local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

local function InitDB()
	SanityEnricherDB = SanityEnricherDB or {}
	local db = SanityEnricherDB
	db.settings = db.settings or {}
	ApplyDefaults(db.settings, ns.DEFAULTS)
	ns.db = db
end

ns.On("ADDON_LOADED", function(name)
	if name == ADDON_NAME then
		InitDB()
	end
end)

-- ---- Ein/Aus ---------------------------------------------------------------

local toggleCallbacks = {}

function ns.OnToggle(fn)
	table.insert(toggleCallbacks, fn)
end

function ns.SetEnabled(enabled)
	ns.db.settings.enabled = enabled
	ns.Print(enabled and "An" or "Aus")
	for _, fn in ipairs(toggleCallbacks) do
		fn(enabled)
	end
end

function ns.Toggle()
	ns.SetEnabled(not ns.db.settings.enabled)
end

-- ---- Slash-Befehle ---------------------------------------------------------

local commands = {}
ns.commands = commands

commands.an = function() ns.SetEnabled(true) end
commands.aus = function() ns.SetEnabled(false) end
commands.toggle = ns.Toggle

local function Help()
	ns.Print("Befehle:")
	ns.Print("  /sanity – Optionen")
	ns.Print("  /sanity an | aus | toggle")
	ns.Print("  /sanity minimap – Minimap-Button ein-/ausblenden")
	ns.Print("  /sanity fenster – Fensterpositionen zurücksetzen")
	ns.Print("Shift gedrückt halten = Pause")
end

SLASH_SANITYENRICHER1 = "/sanity"
SlashCmdList.SANITYENRICHER = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" and commands.options then
		commands.options()
		return
	end
	local fn = commands[cmd]
	if fn then
		fn(rest)
	else
		Help()
	end
end

-- Addon-Menü: Linksklick an/aus, Rechtsklick Optionen
function SanityEnricher_OnAddonCompartmentClick(_, buttonName)
	if buttonName == "RightButton" then
		commands.options()
	else
		ns.Toggle()
	end
end
