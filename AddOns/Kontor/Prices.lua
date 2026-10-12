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
