local _, ns = ...

-- Beim Händler: graue Items verkaufen und reparieren.

-- Wartezeit, bis geprüft wird, ob die Gildenbank die Reparatur bezahlt hat (Annahme)
local GUILD_REPAIR_CHECK_SECONDS = 0.5

local POOR = Enum.ItemQuality.Poor

local function S()
	return ns.db.settings.vendor
end

local function Money(copper)
	return GetMoneyString(copper, true)
end

-- Alle grauen Items mit Händlerwert in den Taschen
local function FindJunk()
	local junk, total = {}, 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR and not info.hasNoValue and not info.isLocked then
				local sellPrice = select(11, C_Item.GetItemInfo(info.itemID)) or 0
				total = total + sellPrice * info.stackCount
				table.insert(junk, { bag = bag, slot = slot })
			end
		end
	end
	return junk, total
end

local function SellJunk()
	local junk, total = FindJunk()
	if #junk == 0 then
		return
	end
	if C_MerchantFrame.IsSellAllJunkEnabled() then
		C_MerchantFrame.SellAllJunkItems()
	else
		for _, item in ipairs(junk) do
			C_Container.UseContainerItem(item.bag, item.slot)
		end
	end
	ns.Print("Müll verkauft: %d × %s", #junk, Money(total))
end

local function RepairOwn()
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then
		return
	end
	if cost > GetMoney() then
		ns.Print("Zu wenig Gold zum Reparieren (%s).", Money(cost))
		return
	end
	RepairAllItems()
	ns.Print("Repariert: %s", Money(cost))
end

local function Repair()
	if not CanMerchantRepair() then
		return
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then
		return
	end
	if S().guildRepair and IsInGuild() and CanGuildBankRepair() then
		RepairAllItems(true)
		-- Ob das Gildenlimit gereicht hat, zeigt erst die nächste Kostenabfrage
		C_Timer.After(GUILD_REPAIR_CHECK_SECONDS, function()
			local rest = GetRepairAllCost()
			if rest == 0 then
				ns.Print("Repariert (Gilde): %s", Money(cost))
			elseif MerchantFrame:IsShown() then
				RepairOwn()
			end
		end)
		return
	end
	RepairOwn()
end

ns.On("MERCHANT_SHOW", function()
	if ns.Paused() then
		return
	end
	if S().repair then
		Repair()
	end
	if S().sellJunk then
		SellJunk()
	end
end)
