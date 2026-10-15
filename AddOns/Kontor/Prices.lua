local _, ns = ...

-- Schwellen fuer Preis-Pfeile stehen in ns.db.settings (trendSignificant, trendLarge, trendMinCopper).
-- Standard 10 % / 25 % / 10 Kupfer ist eine Annahme, abgeleitet aus den eigenen Scans (Abstand ca.
-- 20 Min.): Bei Materialien schwankt der Ø der 5 guenstigsten Angebote bei rund 30 % der Items um 5 %
-- oder mehr (Rauschen), bei 10-20 % um 10 % oder mehr, kaum je um 25 %.

local function ParseHistoryEntry(entry)
	local top5, minimum, quantity, auctions = entry:match("^(%d+):(%d+):(%d+):(%d+)$")
	top5 = tonumber(top5)
	if top5 and top5 > 0 then
		return { top5 = top5, min = tonumber(minimum), quantity = tonumber(quantity), auctions = tonumber(auctions) }
	end
end

-- Preis eines Items aus dem letzten Scan des aktuellen Auktionshauses.
-- Rueckgabe: { top5, min, quantity, auctions } (Kupfer pro Stueck) und Scan-Zeitpunkt, oder nil.
function ns.GetAuctionPrice(itemID)
	local realm = ns.RealmData()
	local price = realm.prices[itemID]
	if not price then
		return nil
	end
	return price, realm.lastScan and realm.lastScan.meta.time
end

-- Juengster Scan im Verlauf, in dem das Item einen Sofortkaufpreis hatte (z.B. wenn es im
-- letzten Scan ausverkauft war). Rueckgabe wie GetAuctionPrice, oder nil.
function ns.GetLastKnownPrice(itemID)
	local history = ns.RealmData().history
	for i = #history, 1, -1 do
		local entry = history[i].items[itemID]
		local price = entry and ParseHistoryEntry(entry)
		if price then
			return price, history[i].meta.time
		end
	end
end

-- Vergleichsbasis fuer die Preis-Pfeile: der juengste Scan vor dem letzten, der mindestens
-- trendMinAgeHours aelter ist. nil, wenn es keinen gibt.
function ns.PreviousSnapshot()
	local realm = ns.RealmData()
	local last = realm.lastScan and realm.lastScan.meta.time
	if not last then
		return nil
	end
	local latest = last - ns.db.settings.trendMinAgeHours * 3600
	for i = #realm.history, 1, -1 do
		local snapshot = realm.history[i]
		local t = snapshot.meta.time
		if t < last and t <= latest then
			return snapshot
		end
	end
end

-- Preis eines Items im vorletzten Scan. Rueckgabe wie GetAuctionPrice, oder nil.
function ns.GetPreviousPrice(itemID)
	local snapshot = ns.PreviousSnapshot()
	local entry = snapshot and snapshot.items[itemID]
	local price = entry and ParseHistoryEntry(entry)
	if price then
		return price, snapshot.meta.time
	end
end

-- Richtung und Staerke einer Aenderung: 2/1 gestiegen, -1/-2 gefallen, 0 unveraendert.
-- Relativ zum Betrag des alten Werts, damit es auch fuer Margen um null oder darunter taugt.
function ns.PriceTrend(now, before)
	if not now or not before then
		return 0
	end
	local s = ns.db.settings
	local diff = now - before
	if math.abs(diff) < s.trendMinCopper then
		return 0
	end
	local change = before ~= 0 and math.abs(diff) / math.abs(before) * 100 or math.huge
	local level = 0
	if change >= math.max(s.trendLarge, s.trendSignificant) then
		level = 2
	elseif change >= s.trendSignificant then
		level = 1
	end
	return diff < 0 and -level or level
end

-- Preisverlauf eines Items fuer den Graphen: Liste { time, value } aus allen Scans, in denen es einen
-- Sofortkaufpreis hatte, aelteste zuerst. field: "top5" oder "min"; since: nur Scans ab diesem Zeitpunkt.
function ns.GetPriceSeries(itemID, field, since)
	local points = {}
	for _, snapshot in ipairs(ns.RealmData().history) do
		local t = snapshot.meta.time
		local entry = (not since or t >= since) and snapshot.items[itemID]
		local price = entry and ParseHistoryEntry(entry)
		if price and price[field] and price[field] > 0 then
			points[#points + 1] = { time = t, value = price[field] }
		end
	end
	return points
end

-- Alle Items, die in mindestens einem Scan des Verlaufs einen Sofortkaufpreis hatten (itemID -> true).
-- Bleibt gleich (dieselbe Tabelle), bis ein neuer Scan dazukommt oder das Auktionshaus wechselt.
local historyItems = {}

function ns.HistoryItemIDs()
	local history = ns.RealmData().history
	local last = history[#history]
	local key = ("%s:%d:%d"):format(ns.RealmKey(), #history, last and last.meta.time or 0)
	if historyItems.key ~= key then
		local ids = {}
		for _, snapshot in ipairs(history) do
			for itemID, entry in pairs(snapshot.items) do
				-- "0:..." = kein Sofortkaufpreis in diesem Scan
				if not ids[itemID] and entry:sub(1, 2) ~= "0:" then
					ids[itemID] = true
				end
			end
		end
		historyItems.key, historyItems.ids = key, ids
	end
	return historyItems.ids
end
