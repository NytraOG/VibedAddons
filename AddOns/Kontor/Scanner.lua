local _, ns = ...

-- Komplett-Scan per C_AuctionHouse.ReplicateItems().
-- Ablauf: ReplicateItems -> REPLICATE_ITEM_LIST_UPDATE -> alle Eintraege in Haeppchen lesen
-- (Zeitbudget pro Frame, damit das Spiel nicht einfriert) -> Snapshot und Preise speichern.

local TOP_N = 5
local OUTLIER_FACTOR = 10 -- Angebote ueber dem 10-fachen des guenstigsten zaehlen nicht zum Schnitt
local FRAME_BUDGET_MS = 8
local RESPONSE_TIMEOUT = 60
local RETRY_ROUNDS = 3
-- Sperrzeit zwischen zwei Komplett-Scans. Auf Retail 15 Minuten; fuer Forever angenommen, nicht bestaetigt.
local SCAN_COOLDOWN = 15 * 60

local scan -- laufender Scan, sonst nil
local worker = CreateFrame("Frame")
worker:Hide()

ns.ahOpen = false
ns.On("AUCTION_HOUSE_SHOW", function() ns.ahOpen = true end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	ns.ahOpen = false
	if scan then
		ns.AbortScan("Auktionshaus wurde geschlossen.")
	end
end)

local function Notify()
	if ns.OnScanProgress then
		ns.OnScanProgress(scan)
	end
end

function ns.IsScanning()
	return scan ~= nil
end

function ns.AbortScan(reason)
	worker:Hide()
	scan = nil
	ns.Print("|cffff6060Scan abgebrochen:|r %s", reason)
	Notify()
end

