local _, ns = ...

local TYPES = {
	{ key = "sale", label = "Verkauft", color = { 0.4, 0.9, 0.4 } },
	{ key = "expired", label = "Abgelaufen", color = { 1, 0.65, 0.25 } },
	{ key = "cancelled", label = "Abgebrochen", color = { 0.75, 0.75, 0.75 } },
	{ key = "purchase", label = "Gekauft", color = { 0.45, 0.7, 1 } },
}
local TYPE_BY_KEY = {}
for _, t in ipairs(TYPES) do
	TYPE_BY_KEY[t.key] = t
end

local PERIODS = {
	{ label = "Gesamter Zeitraum", seconds = nil },
	{ label = "Letzte 24 Stunden", seconds = 86400 },
	{ label = "Letzte 7 Tage", seconds = 7 * 86400 },
	{ label = "Letzte 30 Tage", seconds = 30 * 86400 },
}

local frame
local filter = { type = nil, period = 1, search = "" }

local function Fees(e)
	if e.t == "sale" then
		return e.cut
	elseif e.t == "expired" then
		return e.deposit
	elseif e.t == "cancelled" then
		return (e.deposit or 0) + (e.cancelFee or 0)
	end
end

local COLUMNS = {
	{ key = "time", title = "Datum", width = 110, defaultDesc = true,
		text = function(e) return date("%d.%m.%y %H:%M", e.time) .. (e.exact and "" or " ~") end,
		sort = function(e) return e.time end },
	{ key = "type", title = "Typ", width = 80,
		text = function(e) return TYPE_BY_KEY[e.t].label end,
		color = function(e) return unpack(TYPE_BY_KEY[e.t].color) end },
	{ key = "item", title = "Item",
		text = function(e) return e.link or e.name or "?" end,
		sort = function(e) return e.name end },
	{ key = "count", title = "Menge", width = 50, align = "RIGHT", defaultDesc = true,
		text = function(e) return e.count and tostring(e.count) or "" end,
		sort = function(e) return e.count end },
	{ key = "price", title = "Preis", width = 105, defaultDesc = true,
		money = function(e) return e.price end },
	{ key = "unit", title = "Stückpreis", width = 95, defaultDesc = true,
		money = function(e) return (e.price and e.count and e.count > 0) and e.price / e.count or nil end },
	{ key = "party", title = "Käufer / Verkäufer", width = 120,
		text = function(e) return e.party or (e.awaitingMail and "Post ausstehend") or "" end,
		color = function(e)
			if e.party then
				return 1, 1, 1
			end
			return 0.6, 0.6, 0.6
		end,
		sort = function(e) return e.party end },
	{ key = "fees", title = "Gebühren", width = 95, defaultDesc = true,
		money = Fees },
	{ key = "net", title = "Netto", width = 105, defaultDesc = true,
		money = function(e) return e.net end },
	{ key = "character", title = "Charakter", width = 85,
		text = function(e) return e.character or "" end,
		sort = function(e) return e.character end },
}

local function Matches(e, now)
	if filter.type and e.t ~= filter.type then
		return false
	end
	local seconds = PERIODS[filter.period].seconds
	if seconds and now - e.time > seconds then
		return false
	end
	if filter.search ~= "" then
		local hay = ((e.name or "") .. " " .. (e.party or "") .. " " .. (e.character or "")):lower()
		if not hay:find(filter.search, 1, true) then
			return false
		end
	end
	return true
end

local function Summary(rows)
	local s = { sale = 0, saleGross = 0, saleNet = 0, expired = 0, cancelled = 0, lost = 0, purchase = 0, spent = 0, total = 0 }
	for _, e in ipairs(rows) do
		s.total = s.total + (e.net or 0)
		if e.t == "sale" then
			s.sale = s.sale + 1
			s.saleGross = s.saleGross + (e.price or 0)
			s.saleNet = s.saleNet + (e.net or 0)
		elseif e.t == "expired" or e.t == "cancelled" then
			s[e.t] = s[e.t] + 1
			s.lost = s.lost - (e.net or 0)
		elseif e.t == "purchase" then
			s.purchase = s.purchase + 1
			s.spent = s.spent + (e.price or 0)
		end
	end
	return ("Verkauft: %d (Umsatz %s, netto %s)   ·   Abgelaufen/abgebrochen: %d (Gebühren %s)   ·   Gekauft: %d (%s)   ·   Bilanz: %s")
		:format(s.sale, ns.Money(s.saleGross), ns.Money(s.saleNet), s.expired + s.cancelled, ns.Money(s.lost),
			s.purchase, ns.Money(s.spent), ns.Money(s.total))
