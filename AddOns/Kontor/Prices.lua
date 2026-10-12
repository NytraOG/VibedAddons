local _, ns = ...

-- Schwellen fuer Preis-Pfeile (Aenderung gegenueber dem vorletzten Scan). Annahme, abgeleitet aus den
-- eigenen Scans (Abstand ca. 20 Min.): Bei Materialien schwankt der Ø der 5 guenstigsten Angebote bei
-- rund 30 % der Items um 5 % oder mehr (Rauschen), bei 10-20 % um 10 % oder mehr, kaum je um 25 %.
local TREND_SIGNIFICANT = 0.10 -- ein Pfeil
local TREND_LARGE = 0.25 -- zwei Pfeile
local TREND_MIN_COPPER = 10 -- kleinere Aenderungen zaehlen nie (z.B. 5 auf 7 Kupfer)

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

-- Der Scan vor dem letzten: Vergleichsbasis fuer die Preis-Pfeile. nil, wenn es keinen gibt.
function ns.PreviousSnapshot()
	local realm = ns.RealmData()
	local last = realm.lastScan and realm.lastScan.meta.time
	if not last then
		return nil
	end
	for i = #realm.history, 1, -1 do
		local snapshot = realm.history[i]
		if snapshot.meta.time < last then
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
	local diff = now - before
	if math.abs(diff) < TREND_MIN_COPPER then
		return 0
	end
	local change = before ~= 0 and math.abs(diff) / math.abs(before) or math.huge
	local level = 0
	if change >= TREND_LARGE then
		level = 2
	elseif change >= TREND_SIGNIFICANT then
		level = 1
	end
	return diff < 0 and -level or level
end
