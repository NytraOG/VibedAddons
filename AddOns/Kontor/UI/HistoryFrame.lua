local _, ns = ...

-- Preisverlauf: Items aus allen gespeicherten Scans per Sofortsuche finden und anklicken. Der Graph
-- zeigt den Preis (y) ueber die Scan-Zeitpunkte (x, zeitlich masstabsgetreu): jeder Scan ein Punkt,
-- die Punkte eines Items mit Linien verbunden. Bis zu acht Items, jedes in eigener Farbe, mit Legende.
-- Maus ueber dem Graphen: Fadenkreuz am naechsten Scan mit allen Preisen.

-- Feste Farbreihenfolge fuer dunklen Hintergrund; ein Item behaelt seine Farbe, solange es gewaehlt ist
local PALETTE = {
	{ 0x39, 0x87, 0xe5 }, -- blau
	{ 0xd9, 0x59, 0x26 }, -- orange
	{ 0x19, 0x9e, 0x70 }, -- tuerkis
	{ 0xc9, 0x85, 0x00 }, -- gelb
	{ 0xd5, 0x51, 0x81 }, -- magenta
	{ 0x00, 0x83, 0x00 }, -- gruen
	{ 0x90, 0x85, 0xe9 }, -- violett
	{ 0xe6, 0x67, 0x67 }, -- rot
}
for _, c in ipairs(PALETTE) do
	c.r, c.g, c.b = c[1] / 255, c[2] / 255, c[3] / 255
end

local FIELDS = {
	{ label = "Ø 5 günstigste", value = "top5" },
	{ label = "Günstigstes Angebot", value = "min" },
}

local PERIODS = {
	{ label = "Alle Scans", seconds = nil },
	{ label = "Letzte 24 Stunden", seconds = 86400 },
	{ label = "Letzte 7 Tage", seconds = 7 * 86400 },
	{ label = "Letzte 30 Tage", seconds = 30 * 86400 },
}

local LIST_WIDTH = 260
local ROW_HEIGHT = 20
local AXIS_LEFT = 90 -- Platz fuer die Preise links vom Graphen
local AXIS_BOTTOM = 22 -- Platz fuer die Zeitpunkte darunter
local PAD = 10 -- Abstand der Punkte zum Rand der Zeichenflaeche
local DOT = 6
local RING = 10 -- Ring in Hintergrundfarbe um jeden Punkt, damit sich Linien und Punkte abheben
local HOVER_DOT = 10
local X_LABELS = 6
local LEGEND_TEXT_MAX = 200
local NAME_BATCH = 50 -- Item-Daten pro Zehntelsekunde nachladen
local BACKGROUND = { 0.07, 0.07, 0.07 }
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local frame
local search = ""

-- Auswahl und Einstellungen bleiben ueber Sitzungen erhalten. selected: itemID -> Farbnummer
local function State()
	local s = ns.db.priceGraph
	if not s then
		s = { selected = {}, field = "top5", period = 1 }
		ns.db.priceGraph = s
	end
	return s
end