end

local function Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local rows, now = {}, time()
	for _, e in ipairs(ns.RealmData().journal) do
		if Matches(e, now) then
			rows[#rows + 1] = e
		end
	end
	frame.table:SetRows(rows)
	frame.summary:SetText(Summary(rows))
	frame.empty:SetShown(#rows == 0)
end

ns.OnJournalChanged = Refresh

local function ShowEntryTooltip(rowFrame, e)
	GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	if e.link then
		GameTooltip:SetHyperlink(e.link)
		GameTooltip:AddLine(" ")
	else
		GameTooltip:AddLine(e.name or "?")
	end
	local t = TYPE_BY_KEY[e.t]
	GameTooltip:AddDoubleLine(t.label, ns.DateTime(e.time), t.color[1], t.color[2], t.color[3], 1, 1, 1)
	if not e.exact then
		GameTooltip:AddLine("Zeitpunkt aus der Post geschätzt (offline passiert).", 0.6, 0.6, 0.6, true)
	end
	if e.awaitingMail then
		GameTooltip:AddLine("Postrechnung noch nicht abgeholt: Käufer und endgültiger Betrag folgen.", 1, 0.82, 0, true)
	end
	if e.deposit then
		GameTooltip:AddDoubleLine("Einstellgebühr", ns.MoneyAligned(e.deposit), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if e.cut then
		GameTooltip:AddDoubleLine("AH-Gebühr", ns.MoneyAligned(e.cut), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if e.cancelFee and e.cancelFee > 0 then
		GameTooltip:AddDoubleLine("Abbruchgebühr", ns.MoneyAligned(e.cancelFee), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreateJournalFrame()
	frame = ns.CreateWindow("KontorJournalFrame", "Kontor – Journal", 1040, 540)
	frame:SetScript("OnShow", Refresh)

	local typeOptions = { { label = "Alle Typen", value = false } }
	for _, t in ipairs(TYPES) do
		typeOptions[#typeOptions + 1] = { label = t.label, value = t.key }
	end
	local typeDropdown = ns.CreateDropdown(frame, 150, typeOptions,
		function(value) return (filter.type or false) == value end,
		function(value) filter.type = value or nil; Refresh() end)
	typeDropdown:SetPoint("TOPLEFT", 14, -32)

	local periodOptions = {}
	for i, p in ipairs(PERIODS) do
		periodOptions[i] = { label = p.label, value = i }
	end
	local periodDropdown = ns.CreateDropdown(frame, 170, periodOptions,
		function(value) return filter.period == value end,
		function(value) filter.period = value; Refresh() end)
	periodDropdown:SetPoint("LEFT", typeDropdown, "RIGHT", 10, 0)

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(220, 20)
	search:SetPoint("LEFT", periodDropdown, "RIGHT", 16, 0)
	search.Instructions:SetText("Item, Käufer, Charakter …")
	search:HookScript("OnTextChanged", function(self)
		filter.search = self:GetText():lower()
		Refresh()
	end)

	frame.table = ns.CreateTable(frame, COLUMNS, {
		sortKey = "time",
		sortDesc = true,
		onEnter = ShowEntryTooltip,
		onClick = function(rowFrame, e, button)
			if button ~= "RightButton" then
				return
			end
			MenuUtil.CreateContextMenu(rowFrame, function(_, root)
				root:CreateTitle(e.name or "?")
				root:CreateButton("Eintrag löschen", function()
					ns.DeleteJournalEntry(e)
				end)
			end)
		end,
	})
	frame.table:SetPoint("TOPLEFT", 14, -64)
	frame.table:SetPoint("BOTTOMRIGHT", -12, 34)

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.table, "CENTER")
	frame.empty:SetText("Keine Einträge. Verkäufe, Käufe und abgelaufene Auktionen erscheinen hier automatisch.")

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.summary:SetPoint("BOTTOMLEFT", 16, 12)
	frame.summary:SetPoint("BOTTOMRIGHT", -16, 12)
	frame.summary:SetJustifyH("LEFT")

	local marginsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	marginsButton:SetSize(120, 22)
	marginsButton:SetPoint("TOPRIGHT", -14, -32)
	marginsButton:SetText("Margen-Liste")
	marginsButton:SetScript("OnClick", function()
		ns.ToggleMargins()
	end)
end

function ns.ToggleJournal()
	if not frame then
		CreateJournalFrame()
	end
	frame:SetShown(not frame:IsShown())
end

ns.commands.journal = ns.ToggleJournal

function Kontor_OnAddonCompartmentClick()
	ns.ToggleJournal()
end
