local _, ns = ...

-- Finanz-Journal: Verkaeufe, abgelaufene und abgebrochene Auktionen, Kaeufe.
--
-- Quellen:
--  * Einstellen (Hooks auf PostItem/PostCommodity + AUCTION_HOUSE_AUCTION_CREATED): merkt sich Preis,
--    Menge und Einstellgebuehr jeder eigenen Auktion unter ihrer auctionID.
--  * AH-Benachrichtigungen (online): exakter Zeitpunkt fuer verkauft / abgelaufen / ersteigert.
--  * Abbrechen (AUCTION_CANCELED): exakter Zeitpunkt, Gebuehr.
--  * Kaeufe (PlaceBid / Commodity-Kauf): exakter Zeitpunkt und Preis.
--  * Post (beim Entnehmen): Rechnung mit Kaeufer/Verkaeufer, Preis, Menge, AH-Gebuehr. Ergaenzt den
--    passenden Online-Eintrag oder legt einen neuen an (Zeitpunkt dann aus der Post-Restlaufzeit geschaetzt).
--
-- Eintrag: { t = "sale"|"expired"|"cancelled"|"purchase", time, exact, itemID, name, link, count,
--            price (gesamt), deposit, cut, cancelFee, net, party (Kaeufer/Verkaeufer), character,
--            auctionID, awaitingMail, mailRemaining }

local MAIL_RETENTION_DAYS = 30 -- AH-Post laeuft nach 30 Tagen ab; daraus wird die Ankunftszeit geschaetzt
local POSTED_MAX_AGE = 3 * 86400
local POST_MATCH_WINDOW = 30
local MAIL_SEEN_TOLERANCE = 120

-- Hook, der bei fehlender Funktion nur warnt statt die ganze Datei abzubrechen
local function Hook(target, name, fn)
	local ok, err
	if fn then
		ok, err = pcall(hooksecurefunc, target, name, fn)
	else
		ok, err = pcall(hooksecurefunc, target, name)
	end
	if not ok then
		ns.Print("Hook %s nicht möglich: %s", tostring(fn and name or target), tostring(err))
	end
end

local notify = function()
	if ns.OnJournalChanged then
		ns.OnJournalChanged()
	end
end

local function AddEntry(entry)
	entry.character = entry.character or UnitName("player")
	table.insert(ns.RealmData().journal, entry)
	notify()
	return entry
end

local function ComputeNet(e)
	if e.t == "sale" then
		e.net = e.price and (e.price - (e.cut or 0)) or nil
	elseif e.t == "expired" then
		e.net = -(e.deposit or 0)
	elseif e.t == "cancelled" then
		e.net = -((e.deposit or 0) + (e.cancelFee or 0))
	elseif e.t == "purchase" then
		e.net = e.price and -e.price or nil
	end
end

local function ResolveItemByName(name)
	local realm = ns.RealmData()
	for _, post in pairs(realm.posted) do
		if post.name == name then
			return post.itemID, post.link
		end
	end
	for i = #realm.journal, 1, -1 do
		local e = realm.journal[i]
		if e.name == name and e.itemID then
			return e.itemID, e.link
		end
	end
	local itemID = C_Item.GetItemIDForItemInfo(name)
	if itemID then
		return itemID, (select(2, C_Item.GetItemInfo(itemID)))
	end
end

-- ---- Einstellen -------------------------------------------------------------

local lastPost

local function CapturePost(isCommodity, itemLocation, duration, quantity, priceArg)
	local ok, err = pcall(function()
		if not itemLocation or not C_Item.DoesItemExist(itemLocation) then
			return
		end
		local itemID = C_Item.GetItemID(itemLocation)
		local link = C_Item.GetItemLink(itemLocation)
		local name = C_Item.GetItemName(itemLocation)
		local deposit
		if isCommodity then
			deposit = C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity)
		else
			deposit = C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity)
		end
		local count, price, auctions
		if isCommodity then
			count, price, auctions = quantity, (priceArg or 0) * quantity, 1
		else
			-- Nicht stapelbare Items: quantity = Anzahl einzelner Auktionen zum selben Preis
			local maxStack = C_Item.GetItemMaxStackSizeByID(itemID) or 1
			if maxStack == 1 and quantity > 1 then
				count, price, auctions = 1, priceArg, quantity
			else
				count, price, auctions = quantity, priceArg, 1
			end
		end
		lastPost = {
			itemID = itemID, link = link, name = name, count = count, price = price,
			deposit = deposit and math.floor(deposit / auctions + 0.5) or nil,
			duration = duration, commodity = isCommodity, time = time(),
		}
	end)
	if not ok then
		ns.Print("Einstellen konnte nicht erfasst werden: %s", tostring(err))
	end
