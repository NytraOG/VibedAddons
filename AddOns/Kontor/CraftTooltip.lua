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
			ns.AddMoneyLine(tooltip, left .. "  " .. SOURCE_LABEL[info.source], info.cost * qty,
				{ trend = ns.MaterialTrend(ctx, part.itemID, qty) })
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
	if m.complete then
		ns.AddMoneyLine(tooltip, "Materialkosten", m.cost, { leftColor = GREY, trend = m.costTrend })
	else
		tooltip:AddDoubleLine("Materialkosten", "unvollständig", GREY[1], GREY[2], GREY[3], 1, 1, 1)
	end

	if not m.unitPrice then
		tooltip:AddLine("Ergebnis nie im AH gesehen: kein Verkaufswert.", 1, 0.4, 0.4, true)
		return
	end
	ns.AddMoneyLine(tooltip, ("Verkauf: %s x %s (AH Ø%s)"):format(QuantityText(recipe), ns.Money(m.unitPrice), m.priceStale and " zuletzt" or ""),
		m.value, { leftColor = GREY, trend = m.netTrend, upIsGood = true })
	if m.priceStale then
		tooltip:AddDoubleLine("Aktuell nicht im AH", "gesehen " .. ns.Ago(m.priceTime), 1, 0.65, 0.25, 1, 0.65, 0.25)
	end
	ns.AddMoneyLine(tooltip, ("AH-Gebühr %.1f %%%s"):format(m.cutRate * 100, m.cutMeasured and "" or " (angenommen)"),
		-m.cut, { leftColor = GREY })
	if m.margin then
		local color = m.margin < 0 and { 1, 0.4, 0.4 } or { 0.4, 1, 0.4 }
		local left = "Netto-Marge"
		if m.percent then
			left = left .. " (" .. Percent(m.percent) .. ")"
		end
		ns.AddMoneyLine(tooltip, left, m.margin, { leftColor = GOLD, color = color, trend = m.marginTrend, upIsGood = true })
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
	if not info or not ns.db or not ns.db.settings.tooltipMargins then
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
		-- Neben das Berufe-Fenster statt mitten hinein
		local window = ProfessionsFrame
		if not (GameTooltip:IsShown() and GameTooltip:IsOwned(button.Label)) then
			ns.SetTooltipOwnerOutside(GameTooltip, button, window)
			GameTooltip:AddLine(recipe.name, 1, 1, 1)
		end
		ns.AddMarginLines(GameTooltip, recipe, CurrentContext())
		GameTooltip:Show()
		ns.PlaceTooltipOutside(GameTooltip, button, window)
	end)
	if not ok then
		ns.Print("Margen-Tooltip fehlgeschlagen: %s", tostring(err))
	end
end, ns)

-- Ergebnis-Item im Rezept-Detail (Blizzard aktualisiert diesen Tooltip jeden Frame)
function ns.AddRecipeResultLines(tooltip)
	local info = tooltip.processingInfo
	if not info or info.getterName ~= "GetRecipeResultItem" or not info.getterArgs or not ns.db.settings.tooltipMargins then
		return
	end
	local recipe = ns.RecipeFromSchematic(info.getterArgs[1])
	if recipe then
		ns.AddMarginLines(tooltip, recipe, CurrentContext())
	end
end