local function ReadEntry(index)
	local _, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, itemID =
		C_AuctionHouse.GetReplicateItemInfo(index)
	if not itemID then
		return false
	end
	local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft(index) or 0
	count = count or 1
	buyout = buyout or 0
	-- Preise koennen ueber 2^31 liegen (Hoechstpreis 9.999.999g); %d schafft in WoW nur 32 Bit, daher %.0f
	scan.raw[#scan.raw + 1] = ("%d:%d:%.0f:%.0f:%d:%s"):format(itemID, count, buyout, minBid or 0, timeLeft, owner or "")

	local entry = scan.items[itemID]
	if not entry then
		entry = { units = {}, quantity = 0, auctions = 0 }
		scan.items[itemID] = entry
	end
	entry.quantity = entry.quantity + count
	entry.auctions = entry.auctions + 1
	if buyout > 0 and count > 0 then
		entry.units[#entry.units + 1] = buyout / count
	end
	return true
end

local function Finish()
	worker:Hide()
	local realm = ns.RealmData()
	local prices, historyItems, itemCount = {}, {}, 0

	for itemID, entry in pairs(scan.items) do
		itemCount = itemCount + 1
		local units = entry.units
		local top5, minimum
		if #units > 0 then
			table.sort(units)
			-- Mondpreise (z.B. 9.999.999g als Platzhalter) wuerden den Schnitt bei wenigen Angeboten verzerren
			local limit = units[1] * OUTLIER_FACTOR
			local n, sum = 0, 0
			for i = 1, math.min(TOP_N, #units) do
				if units[i] > limit then
					break
				end
				n = n + 1
				sum = sum + units[i]
			end
			top5 = math.floor(sum / n + 0.5)
			minimum = math.floor(units[1] + 0.5)
		end
		-- Items ohne Sofortkauf (nur Gebote) haben keinen Preis, zaehlen aber im Angebot mit
		prices[itemID] = { top5 = top5, min = minimum, quantity = entry.quantity, auctions = entry.auctions }
		historyItems[itemID] = ("%.0f:%.0f:%d:%d"):format(top5 or 0, minimum or 0, entry.quantity, entry.auctions)
	end

	local meta = {
		time = scan.startedAt,
		duration = math.floor((GetTimePreciseSec() - scan.startedPrecise) * 10 + 0.5) / 10,
		auctions = #scan.raw,
		items = itemCount,
		unresolved = #scan.pending,
		realm = GetRealmName(),
		faction = UnitFactionGroup("player"),
		character = UnitName("player"),
		build = (select(2, GetBuildInfo())),
		addonVersion = C_AddOns.GetAddOnMetadata("Kontor", "Version"),
	}

	realm.prices = prices
	realm.lastScan = { meta = meta, raw = scan.raw }
	table.insert(realm.history, { meta = meta, items = historyItems })
	while #realm.history > ns.db.settings.historyLimit do
		table.remove(realm.history, 1)
	end

	ns.Print("Scan fertig: %d Auktionen, %d verschiedene Items, %.1f s.%s", meta.auctions, meta.items, meta.duration,
		meta.unresolved > 0 and (" %d Einträge ohne Item-Daten übersprungen."):format(meta.unresolved) or "")
	if scan.errors > 0 then
		ns.Print("|cffff6060%d Einträge mit Fehler übersprungen.|r Erster Fehler: %s", scan.errors, scan.firstError)
	end
	scan = nil
	Notify()
	if ns.OnPricesChanged then
		ns.OnPricesChanged()
	end
end

-- Ein fehlerhafter Eintrag darf nicht den ganzen Scan blockieren: Fehler zaehlen, weitermachen.
-- Rueckgabe: true = gelesen, false = Item-Daten fehlen noch
local function TryReadEntry(index)
	local ok, result = pcall(ReadEntry, index)
	if ok then
		return result
	end
	scan.errors = scan.errors + 1
	scan.firstError = scan.firstError or tostring(result)
	return true
end

local function ProcessPending()
	local stillPending = {}
	for _, index in ipairs(scan.pending) do
		if not TryReadEntry(index) then
			stillPending[#stillPending + 1] = index
		end
	end
	scan.pending = stillPending
	scan.retries = scan.retries + 1
	if #stillPending == 0 or scan.retries >= RETRY_ROUNDS then
		Finish()
	else
		C_Timer.After(1, function()
			if scan then
				ProcessPending()
			end
		end)
	end
end

worker:SetScript("OnUpdate", function()
	local deadline = debugprofilestop() + FRAME_BUDGET_MS
	while scan.nextIndex < scan.total do
		local index = scan.nextIndex
		scan.nextIndex = index + 1
		if not TryReadEntry(index) then
			scan.pending[#scan.pending + 1] = index
		end
		if debugprofilestop() > deadline then
			break
		end
	end
	Notify()
	if scan.nextIndex >= scan.total then
		worker:Hide()
		if #scan.pending > 0 then
			ProcessPending()
		else
			Finish()
		end
	end
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
	if not scan or scan.phase ~= "waiting" then
		return
	end
	scan.phase = "reading"
	-- Indizes der Replicate-Liste beginnen bei 0
	scan.total = C_AuctionHouse.GetNumReplicateItems()
	scan.nextIndex = 0
	ns.Print("Server hat %d Auktionen geliefert, werte aus …", scan.total)
	if scan.total == 0 then
		ns.AbortScan("Der Server hat 0 Auktionen geliefert (Sperrzeit aktiv?).")
		return
	end
	worker:Show()
end)

-- Restliche Sperrzeit in Sekunden (0 = bereit). Zaehlt ab dem letzten Scan-Versuch.
function ns.ScanCooldownRemaining()
	local last = ns.RealmData().lastScanAttempt
	if not last then
		return 0
	end
	return math.max(0, last + SCAN_COOLDOWN - time())
end

function ns.FormatDuration(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function ns.StartScan(force)
	if scan then
		ns.Print("Es läuft bereits ein Scan.")
		return
	end
	if not ns.ahOpen and not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		ns.Print("Bitte zuerst das Auktionshaus öffnen.")
		return
	end
	local realm = ns.RealmData()
	local remaining = ns.ScanCooldownRemaining()
	if remaining > 0 and not force then
		ns.Print("Komplett-Scan erst in %s wieder möglich. Mit /kontor scan force trotzdem versuchen.",
			ns.FormatDuration(remaining))
		return
	end
	realm.lastScanAttempt = time()

	scan = {
		phase = "waiting",
		startedAt = time(),
		startedPrecise = GetTimePreciseSec(),
		raw = {},
		items = {},
		pending = {},
		retries = 0,
		errors = 0,
		total = 0,
		nextIndex = 0,
	}
	local thisScan = scan
	C_AuctionHouse.ReplicateItems()
	ns.Print("Komplett-Scan angefordert, warte auf den Server …")
	Notify()

	C_Timer.After(RESPONSE_TIMEOUT, function()
		if scan == thisScan and scan.phase == "waiting" then
			ns.AbortScan(("Keine Antwort vom Server nach %d s (Sperrzeit aktiv?)."):format(RESPONSE_TIMEOUT))
		end
	end)
end

function ns.ScanProgress()
	if not scan then
		return nil
	end
	if scan.phase == "waiting" or scan.total == 0 then
		return 0
	end
	return scan.nextIndex / scan.total
end

ns.commands.scan = function(args)
	ns.StartScan(args == "force")
end