end

Hook(C_AuctionHouse, "PostItem", function(item, duration, quantity, bid, buyout)
	CapturePost(false, item, duration, quantity, buyout)
end)
Hook(C_AuctionHouse, "ConfirmPostItem", function(item, duration, quantity, bid, buyout)
	CapturePost(false, item, duration, quantity, buyout)
end)
Hook(C_AuctionHouse, "PostCommodity", function(item, duration, quantity, unitPrice)
	CapturePost(true, item, duration, quantity, unitPrice)
end)
Hook(C_AuctionHouse, "ConfirmPostCommodity", function(item, duration, quantity, unitPrice)
	CapturePost(true, item, duration, quantity, unitPrice)
end)

ns.On("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
	if not lastPost or time() - lastPost.time > POST_MATCH_WINDOW then
		return
	end
	local post = CopyTable(lastPost)
	post.time = time()
	post.character = UnitName("player")
	ns.RealmData().posted[auctionID] = post
end)

-- ---- Abbrechen ---------------------------------------------------------------

-- AUCTION_CANCELED feuert fuer jede eigene Auktion, die aus der Liste verschwindet, also auch
-- wenn sie komplett verkauft wurde. Als "abgebrochen" zaehlt nur, was ueber CancelAuction lief.
local pendingCancels = {}

Hook(C_AuctionHouse, "CancelAuction", function(auctionID)
	local ok, fee = pcall(C_AuctionHouse.GetCancelCost, auctionID)
	pendingCancels[auctionID] = { fee = ok and fee or nil }
end)

ns.On("AUCTION_CANCELED", function(auctionID)
	local cancel = pendingCancels[auctionID]
	if not cancel then
		return
	end
	pendingCancels[auctionID] = nil
	local realm = ns.RealmData()
	local post = realm.posted[auctionID]
	if not post then
		return
	end
	realm.posted[auctionID] = nil
	local e = {
		t = "cancelled", time = time(), exact = true, auctionID = auctionID,
		itemID = post.itemID, name = post.name, link = post.link, count = post.count, price = post.price,
		deposit = post.deposit, cancelFee = cancel.fee or 0,
	}
	ComputeNet(e)
	AddEntry(e)
end)

-- ---- Kaeufe im Auktionshaus ------------------------------------------------------

local pendingBids = {}
local pendingCommodity

Hook(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
	local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
	pendingBids[auctionID] = {
		amount = bidAmount,
		itemID = info and info.itemKey and info.itemKey.itemID,
		link = info and info.itemLink,
	}
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
	local bid = pendingBids[auctionID]
	if not bid then
		return
	end
	pendingBids[auctionID] = nil
	local e = {
		t = "purchase", time = time(), exact = true, auctionID = auctionID,
		itemID = bid.itemID, link = bid.link, price = bid.amount, awaitingMail = true,
		name = bid.itemID and C_Item.GetItemNameByID(bid.itemID) or nil,
	}
	ComputeNet(e)
	AddEntry(e)
end)

Hook(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, quantity)
	pendingCommodity = { itemID = itemID, quantity = quantity }
end)

ns.On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
	if pendingCommodity then
		pendingCommodity.total = totalPrice
	end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
	pendingCommodity = nil
end)

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	local c = pendingCommodity
	pendingCommodity = nil
	if not c then
		return
	end
	local e = {
		t = "purchase", time = time(), exact = true, itemID = c.itemID, count = c.quantity, price = c.total,
		name = C_Item.GetItemNameByID(c.itemID), link = select(2, C_Item.GetItemInfo(c.itemID)),
		-- Commodity-Kaeufe kommen als mehrere Post-Rechnungen (eine je Verkaeufer)
		awaitingMail = true, mailRemaining = c.quantity, sellers = {},
	}
	ComputeNet(e)
	AddEntry(e)
end)

-- ---- AH-Benachrichtigungen (verkauft / abgelaufen / ersteigert) ------------------------

