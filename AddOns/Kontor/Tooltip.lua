local _, ns = ...

-- Item-Tooltips: AH-Preis aus dem letzten Scan (pro Stueck und fuer den ganzen Stapel),
-- Haendlerpreis und im Berufe-Fenster die Margen-Aufstellung am Ergebnis-Item.

local GREY = { 0.6, 0.6, 0.6 }
local GOLD = { 0.9, 0.69, 0.29 }

-- Stapelgroesse des angezeigten Items, abhaengig davon, woher der Tooltip kommt
local STACK_GETTERS = {
	GetBagItem = function(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount
	end,
	GetInboxItem = function(message, attachment)
		return (select(4, GetInboxItem(message, attachment or 1)))
	end,
	GetSendMailItem = function(attachment)
		return (select(4, GetSendMailItem(attachment or 1)))
	end,
	GetMerchantItem = function(slot)
		local info = C_MerchantFrame.GetItemInfo(slot)
		return info and info.stackCount
	end,
	GetLootItem = function(slot)
		return (select(3, GetLootSlotInfo(slot)))
	end,
	GetGuildBankItem = function(tab, slot)
		return (select(2, GetGuildBankItemInfo(tab, slot)))
	end,
	GetTradePlayerItem = function(slot)
		return (select(3, GetTradePlayerItemInfo(slot)))
	end,
	GetTradeTargetItem = function(slot)
		return (select(3, GetTradeTargetItemInfo(slot)))
	end,
}

local function StackCount(tooltip)
	local info = tooltip.processingInfo
	local getter = info and STACK_GETTERS[info.getterName]
	if not getter then
		return 1
	end
	local ok, count = pcall(getter, unpack(info.getterArgs or {}))
	count = ok and ns.SafeID(count)
	return (type(count) == "number" and count > 1) and count or 1
end

local function AddPriceLines(tooltip, itemID)
	local price, scanTime = ns.GetAuctionPrice(itemID)
	local vendor = ns.GetVendorPrice(itemID)
	local lastKnown, lastTime
	if not price then
		lastKnown, lastTime = ns.GetLastKnownPrice(itemID)
	end
	if not price and not vendor and not lastKnown then
		return
	end
	local count = StackCount(tooltip)

	if lastKnown then
		tooltip:AddDoubleLine("AH Ø (zuletzt)", ns.MoneyAligned(lastKnown.top5), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
		if count > 1 then
			tooltip:AddDoubleLine(("AH Ø für %d Stück"):format(count), ns.MoneyAligned(lastKnown.top5 * count), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
		end
		tooltip:AddDoubleLine("Aktuell nicht im AH", "gesehen " .. ns.Ago(lastTime), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
	elseif price then
		if price.top5 then
			-- Pfeil: Aenderung gegenueber dem vorletzten Scan
			local previous = ns.GetPreviousPrice(itemID)
			local trend = ns.TrendMarkup(previous and ns.PriceTrend(price.top5, previous.top5))
			tooltip:AddDoubleLine("AH Ø", trend .. ns.MoneyAligned(price.top5), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
			if count > 1 then
				tooltip:AddDoubleLine(("AH Ø für %d Stück"):format(count), ns.MoneyAligned(price.top5 * count), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
			end
		else
			tooltip:AddDoubleLine("AH", "nur Gebote, kein Sofortkauf", GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
		end
		tooltip:AddDoubleLine(("%d Angebote · %d Stück"):format(price.auctions, price.quantity), "Scan " .. ns.Ago(scanTime),
			GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
	end
	if vendor then
		tooltip:AddDoubleLine("Händler-Einkauf", ns.MoneyAligned(vendor), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
		if count > 1 then
			tooltip:AddDoubleLine(("Händler für %d Stück"):format(count), ns.MoneyAligned(vendor * count), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
		end
	end
end

local function OnTooltipSetItem(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local itemID = data and ns.SafeID(data.id)
	if not itemID or not ns.db then
		return
	end
	-- Der Client meldet dasselbe Item manchmal zweimal fuer einen Tooltip
	if tooltip.kontorItemID == itemID then
		return
	end
	tooltip.kontorItemID = itemID
	AddPriceLines(tooltip, itemID)
	local ok, err = pcall(ns.AddRecipeResultLines, tooltip)
	if not ok then
		ns.Print("Margen-Tooltip fehlgeschlagen: %s", tostring(err))
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
	tooltip:HookScript("OnTooltipCleared", function(self)
		self.kontorItemID = nil
	end)
end