local function SelectedInOrder()
	local list = {}
	for itemID, slot in pairs(State().selected) do
		list[#list + 1] = { id = itemID, slot = slot }
	end
	table.sort(list, function(a, b) return a.slot < b.slot end)
	return list
end

-- ---- Item-Namen ------------------------------------------------------------
-- Namen kommen aus dem Item-Cache des Clients oder aus dem Scan (ns.db.itemNames). Fehlende werden
-- in kleinen Portionen nachgeladen; GET_ITEM_INFO_RECEIVED traegt sie dann nach.

local records = {} -- itemID -> { id, name, search, known } fuer alle Items im Verlauf
local extras = {} -- gewaehlte Items, die nicht (mehr) im Verlauf stehen
local recordIDs -- Stand von ns.HistoryItemIDs(), aus dem records gebaut wurde
local sorted -- records nach Name, nil = neu sortieren
local pendingNames = {}
local nameTicker

-- Klein schreiben ohne string.lower: das haengt von der Locale ab und kann UTF-8-Umlaute zerstoeren
local function SearchKey(text)
	return (text:gsub("[A-Z]", string.lower):gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"))
end

-- Nur ein Name vom Client gilt als endgueltig; der gespeicherte ueberbrueckt, bis er nachgeladen ist
local function ResolveName(record)
	local name = ns.ValidItemName(C_Item.GetItemNameByID(record.id))
	if name then
		ns.db.itemNames[record.id] = name
	end
	record.known = name ~= nil
	record.name = name or ns.ValidItemName(ns.db.itemNames[record.id]) or ("Item #" .. record.id)
	record.search = SearchKey(record.name)
	return record.known
end

local function RequestNames()
	if nameTicker or #pendingNames == 0 then
		return
	end
	nameTicker = C_Timer.NewTicker(0.1, function()
		for _ = 1, NAME_BATCH do
			local itemID = table.remove(pendingNames)
			if not itemID then
				nameTicker:Cancel()
				nameTicker = nil
				return
			end
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end)
end

local function UpdateRecords()
	local ids = ns.HistoryItemIDs()
	if ids == recordIDs then
		return
	end
	recordIDs = ids
	local fresh = {}
	wipe(pendingNames)
	for itemID in pairs(ids) do
		local record = records[itemID] or extras[itemID] or { id = itemID }
		if not record.known and not ResolveName(record) then
			pendingNames[#pendingNames + 1] = itemID
		end
		fresh[itemID] = record
	end
	records = fresh
	sorted = nil
	RequestNames()
end

local function Record(itemID)
	local record = records[itemID] or extras[itemID]
	if not record then
		record = { id = itemID }
		if not ResolveName(record) then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		extras[itemID] = record
	end
	return record
end

local function SortedRecords()
	if not sorted then
		sorted = {}
		for _, record in pairs(records) do
			sorted[#sorted + 1] = record
		end
		table.sort(sorted, function(a, b)
			if a.search ~= b.search then
				return a.search < b.search
			end
			return a.id < b.id
		end)
	end
	return sorted
end

-- ---- Objekt-Pools ----------------------------------------------------------

local function CreatePool(create)
	return { used = 0, items = {}, create = create }
end

local function Acquire(pool)
	pool.used = pool.used + 1
	local obj = pool.items[pool.used]
	if not obj then
		obj = pool.create()
		pool.items[pool.used] = obj
	end
	obj:Show()
	return obj
end

local function ReleaseAll(pool)
	for _, obj in ipairs(pool.items) do
		obj:Hide()
	end
	pool.used = 0
end

-- ---- Achsen ----------------------------------------------------------------

-- Runde Schritte (1-2-5 in Kupfer, also auch in Silber und Gold rund) von unter minimum bis ueber maximum
local function NiceTicks(minimum, maximum)
	if maximum <= minimum then
		local pad = math.max(1, minimum * 0.1)
		minimum, maximum = math.max(0, minimum - pad), maximum + pad
	end
	local rough = (maximum - minimum) / 4
	local magnitude = 10 ^ math.floor(math.log10(rough))
	local norm = rough / magnitude
	local step = (norm < 1.5 and 1 or norm < 3 and 2 or norm < 7 and 5 or 10) * magnitude
	step = math.max(1, step)
	local lo, hi = math.floor(minimum / step) * step, math.ceil(maximum / step) * step
	local ticks = {}
	for i = 0, math.floor((hi - lo) / step + 0.5) do
		ticks[#ticks + 1] = lo + i * step
	end
	return ticks, lo, hi
end

local function Swatch(c)
	return ("|T%s:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(WHITE, c[1], c[2], c[3])
end

-- ---- Graph -----------------------------------------------------------------

local function HideHover()
	if not frame then
		return
	end
	frame.hoverIndex = nil
	frame.crosshair:Hide()
	ReleaseAll(frame.pools.hover)
	if GameTooltip:IsOwned(frame.plot) then
		GameTooltip:Hide()
	end
end

-- Legende in die obere Ecke, in der weniger Punkte liegen
local function PlaceLegend(points, width, height)
	local legend = frame.legend
	if not legend:IsShown() then
		return
	end
	local w, h = legend:GetSize()
	local left, right = 0, 0
	for _, p in ipairs(points) do
		if p.y > height - h - 12 then
			if p.x < w + 12 then
				left = left + 1
			end
			if p.x > width - w - 12 then
				right = right + 1
			end
		end
	end
	legend:ClearAllPoints()
	if right < left then
		legend:SetPoint("TOPRIGHT", frame.plot, "TOPRIGHT", -6, -6)
	else
		legend:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", 6, -6)
	end
end

local function UpdateLegend(series)
	local legend = frame.legend
	ReleaseAll(legend.pool)
	legend:SetShown(#series > 0)
	local textWidth = 0
	for i, s in ipairs(series) do
		local entry = Acquire(legend.pool)
		entry:ClearAllPoints()
		entry:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 14)
		local c = s.color
		entry.line:SetColorTexture(c.r, c.g, c.b, 1)
		entry.dot:SetVertexColor(c.r, c.g, c.b, 1)
		local text = s.record.name
		if #s.points == 0 then
			text = text .. " (keine Daten)"
			entry.text:SetTextColor(0.6, 0.6, 0.6)
		else
			entry.text:SetTextColor(1, 1, 1)
		end
		entry.text:SetText(text)
		local w = math.min(LEGEND_TEXT_MAX, math.ceil(ns.TextWidth(GameFontHighlightSmall, text) or LEGEND_TEXT_MAX))
		entry.text:SetWidth(w)
		textWidth = math.max(textWidth, w)
	end
	legend:SetSize(8 + 16 + 6 + textWidth + 8, 12 + #series * 14)
end

local function Draw()
	if not frame or not frame:IsShown() then
		return
	end
	local plot = frame.plot
	local width, height = plot:GetSize()
	for _, pool in pairs(frame.pools) do
		ReleaseAll(pool)
	end
	HideHover()
	frame.times = nil

	local state = State()
	local period = PERIODS[state.period] or PERIODS[1]
	local since = period.seconds and time() - period.seconds
	local series = {}
	local tMin, tMax, vMin, vMax
	for _, sel in ipairs(SelectedInOrder()) do
		local points = ns.GetPriceSeries(sel.id, state.field, since)
		series[#series + 1] = { id = sel.id, color = PALETTE[sel.slot], points = points, record = Record(sel.id) }
		for _, p in ipairs(points) do
			tMin, tMax = math.min(tMin or p.time, p.time), math.max(tMax or p.time, p.time)
			vMin, vMax = math.min(vMin or p.value, p.value), math.max(vMax or p.value, p.value)
		end
	end
	frame.series = series
	UpdateLegend(series)

	local message
	if #ns.RealmData().history == 0 then
		message = "Noch keine Scans. Starte im Auktionshaus einen Komplett-Scan."
	elseif #series == 0 then
		message = "Links Items anklicken."
	elseif not tMin then
		message = "Keine Preise im gewählten Zeitraum."
	end
	frame.plotEmpty:SetText(message or "")
	frame.plotEmpty:SetShown(message ~= nil)
	if not tMin or width <= 2 * PAD or height <= 2 * PAD then
		return
	end

	-- Ein einzelner Zeitpunkt steht in der Mitte
	local single = tMin == tMax
	if single then
		tMin, tMax = tMin - 3600, tMax + 3600
	end
	local ticks, lo, hi = NiceTicks(vMin, vMax)
	local function X(t)
		return PAD + (t - tMin) / (tMax - tMin) * (width - 2 * PAD)
	end
	local function Y(v)
		return PAD + (v - lo) / (hi - lo) * (height - 2 * PAD)
	end
	frame.X, frame.Y = X, Y

	-- y-Achse: Preise mit Gitterlinien
	for _, v in ipairs(ticks) do
		local y = Y(v)
		local grid = Acquire(frame.pools.grid)
		grid:ClearAllPoints()
		grid:SetPoint("LEFT", plot, "BOTTOMLEFT", 0, y)
		grid:SetPoint("RIGHT", plot, "BOTTOMRIGHT", 0, y)
		local label = Acquire(frame.pools.yLabels)
		label:ClearAllPoints()
		label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, y)
		label:SetText(ns.Money(v))
	end

	-- x-Achse: gleichmaessig verteilte Zeitpunkte; Uhrzeit nur, wenn die Abstaende unter einem Tag liegen
	local count = single and 1 or X_LABELS
	local step = single and 0 or (tMax - tMin) / (count - 1)
	local format = (not single and step >= 86400) and "%d.%m." or "%d.%m. %H:%M"
	for i = 0, count - 1 do
		local t = single and (tMin + tMax) / 2 or tMin + i * step
		local label = Acquire(frame.pools.xLabels)
		label:ClearAllPoints()
		label:SetPoint("TOP", plot, "BOTTOMLEFT", X(t), -6)
		label:SetText(date(format, t))
	end

	-- Linien und Punkte
	local times, seen, placed = {}, {}, {}
	for _, s in ipairs(series) do
		local c = s.color
		local prevX, prevY
		s.byTime = {}
		for _, p in ipairs(s.points) do
			local x, y = X(p.time), Y(p.value)
			s.byTime[p.time] = p.value
			if not seen[p.time] then
				seen[p.time] = true
				times[#times + 1] = p.time
			end
			if prevX then
				local line = Acquire(frame.pools.lines)
				line:SetStartPoint("BOTTOMLEFT", plot, prevX, prevY)
				line:SetEndPoint("BOTTOMLEFT", plot, x, y)
				line:SetColorTexture(c.r, c.g, c.b, 1)
			end
			local ring = Acquire(frame.pools.rings)
			ring:ClearAllPoints()
			ring:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
			local dot = Acquire(frame.pools.dots)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
			dot:SetVertexColor(c.r, c.g, c.b, 1)
			placed[#placed + 1] = { x = x, y = y }
			prevX, prevY = x, y
		end
	end
	table.sort(times)
	frame.times = times
	PlaceLegend(placed, width, height)
end

-- Fadenkreuz am Scan, der dem Mauszeiger waagerecht am naechsten liegt
local function UpdateHover()
	local times, plot = frame.times, frame.plot
	if not times or #times == 0 or not plot:GetLeft() then
		HideHover()
		return
	end
	local cursorX = GetCursorPosition() / plot:GetEffectiveScale() - plot:GetLeft()
	local index, best
	for i, t in ipairs(times) do
		local distance = math.abs(frame.X(t) - cursorX)
		if not best or distance < best then
			index, best = i, distance
		end
	end
	if index == frame.hoverIndex then
		return
	end
	frame.hoverIndex = index

	local t = times[index]
	local x = frame.X(t)
	frame.crosshair:ClearAllPoints()
	frame.crosshair:SetPoint("TOP", plot, "TOPLEFT", x, 0)
	frame.crosshair:SetPoint("BOTTOM", plot, "BOTTOMLEFT", x, 0)
	frame.crosshair:Show()

	ReleaseAll(frame.pools.hover)
	GameTooltip:SetOwner(plot, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if x < plot:GetWidth() / 2 then
		GameTooltip:SetPoint("TOPLEFT", plot, "TOPLEFT", x + 14, -8)
	else
		GameTooltip:SetPoint("TOPRIGHT", plot, "TOPLEFT", x - 14, -8)
	end
	GameTooltip:SetText(ns.DateTime(t), 1, 1, 1)
	for _, s in ipairs(frame.series) do
		local value = s.byTime and s.byTime[t]
		if value then
			local c = s.color
			local marker = Acquire(frame.pools.hover)
			marker:ClearAllPoints()
			marker:SetPoint("CENTER", plot, "BOTTOMLEFT", x, frame.Y(value))
			marker.dot:SetVertexColor(c.r, c.g, c.b, 1)
			ns.AddMoneyLine(GameTooltip, Swatch(c) .. " " .. s.record.name, value)
		end
	end
	GameTooltip:Show()
end

-- ---- Item-Liste ------------------------------------------------------------

local RefreshList

local function ToggleItem(itemID)
	local selected = State().selected
	if selected[itemID] then
		selected[itemID] = nil
	else
		local used = {}
		for _, slot in pairs(selected) do
			used[slot] = true
		end
		local free
		for slot = 1, #PALETTE do
			if not used[slot] then
				free = slot
				break
			end
		end
		if not free then
			ns.Print("Höchstens %d Items gleichzeitig.", #PALETTE)
			return
		end
		selected[itemID] = free
	end
	RefreshList()
	Draw()
end

local function InitRow(row, record)
	if not row.label then
		row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
		row.selectedBg:SetAllPoints()
		row.selectedBg:SetColorTexture(1, 1, 1, 0.07)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		row.swatch = row:CreateTexture(nil, "ARTWORK")
		row.swatch:SetSize(4, ROW_HEIGHT - 4)
		row.swatch:SetPoint("LEFT", 2, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 10, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.label:SetPoint("RIGHT", -4, 0)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			ToggleItem(self.record.id)
		end)
		row:SetScript("OnEnter", function(self)
			ns.SetTooltipOwnerOutside(GameTooltip, self)
			GameTooltip:SetItemByID(self.record.id)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	row.record = record
	local slot = State().selected[record.id]
	if slot then
		local c = PALETTE[slot]
		row.swatch:SetColorTexture(c.r, c.g, c.b, 1)
	end
	row.swatch:SetShown(slot ~= nil)
	row.selectedBg:SetShown(slot ~= nil)
	row.icon:SetTexture(C_Item.GetItemIconByID(record.id))
	row.label:SetText(record.name)
	local quality = C_Item.GetItemQualityByID(record.id)
	local colorData = quality and ColorManager and ColorManager.GetColorDataForItemQuality(quality)
	if colorData then
		row.label:SetTextColor(colorData.color:GetRGB())
	else
		row.label:SetTextColor(1, 1, 1)
	end
end

-- Gewaehlte Items stehen immer oben (in Farbreihenfolge), darunter die Treffer der Suche
function RefreshList(resetScroll)
	if not frame or not frame:IsShown() then
		return
	end
	UpdateRecords()
	local selected = State().selected
	local list = {}
	for _, sel in ipairs(SelectedInOrder()) do
		list[#list + 1] = Record(sel.id)
	end
	local matches = 0
	for _, record in ipairs(SortedRecords()) do
		if not selected[record.id] and (search == "" or record.search:find(search, 1, true) or tostring(record.id) == search) then
			list[#list + 1] = record
			matches = matches + 1
		end
	end
	frame.list:SetDataProvider(CreateDataProvider(list),
		resetScroll and ScrollBoxConstants.DiscardScrollPosition or ScrollBoxConstants.RetainScrollPosition)

	local empty
	if not next(records) then
		empty = "Noch keine Scans."
	elseif matches == 0 then
		empty = "Keine Treffer."
	end
	frame.listEmpty:SetText(empty or "")
	frame.listEmpty:SetShown(empty ~= nil)

	local history = ns.RealmData().history
	if #history > 0 then
		frame.footer:SetText(("%d Scans im Verlauf (%s bis %s)   ·   %d Items"):format(#history,
			ns.DateTime(history[1].meta.time), ns.DateTime(history[#history].meta.time), #SortedRecords()))
	else
		frame.footer:SetText("")
	end
end

local function Refresh()
	RefreshList()
	Draw()
end

ns.Listen("PricesChanged", Refresh)

-- Nachgeladene Namen gesammelt einarbeiten
local refreshPending = false
ns.On("GET_ITEM_INFO_RECEIVED", function(itemID, success)
	local record = records[itemID] or extras[itemID]
	if not success or not record or record.known or not ResolveName(record) then
		return
	end
	sorted = nil
	if refreshPending or not frame or not frame:IsShown() then
		return
	end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = false
		Refresh()
	end)
end)

-- ---- Fenster ---------------------------------------------------------------

local function CreateDot(parent, size, sublevel, color)
	local dot = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
	dot:SetTexture(WHITE)
	dot:SetMask(MASK)
	dot:SetSize(size, size)
	if color then
		dot:SetVertexColor(color[1], color[2], color[3], 1)
	end
	return dot
end

local function CreateLegend(plot)
	local legend = CreateFrame("Frame", nil, plot)
	legend:SetFrameLevel(plot:GetFrameLevel() + 5)
	local bg = legend:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.75)
	legend.pool = CreatePool(function()
		local entry = CreateFrame("Frame", nil, legend)
		entry:SetSize(1, 14)
		entry.line = entry:CreateTexture(nil, "ARTWORK")
		entry.line:SetSize(16, 2)
		entry.line:SetPoint("LEFT", 0, 0)
		entry.dot = CreateDot(entry, DOT, 1)
		entry.dot:SetPoint("CENTER", entry.line, "CENTER")
		entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		entry.text:SetPoint("LEFT", entry.line, "RIGHT", 6, 0)
		entry.text:SetJustifyH("LEFT")
		entry.text:SetWordWrap(false)
		return entry
	end)
	legend:Hide()
	return legend
end

local function CreateHistoryFrame()
	frame = ns.CreateWindow("KontorHistoryFrame", "Kontor – Preisverlauf", 1000, 560)
	frame:SetScript("OnShow", function()
		RefreshList()
		Draw()
	end)
	frame:SetScript("OnHide", HideHover)

	-- Links: Suche und Item-Liste
	local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(LIST_WIDTH - 6, 20)
	searchBox:SetPoint("TOPLEFT", 20, -34)
	searchBox.Instructions:SetText("Item suchen …")
	searchBox:HookScript("OnTextChanged", function(self)
		local text = SearchKey(strtrim(self:GetText()))
		if text ~= search then
			search = text
			RefreshList(true)
		end
	end)

	frame.list = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	frame.list:SetPoint("TOPLEFT", 14, -62)
	frame.list:SetPoint("BOTTOMLEFT", 14, 34)
	frame.list:SetWidth(LIST_WIDTH - 16)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(frame.list, scrollBar, view)

	frame.listEmpty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.listEmpty:SetPoint("TOP", frame.list, "TOP", 0, -20)

	-- Rechts oben: Preisart, Zeitraum, Auswahl leeren
	local right = LIST_WIDTH + 30
	local fieldDropdown = ns.CreateDropdown(frame, 180, FIELDS,
		function(value) return State().field == value end,
		function(value) State().field = value; Draw() end)
	fieldDropdown:SetPoint("TOPLEFT", right, -32)

	local periodOptions = {}
	for i, p in ipairs(PERIODS) do
		periodOptions[i] = { label = p.label, value = i }
	end
	local periodDropdown = ns.CreateDropdown(frame, 170, periodOptions,
		function(value) return State().period == value end,
		function(value) State().period = value; Draw() end)
	periodDropdown:SetPoint("LEFT", fieldDropdown, "RIGHT", 10, 0)

	local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearButton:SetSize(130, 22)
	clearButton:SetPoint("TOPRIGHT", -14, -32)
	clearButton:SetText("Auswahl leeren")
	clearButton:SetScript("OnClick", function()
		wipe(State().selected)
		Refresh()
	end)

	-- Zeichenflaeche
	local plot = CreateFrame("Frame", nil, frame)
	plot:SetPoint("TOPLEFT", right + AXIS_LEFT, -70)
	plot:SetPoint("BOTTOMRIGHT", -36, 34 + AXIS_BOTTOM)
	plot:EnableMouse(true)
	frame.plot = plot
	local bg = plot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 1)

	frame.pools = {
		grid = CreatePool(function()
			local tex = plot:CreateTexture(nil, "BORDER")
			tex:SetHeight(1)
			tex:SetColorTexture(1, 1, 1, 0.08)
			return tex
		end),
		yLabels = CreatePool(function()
			local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetJustifyH("RIGHT")
			fs:SetTextColor(0.75, 0.75, 0.75)
			return fs
		end),
		xLabels = CreatePool(function()
			local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetTextColor(0.75, 0.75, 0.75)
			return fs
		end),
		lines = CreatePool(function()
			local line = plot:CreateLine(nil, "ARTWORK")
			line:SetThickness(2)
			return line
		end),
		rings = CreatePool(function()
			return CreateDot(plot, RING, 1, BACKGROUND)
		end),
		dots = CreatePool(function()
			return CreateDot(plot, DOT, 2)
		end),
		-- Hervorgehobener Punkt am Fadenkreuz: farbiger Punkt mit weissem Ring
		hover = CreatePool(function()
			local marker = CreateFrame("Frame", nil, plot)
			marker:SetSize(HOVER_DOT + 4, HOVER_DOT + 4)
			CreateDot(marker, HOVER_DOT + 4, 3, { 1, 1, 1 }):SetPoint("CENTER")
			marker.dot = CreateDot(marker, HOVER_DOT, 4)
			marker.dot:SetPoint("CENTER")
			return marker
		end),
	}

	local axis = plot:CreateTexture(nil, "BORDER")
	axis:SetHeight(1)
	axis:SetPoint("BOTTOMLEFT")
	axis:SetPoint("BOTTOMRIGHT")
	axis:SetColorTexture(1, 1, 1, 0.3)

	frame.crosshair = plot:CreateTexture(nil, "OVERLAY", nil, 0)
	frame.crosshair:SetWidth(1)
	frame.crosshair:SetColorTexture(1, 1, 1, 0.35)
	frame.crosshair:Hide()

	frame.legend = CreateLegend(plot)

	frame.plotEmpty = plot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.plotEmpty:SetPoint("CENTER")

	plot:SetScript("OnEnter", function(self)
		self:SetScript("OnUpdate", UpdateHover)
	end)
	plot:SetScript("OnLeave", function(self)
		self:SetScript("OnUpdate", nil)
		HideHover()
	end)
	plot:SetScript("OnSizeChanged", Draw)

	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.footer:SetPoint("BOTTOMLEFT", 16, 12)
	frame.footer:SetPoint("BOTTOMRIGHT", -16, 12)
	frame.footer:SetJustifyH("LEFT")
end

function ns.ToggleHistory()
	if not frame then
		CreateHistoryFrame()
	end
	frame:SetShown(not frame:IsShown())
end

ns.commands.verlauf = ns.ToggleHistory