ns.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", function(notification, text, auctionID)
	local realm = ns.RealmData()
	local post = auctionID and realm.posted[auctionID]
	local N = Enum.AuctionHouseNotification
	local e
	if notification == N.AuctionSold then
		e = { t = "sale", awaitingMail = true }
		-- Commodities koennen teilweise verkauft werden: Auktion bleibt bis zum Ablauf bekannt
		if post and not post.commodity then
			realm.posted[auctionID] = nil
		end
	elseif notification == N.AuctionExpired then
		e = { t = "expired", awaitingMail = true }
		realm.posted[auctionID or 0] = nil
	elseif notification == N.AuctionWon then
		e = { t = "purchase", awaitingMail = true }
	else
		return
	end
	e.time, e.exact, e.auctionID, e.name = time(), true, auctionID, text
	if post then
		e.itemID, e.link, e.deposit = post.itemID, post.link, post.deposit
		-- Bei Commodities ist die verkaufte Menge erst aus der Post-Rechnung bekannt
		if not post.commodity then
			e.count, e.price = post.count, post.price
		end
	end
	if e.t == "purchase" and auctionID and pendingBids[auctionID] then
		e.price = pendingBids[auctionID].amount
		pendingBids[auctionID] = nil
	end
	ComputeNet(e)
	AddEntry(e)
end)

-- ---- Post ---------------------------------------------------------------------

local function SubjectPattern(format)
	return "^" .. format:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
end

local expiredPatterns = {}
for _, f in ipairs({ AUCTION_EXPIRED_MAIL_SUBJECT or false, "Auction expired: %s", "Auktion abgelaufen: %s" }) do
	if f then
		table.insert(expiredPatterns, SubjectPattern(f))
	end
end

local function MatchExpiredSubject(subject)
	for _, pattern in ipairs(expiredPatterns) do
		local name = subject:match(pattern)
		if name then
			return name
		end
	end
end

-- Dieselbe Post nicht doppelt verbuchen (z.B. wenn das Entnehmen fehlschlaegt und wiederholt wird).
-- Die geschaetzte Ankunftszeit ist stabil, solange die Post im Postfach liegt.
local function AlreadySeen(key, arrival)
	local realm = ns.RealmData()
	local list = realm.mailSeen[key]
	if list then
		for _, t in ipairs(list) do
			if math.abs(t - arrival) <= MAIL_SEEN_TOLERANCE then
				return true
			end
		end
	end
	realm.mailSeen[key] = list or {}
	table.insert(realm.mailSeen[key], arrival)
	return false
end

-- Offenen Online-Eintrag finden, der zu dieser Post passt (zeitlich naechster)
local function FindAwaiting(t, name, arrival, accept)
	local best, bestDiff
	for _, e in ipairs(ns.RealmData().journal) do
		if e.t == t and e.awaitingMail and e.name == name and (not accept or accept(e)) then
			local diff = math.abs(e.time - arrival)
			if not bestDiff or diff < bestDiff then
				best, bestDiff = e, diff
			end
		end
	end
	return best
end

local function RecordSale(name, buyer, bid, deposit, consignment, count, arrival)
	local e = FindAwaiting("sale", name, arrival)
	if not e then
		e = AddEntry({ t = "sale", time = arrival, exact = false, name = name })
		e.itemID, e.link = ResolveItemByName(name)
	end
	e.awaitingMail = nil
	e.party, e.price, e.count, e.deposit, e.cut = buyer, bid, count, deposit, consignment
	ComputeNet(e)
	-- Teilverkauf einer Commodity-Auktion: Restmenge fortschreiben, bei 0 vergessen
	local realm = ns.RealmData()
	local post = e.auctionID and realm.posted[e.auctionID]
	if post and post.commodity and count then
		post.count = post.count - count
		if post.count <= 0 then
			realm.posted[e.auctionID] = nil
		end
	end
end

local function RecordPurchase(name, seller, bid, count, arrival)
	local e = FindAwaiting("purchase", name, arrival, function(c)
		if c.mailRemaining then
			return c.mailRemaining >= (count or 0)
		end
		return not c.price or c.price == bid
	end)
	if e and e.mailRemaining then
		e.mailRemaining = e.mailRemaining - (count or 0)
		if seller and not tContains(e.sellers, seller) then
			table.insert(e.sellers, seller)
		end
		e.party = table.concat(e.sellers, ", ")
		if e.mailRemaining <= 0 then
			e.awaitingMail, e.mailRemaining = nil, nil
		end
		return
	end
	if not e then
		e = AddEntry({ t = "purchase", time = arrival, exact = false, name = name })
		e.itemID, e.link = ResolveItemByName(name)
	end
	e.awaitingMail = nil
	e.party, e.price, e.count = seller, bid, count
	ComputeNet(e)
