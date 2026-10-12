local _, ns = ...

-- Margen-Aufstellung im Tooltip:
--  * beim Hovern eines Rezepts in der Rezeptliste des Berufe-Fensters
--  * beim Hovern des Ergebnis-Items im Rezept-Detail

local GOLD = { 0.9, 0.69, 0.29 }
local GREY = { 0.6, 0.6, 0.6 }
local SOURCE_LABEL = {
	ah = "|cff9d9d9dAH|r",
	vendor = "|cff9d9d9dHändler|r",
	craft = "|cff66ccffHerstellen|r",
}

local function Percent(value)
	return ("%+.0f %%"):format(value)
end

local function QuantityText(recipe)
	if recipe.qmin == recipe.qmax then
		return tostring(recipe.qmin)
	end
	return ("%d–%d"):format(recipe.qmin, recipe.qmax)
end

-- Rechte Spalte nur Betraege (spaltenbuendig); Bezugsquelle steht links hinter dem Namen
local function AddPartLines(tooltip, parts, multiplier, indent, ctx)
	for _, part in ipairs(parts) do
		local qty = part.qty * multiplier
		local qtyText = qty % 1 == 0 and tostring(qty) or ("%.1f"):format(qty)
		local left = ("%s%sx %s"):format(indent, qtyText, ns.ItemName(part.itemID))
		local info = part.info
		if info.cost then
			local trend = ns.MaterialTrend(ctx, part.itemID, qty)
			tooltip:AddDoubleLine(left .. "  " .. SOURCE_LABEL[info.source],
				ns.TrendMarkup(trend) .. ns.MoneyAligned(info.cost * qty), 1, 1, 1, 1, 1, 1)
			if info.source == "craft" then
				if info.buy then
					tooltip:AddLine(("%s    statt kaufen: %s (%s)"):format(indent, ns.Money(info.buy * qty),
						info.buySource == "vendor" and "Händler" or "AH"), GREY[1], GREY[2], GREY[3])
				end
				-- Zwischenprodukt: Basismaterialien eine Ebene tiefer anzeigen
				local perCraft = qty / ((info.recipe.qmin + info.recipe.qmax) / 2)
				AddPartLines(tooltip, info.parts, perCraft, indent .. "    ", ctx)
			end
		else
			tooltip:AddDoubleLine(left, "|cffff6060kein Preis|r", 1, 1, 1)
		end
	end
end

function ns.AddMarginLines(tooltip, recipe, ctx)
	local m = ns.RecipeMargin(recipe, ctx)
	tooltip:AddLine(" ")
	tooltip:AddLine("Kontor – Marge", GOLD[1], GOLD[2], GOLD[3])
	AddPartLines(tooltip, m.parts, 1, "", ctx)
	tooltip:AddDoubleLine("Materialkosten", m.complete and (ns.TrendMarkup(m.costTrend) .. ns.MoneyAligned(m.cost)) or "unvollständig",
		GREY[1], GREY[2], GREY[3], 1, 1, 1)

	if not m.unitPrice then
		tooltip:AddLine("Ergebnis nie im AH gesehen: kein Verkaufswert.", 1, 0.4, 0.4, true)
		return
	end
	tooltip:AddDoubleLine(("Verkauf: %s x %s (AH Ø%s)"):format(QuantityText(recipe), ns.Money(m.unitPrice), m.priceStale and " zuletzt" or ""),
		ns.MoneyAligned(m.value), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	if m.priceStale then
		tooltip:AddDoubleLine("Aktuell nicht im AH", "gesehen " .. ns.Ago(m.priceTime), 1, 0.65, 0.25, 1, 0.65, 0.25)
	end
	tooltip:AddDoubleLine(("AH-Gebühr %.1f %%%s"):format(m.cutRate * 100, m.cutMeasured and "" or " (angenommen)"),
		ns.MoneyAligned(-m.cut), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	if m.margin then
		local r, g, b = 0.4, 1, 0.4
		if m.margin < 0 then
			r, g, b = 1, 0.4, 0.4
		end
		local left = "Netto-Marge"
		if m.percent then
			left = left .. " (" .. Percent(m.percent) .. ")"
		end
		tooltip:AddDoubleLine(left, ns.MoneyAligned(m.margin), GOLD[1], GOLD[2], GOLD[3], r, g, b)
	else
		tooltip:AddLine("Marge nicht berechenbar: Für mindestens ein Material fehlt ein Preis.", 1, 0.4, 0.4, true)
	end
end

local function CurrentContext()
	return ns.CraftContext(ns.CharacterKey(), ns.CurrentProfessionName())
end

-- Rezeptliste: Blizzard loest beim Hovern ein eigenes Event aus (zeigt sonst nur bei
-- abgeschnittenem Namen einen Tooltip)
EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", function(_, button, data)
	local info = data and data.recipeInfo
	if not info or not ns.db then
		return
	end
	if Professions and Professions.GetHighestLearnedRecipe then
		info = Professions.GetHighestLearnedRecipe(info) or info
	end
	local ok, err = pcall(function()
		local recipe = ns.RecipeFromSchematic(info.recipeID)
		if not recipe then
			return
		end
		if not (GameTooltip:IsShown() and GameTooltip:IsOwned(button.Label)) then
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip:AddLine(recipe.name, 1, 1, 1)
		end
		ns.AddMarginLines(GameTooltip, recipe, CurrentContext())
		GameTooltip:Show()
	end)
	if not ok then
		ns.Print("Margen-Tooltip fehlgeschlagen: %s", tostring(err))
	end
end, ns)

-- Ergebnis-Item im Rezept-Detail (Blizzard aktualisiert diesen Tooltip jeden Frame)
function ns.AddRecipeResultLines(tooltip)
	local info = tooltip.processingInfo
	if not info or info.getterName ~= "GetRecipeResultItem" or not info.getterArgs then
		return
	end
	local recipe = ns.RecipeFromSchematic(info.getterArgs[1])
	if recipe then
		ns.AddMarginLines(tooltip, recipe, CurrentContext())
	end
end
