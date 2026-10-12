local _, ns = ...

-- Margen-Liste: alle erfassten Rezepte aller Charaktere, absteigend nach Marge.
-- Filter nach Beruf, Sortierung umschaltbar zwischen absoluter und relativer Marge.

local frame
local filter = { profession = nil, sort = "margin" }

local SORTS = {
	margin = { label = "Sortierung: Marge absolut", next = "percent" },
	percent = { label = "Sortierung: Marge in %", next = "margin" },
}

local function ColorMargin(value)
	if not value then
		return 0.6, 0.6, 0.6
	elseif value < 0 then
		return 1, 0.4, 0.4
	end
	return 0.4, 1, 0.4
end

local COLUMNS = {
	{ key = "item", title = "Ergebnis",
		text = function(r) return r.link or r.name end,
		sort = function(r) return r.name end },
	{ key = "profession", title = "Beruf", width = 110,
		text = function(r) return r.profession end,
		sort = function(r) return r.profession end },
	{ key = "character", title = "Charakter", width = 95,
		text = function(r) return r.characterName end,
		sort = function(r) return r.characterName end },
	-- Pfeile: Materialkosten gegenueber dem vorletzten Scan gestiegen (rot) oder gefallen (gruen)
	{ key = "cost", title = "Material", width = 115, defaultDesc = true,
		money = function(r) return r.m.cost end,
		trend = function(r) return r.m.costTrend end },
	{ key = "net", title = "Erlös netto", width = 100, defaultDesc = true,
		money = function(r) return r.m.net end },
	{ key = "margin", title = "Marge", width = 100, defaultDesc = true,
		money = function(r) return r.m.margin end,
		color = function(r) return ColorMargin(r.m.margin) end },
	{ key = "percent", title = "Marge %", width = 70, align = "RIGHT", defaultDesc = true,
		text = function(r) return r.m.percent and ("%+.0f %%"):format(r.m.percent) or "" end,
		color = function(r) return ColorMargin(r.m.margin) end,
		sort = function(r) return r.m.percent end },
	{ key = "supply", title = "Im AH", width = 60, align = "RIGHT", defaultDesc = true,
		text = function(r) return r.supply and tostring(r.supply) or "0" end,
		-- Orange: ausverkauft, Marge basiert auf dem zuletzt bekannten Preis
		color = function(r)
			if r.m.priceStale then
				return 1, 0.65, 0.25
			end
			return 1, 1, 1
		end,
		sort = function(r) return r.supply or 0 end },
}

local function ProfessionOptions()
	local options, seen = { { label = "Alle Berufe", value = false } }, {}
	for _, p in ipairs(ns.AllProfessions()) do
		if not seen[p.profession] then
			seen[p.profession] = true
			options[#options + 1] = { label = p.profession, value = p.profession }
		end
	end
	table.sort(options, function(a, b)
		if a.value == false then
			return true
		elseif b.value == false then
			return false
		end
		return a.label < b.label
	end)
	return options
end

-- Eine Zeile pro Charakter/Beruf/Ergebnis-Item (bei mehreren Raengen das beste Rezept)
local function BuildRows()
	local rows, incomplete = {}, 0
	for _, p in ipairs(ns.AllProfessions()) do
		if not filter.profession or filter.profession == p.profession then
			local ctx = ns.CraftContext(p.character, p.profession)
			local best = {}
			for _, recipe in pairs(p.recipes) do
				local m = ns.RecipeMargin(recipe, ctx)
				if m.margin then
					local current = best[recipe.out]
					if not current or m.margin > current.margin then
						best[recipe.out] = m
					end
				else
					incomplete = incomplete + 1
				end
			end
			for itemID, m in pairs(best) do
				local ah = ns.GetAuctionPrice(itemID)
				rows[#rows + 1] = {
					m = m,
					name = ns.ItemName(itemID),
					link = select(2, C_Item.GetItemInfo(itemID)),
					profession = p.profession,
					character = p.character,
					characterName = p.character:match("^[^-]+"),
					supply = ah and ah.auctions,
					itemID = itemID,
				}
			end
		end
	end
	return rows, incomplete
end

local function Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local rows, incomplete = BuildRows()
	frame.table:SetRows(rows)
	frame.sortButton:SetText(SORTS[filter.sort].label)

	local realm = ns.RealmData()
	local cutRate, measured = ns.AuctionCutRate()
	local parts = { ("%d Rezepte"):format(#rows) }
	if incomplete > 0 then
		parts[#parts + 1] = ("%d ohne vollständige Preise ausgeblendet"):format(incomplete)
	end
	parts[#parts + 1] = "Preise: Scan " .. (realm.lastScan and ns.Ago(realm.lastScan.meta.time) or "fehlt")
	parts[#parts + 1] = ("AH-Gebühr %.1f %%%s"):format(cutRate * 100, measured and "" or " (angenommen)")
	frame.footer:SetText(table.concat(parts, "   ·   "))

	local empty
	if not next(ns.db.characters or {}) then
		empty = "Noch keine Rezepte erfasst. Öffne einmal das Berufe-Fenster jedes Berufs."
	elseif #rows == 0 then
		empty = "Keine Rezepte mit vollständigen Preisen. Ein AH-Scan und ein Händlerbesuch helfen."
	end
	frame.empty:SetText(empty or "")
	frame.empty:SetShown(empty ~= nil)
end

ns.OnRecipesChanged = Refresh
ns.OnPricesChanged = Refresh

-- Item-Namen/-Links werden asynchron nachgeladen: dann einmal gesammelt neu zeichnen
local refreshPending = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
	if refreshPending or not frame or not frame:IsShown() then
		return
	end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = false
		Refresh()
	end)
end)

local function ShowRowTooltip(rowFrame, r)
	GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(r.itemID)
	ns.AddMarginLines(GameTooltip, r.m.recipe, ns.CraftContext(r.character, r.profession))
	GameTooltip:Show()
end

local function CreateMarginFrame()
	frame = ns.CreateWindow("KontorMarginFrame", "Kontor – Margen", 960, 540)
	frame:SetScript("OnShow", Refresh)

	local professionDropdown = ns.CreateDropdown(frame, 170, ProfessionOptions,
		function(value) return (filter.profession or false) == value end,
		function(value) filter.profession = value or nil; Refresh() end)
	professionDropdown:SetPoint("TOPLEFT", 14, -32)

	frame.sortButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.sortButton:SetSize(200, 22)
	frame.sortButton:SetPoint("LEFT", professionDropdown, "RIGHT", 12, 0)
	frame.sortButton:SetScript("OnClick", function()
		frame.table:SetSort(SORTS[filter.sort].next, true)
	end)

	frame.table = ns.CreateTable(frame, COLUMNS, {
		sortKey = filter.sort,
		sortDesc = true,
		onEnter = ShowRowTooltip,
		-- Klick auf die Spaltenkoepfe "Marge"/"Marge %" haelt den Umschalter synchron
		onSortChanged = function(key)
			if SORTS[key] then
				filter.sort = key
				frame.sortButton:SetText(SORTS[key].label)
			end
		end,
	})
	frame.table:SetPoint("TOPLEFT", 14, -64)
	frame.table:SetPoint("BOTTOMRIGHT", -12, 34)

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.table, "CENTER")

	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.footer:SetPoint("BOTTOMLEFT", 16, 12)
	frame.footer:SetPoint("BOTTOMRIGHT", -16, 12)
	frame.footer:SetJustifyH("LEFT")
end

function ns.ToggleMargins()
	if not frame then
		CreateMarginFrame()
	end
	frame:SetShown(not frame:IsShown())
end

ns.commands.margen = ns.ToggleMargins