end

local function RecordExpired(name, count, arrival)
	local e = FindAwaiting("expired", name, arrival)
	if e then
		e.awaitingMail = nil
		e.count = e.count or count
		return
	end
	-- Offline abgelaufen: Preis aus der gemerkten Auktion (aelteste passende) uebernehmen
	local realm = ns.RealmData()
	local postID, post
	for id, p in pairs(realm.posted) do
		if p.name == name and (not post or p.time < post.time) then
			postID, post = id, p
		end
	end
	e = { t = "expired", time = arrival, exact = false, name = name, count = count }
	if post then
		realm.posted[postID] = nil
		e.itemID, e.link, e.price, e.deposit, e.count = post.itemID, post.link, post.price, post.deposit, post.count
	else
		e.itemID, e.link = ResolveItemByName(name)
	end
	ComputeNet(e)
	AddEntry(e)
end

local function ProcessMail(index)
	local _, _, sender, subject, _, _, daysLeft, itemCount = GetInboxHeaderInfo(index)
	if not subject or not daysLeft then
		return
	end
	local arrival = time() - math.floor((MAIL_RETENTION_DAYS - daysLeft) * 86400 + 0.5)
	local invoiceType, itemName, playerName, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)

	if invoiceType == "seller" or invoiceType == "buyer" then
		local key = table.concat({ invoiceType, tostring(itemName), tostring(playerName), tostring(bid), tostring(count) }, "|")
		if AlreadySeen(key, arrival) then
			return
		end
		if invoiceType == "seller" then
			RecordSale(itemName, playerName, bid, deposit, consignment, count, arrival)
		else
			RecordPurchase(itemName, playerName, bid, count, arrival)
		end
		notify()
	elseif not invoiceType and itemCount and itemCount > 0 then
		local name = MatchExpiredSubject(subject)
		if not name then
			return
		end
		local _, _, _, stack = GetInboxItem(index, 1)
		if AlreadySeen("expired|" .. name .. "|" .. tostring(stack), arrival) then
			return
		end
		RecordExpired(name, stack, arrival)
		notify()
	end
end

local function SafeProcessMail(index)
	local ok, err = pcall(ProcessMail, index)
	if not ok then
		ns.Print("Post konnte nicht verbucht werden: %s", tostring(err))
	end
end

-- Post-Hooks laufen direkt nach dem Aufruf; die Post ist dann noch im Postfach lesbar
Hook("TakeInboxMoney", SafeProcessMail)
Hook("TakeInboxItem", SafeProcessMail)
Hook("AutoLootMailItem", SafeProcessMail)

-- ---- Aufraeumen -----------------------------------------------------------------

function ns.DeleteJournalEntry(entry)
	local journal = ns.RealmData().journal
	for i = #journal, 1, -1 do
		if journal[i] == entry then
			table.remove(journal, i)
			notify()
			return
		end
	end
end

-- Kontor 0.2.0 hat komplett verkaufte Auktionen faelschlich als "abgebrochen" verbucht.
-- Echte Abbrueche hatten immer eine Abbruchgebuehr (ggf. 0), die falschen nicht.
local function MigrateFalseCancels()
	if ns.db.migratedFalseCancels then
		return
	end
	local removed = 0
	for _, realm in pairs(ns.db.realms) do
		local journal = realm.journal or {}
		for i = #journal, 1, -1 do
			if journal[i].t == "cancelled" and journal[i].cancelFee == nil then
				table.remove(journal, i)
				removed = removed + 1
			end
		end
	end
	ns.db.migratedFalseCancels = true
	if removed > 0 then
		ns.Print("%d fälschlich als \"abgebrochen\" verbuchte Einträge entfernt.", removed)
	end
end

ns.On("PLAYER_LOGIN", function()
	MigrateFalseCancels()
	local realm = ns.RealmData()
	local now = time()
	for id, post in pairs(realm.posted) do
		if now - post.time > POSTED_MAX_AGE then
			realm.posted[id] = nil
		end
	end
	for key, list in pairs(realm.mailSeen) do
		for i = #list, 1, -1 do
			if now - list[i] > (MAIL_RETENTION_DAYS + 1) * 86400 then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			realm.mailSeen[key] = nil
		end
	end
end)
