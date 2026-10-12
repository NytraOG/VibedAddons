local ADDON_NAME, ns = ...

local DB_VERSION = 1

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

local loadedFromDisk = false

local function InitDB()
	loadedFromDisk = KontorDB ~= nil
	KontorDB = KontorDB or {}
	local db = KontorDB
	db.version = db.version or DB_VERSION
	db.realms = db.realms or {}
	db.settings = db.settings or {}
	db.settings.historyLimit = db.settings.historyLimit or 100
	db.sessions = (db.sessions or 0) + 1
	ns.db = db
end

function ns.RealmData()
	local key = ns.RealmKey()
	local realm = ns.db.realms[key]
	if not realm then
		realm = {}
		ns.db.realms[key] = realm
	end
	realm.prices = realm.prices or {}
	realm.history = realm.history or {}
	realm.journal = realm.journal or {}  -- Transaktionen
	realm.posted = realm.posted or {}    -- eigene laufende Auktionen nach auctionID
	realm.mailSeen = realm.mailSeen or {} -- bereits verbuchte AH-Post
	return realm
end

ns.On("ADDON_LOADED", function(name)
	if name == ADDON_NAME then
		InitDB()
	end
end)

ns.On("PLAYER_LOGIN", function()
	local db = ns.db
	if loadedFromDisk then
		ns.Print("Daten geladen (Sitzung #%d, zuletzt gespeichert %s).", db.sessions,
			db.lastLogout and ns.DateTime(db.lastLogout) or "unbekannt")
	else
		ns.Print("Keine gespeicherten Daten gefunden. Beim ersten Start ist das normal; nach einem Neustart sollte hier \"Daten geladen\" stehen.")
	end
end)

ns.On("PLAYER_LOGOUT", function()
	ns.db.lastLogout = time()
end)

-- ---- Slash-Befehle ---------------------------------------------------------

local commands = {}
ns.commands = commands

commands.status = function()
	local realm = ns.RealmData()
	local scan = realm.lastScan
	ns.Print("Sitzung #%d · Auktionshaus %s", ns.db.sessions, ns.RealmKey())
	if scan then
		ns.Print("Letzter Scan: %s (%s) · %d Auktionen · %d Items · Verlauf: %d Scans",
			ns.DateTime(scan.meta.time), ns.Ago(scan.meta.time), scan.meta.auctions, scan.meta.items, #realm.history)
	else
		ns.Print("Noch kein Scan für dieses Auktionshaus.")
	end
end

local function Help()
	ns.Print("Befehle:")
	ns.Print("  /kontor – Journal öffnen/schließen")
	ns.Print("  /kontor margen – Margen-Liste öffnen/schließen")
	ns.Print("  /kontor scan – Komplett-Scan (Auktionshaus muss offen sein; \"force\" ignoriert die Sperrzeit)")
	ns.Print("  /kontor status – gespeicherte Daten anzeigen")
	ns.Print("  /kontor minimap – Minimap-Button ein-/ausblenden")
end

SLASH_KONTOR1 = "/kontor"
SlashCmdList.KONTOR = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" and commands.journal then
		commands.journal()
		return
	end
	local fn = commands[cmd]
	if fn then
		fn(rest)
	else
		Help()
	end
end
