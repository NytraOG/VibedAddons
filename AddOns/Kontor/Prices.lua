local _, ns = ...

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
		if entry then
			local top5, minimum, quantity, auctions = entry:match("^(%d+):(%d+):(%d+):(%d+)$")
			top5 = tonumber(top5)
			if top5 and top5 > 0 then
				return { top5 = top5, min = tonumber(minimum), quantity = tonumber(quantity), auctions = tonumber(auctions) },
					history[i].meta.time
			end
		end
	end
end
