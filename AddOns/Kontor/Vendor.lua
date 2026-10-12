local _, ns = ...

-- Haendler-Einkaufspreise. Die API liefert sie nur bei offenem Haendlerfenster, daher merkt sich
-- Kontor bei jedem Besuch alle Preise (Kupfer pro Stueck, guenstigster je gesehener Preis,
-- z.B. mit Rufrabatt). Gilt fuer alle Realms.

local function VendorDB()
	ns.db.vendor = ns.db.vendor or {}
	return ns.db.vendor
end

local function ScanMerchant()
	local vendor = VendorDB()
	local learned = 0
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		local info = C_MerchantFrame.GetItemInfo(index)
		-- Waren gegen Marken/Ruf (extendedCost) haben keinen reinen Goldpreis
		if itemID and info and info.price and info.price > 0 and not info.hasExtendedCost then
			local unit = info.price / math.max(1, info.stackCount or 1)
			local known = vendor[itemID]
			if not known or unit < known.price then
				learned = learned + (known and 0 or 1)
				vendor[itemID] = { price = unit, limited = info.numAvailable ~= -1, seen = time() }
			else
				known.seen = time()
			end
		end
	end
	if learned > 0 then
		ns.Print("%d neue Händlerpreise gemerkt.", learned)
	end
end

local function SafeScan()
	local ok, err = pcall(ScanMerchant)
	if not ok then
		ns.Print("Händlerpreise konnten nicht gelesen werden: %s", tostring(err))
	end
end

ns.On("MERCHANT_SHOW", SafeScan)
ns.On("MERCHANT_UPDATE", SafeScan)

-- Kupfer pro Stueck oder nil
function ns.GetVendorPrice(itemID)
	local known = ns.db and ns.db.vendor and ns.db.vendor[itemID]
	return known and known.price
end
