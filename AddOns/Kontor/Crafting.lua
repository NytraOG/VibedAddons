local _, ns = ...

-- Herstellkosten und Marge.
--
-- Kosten eines Materials = guenstigste Variante aus
--   * AH (Durchschnitt der 5 guenstigsten Angebote aus dem letzten Scan)
--   * Haendler (gemerkter Einkaufspreis)
--   * selbst herstellen mit einem Rezept desselben Berufs desselben Charakters, rekursiv
--     (z.B. Bolt of Silk Cloth aus Silk Cloth)
-- Marge = AH-Wert des Ergebnisses * Menge, abzueglich AH-Gebuehr, minus Materialkosten.
-- Die Einstellgebuehr zaehlt nicht, weil sie bei Verkauf zurueckkommt.

local MAX_DEPTH = 6
local DEFAULT_CUT_RATE = 0.05

-- ctx = { character, profession, memo = {}, visiting = {}, auctionPrice = fn, prev = ctx|nil }
-- prev rechnet dasselbe mit den Preisen des vorletzten Scans (fuer die Preis-Pfeile).
local function NewContext(character, profession, auctionPrice)
	return { character = character, profession = profession, memo = {}, visiting = {}, auctionPrice = auctionPrice }
end

function ns.CraftContext(character, profession)
	local ctx = NewContext(character, profession, ns.GetAuctionPrice)
	if ns.PreviousSnapshot() then
		ctx.prev = NewContext(character, profession, ns.GetPreviousPrice)
	end
	return ctx
end

local function BuyPrice(itemID, ctx)
	local best, source
	local ah = ctx.auctionPrice(itemID)
	if ah and ah.top5 then
		best, source = ah.top5, "ah"
	end
	local vendor = ns.GetVendorPrice(itemID)
	if vendor and (not best or vendor < best) then
		best, source = vendor, "vendor"
	end
	return best, source
end

local function AverageQuantity(recipe)
	return ((recipe.qmin or 1) + (recipe.qmax or recipe.qmin or 1)) / 2
end

local RecipeCost

-- Kosten pro Stueck: { cost, source = "ah"|"vendor"|"craft"|nil, buy, buySource, craft, recipe, parts }
local function ItemCost(itemID, ctx, depth)
	local cached = ctx.memo[itemID]
	if cached then
		return cached
	end
	local result = {}
	result.buy, result.buySource = BuyPrice(itemID, ctx)

	if depth < MAX_DEPTH and not ctx.visiting[itemID] and ctx.character and ctx.profession then
		ctx.visiting[itemID] = true
		local producers = ns.RecipesProducing(ctx.character, ctx.profession)[itemID]
		for _, recipe in ipairs(producers or {}) do
			local total, parts, complete = RecipeCost(recipe, ctx, depth + 1)
			if complete then
				local perUnit = total / AverageQuantity(recipe)
				if not result.craft or perUnit < result.craft then
					result.craft, result.recipe, result.parts = perUnit, recipe, parts
				end
			end
		end
		ctx.visiting[itemID] = nil
	end

	if result.craft and (not result.buy or result.craft < result.buy) then
		result.cost, result.source = result.craft, "craft"
	elseif result.buy then
		result.cost, result.source = result.buy, result.buySource
	end
	ctx.memo[itemID] = result
	return result
end

-- Materialkosten eines Rezepts. Rueckgabe: Summe, Teile { itemID, qty, info }, vollstaendig?
RecipeCost = function(recipe, ctx, depth)
	local total, parts, complete = 0, {}, true
	for _, reagent in ipairs(recipe.reagents) do
		local info = ItemCost(reagent.itemID, ctx, depth)
		parts[#parts + 1] = { itemID = reagent.itemID, qty = reagent.qty, info = info }
		if info.cost then
			total = total + info.cost * reagent.qty
		else
			complete = false
		end
	end
	return total, parts, complete
end

-- AH-Gebuehr aus den eigenen Verkaeufen ablesen (Postrechnungen), sonst 5 %
function ns.AuctionCutRate()
	local cut, gross = 0, 0
	for _, e in ipairs(ns.RealmData().journal) do
		if e.t == "sale" and e.cut and e.price and e.price > 0 then
			cut, gross = cut + e.cut, gross + e.price
		end
	end
	if gross > 0 then
		return cut / gross, true
	end
	return DEFAULT_CUT_RATE, false
end

-- Vollstaendige Margenrechnung fuer ein Rezept
function ns.RecipeMargin(recipe, ctx)
	local cost, parts, complete = RecipeCost(recipe, ctx, 0)
	local m = { recipe = recipe, cost = cost, parts = parts, complete = complete, quantity = AverageQuantity(recipe) }
	if ctx.prev then
		local prevCost, _, prevComplete = RecipeCost(recipe, ctx.prev, 0)
		if complete and prevComplete then
			m.costTrend = ns.PriceTrend(cost, prevCost)
		end
	end
	local ah = ns.GetAuctionPrice(recipe.out)
	m.unitPrice = ah and ah.top5
	if not m.unitPrice then
		-- Ergebnis gerade ausverkauft: zuletzt bekannten Preis nehmen (keine Konkurrenz im AH)
		local last, lastTime = ns.GetLastKnownPrice(recipe.out)
		if last then
			m.unitPrice, m.priceStale, m.priceTime = last.top5, true, lastTime
		end
	end
	m.cutRate, m.cutMeasured = ns.AuctionCutRate()
	if m.unitPrice then
		m.value = m.unitPrice * m.quantity
		m.cut = m.value * m.cutRate
		m.net = m.value - m.cut
		if complete then
			m.margin = m.net - cost
			m.percent = cost > 0 and m.margin / cost * 100 or nil
		end
	end
	return m
end

-- Pfeil fuer qty Stueck eines Materials (nach ns.RecipeMargin mit demselben ctx)
function ns.MaterialTrend(ctx, itemID, qty)
	local now, before = ctx.memo[itemID], ctx.prev and ctx.prev.memo[itemID]
	if now and now.cost and before and before.cost then
		return ns.PriceTrend(now.cost * qty, before.cost * qty)
	end
	return 0
end

function ns.ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		return "Item #" .. itemID
	end
	return name
end
