local _, ns = ...

-- Sortierbare Tabelle auf Basis von Blizzards ScrollBox.
--
-- columns: { key, title, width (nil = Rest), align ("LEFT"|"RIGHT"|"CENTER"),
--            text(row) -> string, color(row) -> r,g,b (optional), sort(row) -> Wert (optional),
--            money(row) -> Kupfer (statt text; spaltenbuendig, rechtsbuendig, sortiert nach Betrag),
--            trend(row) -> -2..2 (optional: Preis-Pfeile am linken Zellenrand) }
-- opts:    { rowHeight, sortKey, sortDesc, onEnter(rowFrame, row), onClick(rowFrame, row, button) }

local HEADER_HEIGHT = 20
local PADDING = 4

local TableMixin = {}

local function SortValue(column, row)
	if column.money and not column.sort then
		return column.money(row)
	end
	return column.sort and column.sort(row) or column.text(row)
end

local function CellText(column, row, cell)
	if column.money then
		local copper = column.money(row)
		return copper and ns.MoneyAligned(copper, cell:GetFontObject()) or ""
	end
	return column.text(row) or ""
end

function TableMixin:SetRows(rows)
	self.rows = rows
	self:Refresh()
end

function TableMixin:Refresh()
	local column = self.columnsByKey[self.sortKey]
	local sorted = {}
	for i, row in ipairs(self.rows or {}) do
		sorted[i] = row
	end
	if column then
		local desc = self.sortDesc
		table.sort(sorted, function(a, b)
			local va, vb = SortValue(column, a), SortValue(column, b)
			if va == vb then
				return false
			end
			-- Leere Werte immer ans Ende
			if va == nil then
				return false
			elseif vb == nil then
				return true
			end
			if type(va) ~= type(vb) then
				va, vb = tostring(va), tostring(vb)
			end
			if desc then
				return va > vb
			end
			return va < vb
		end)
	end
	for i, row in ipairs(sorted) do
		row._tableIndex = i
	end
	self.ScrollBox:SetDataProvider(CreateDataProvider(sorted), ScrollBoxConstants.RetainScrollPosition)
	self:UpdateHeaders()
end

function TableMixin:SetSort(key, desc)
	self.sortKey, self.sortDesc = key, desc
	self:Refresh()
	if self.opts.onSortChanged then
		self.opts.onSortChanged(key, desc)
	end
end

function TableMixin:UpdateHeaders()
	for _, header in ipairs(self.headers) do
		local column = header.column
		local arrow = ""
		if column.key == self.sortKey then
			-- Die Standardschrift kennt keine Pfeilzeichen
			arrow = self.sortDesc and " v" or " ^"
		end
		header.Text:SetText(column.title .. arrow)
	end
end

-- Spaltenbreiten: feste Breiten, Spalten ohne width teilen sich den Rest
local function LayoutColumns(columns, totalWidth)
	local fixed, flexible = 0, 0
	for _, c in ipairs(columns) do
		if c.width then
			fixed = fixed + c.width
		else
			flexible = flexible + 1
		end
	end
	local flexWidth = flexible > 0 and math.max(60, (totalWidth - fixed) / flexible) or 0
	local x, layout = 0, {}
	for i, c in ipairs(columns) do
		local w = c.width or flexWidth
		layout[i] = { x = x, width = w }
		x = x + w
	end
	return layout
end

function TableMixin:Layout()
	local width = self.ScrollBox:GetWidth()
	if width <= 0 then
		return
	end
	self.layout = LayoutColumns(self.columns, width)
	for i, header in ipairs(self.headers) do
		local l = self.layout[i]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", self, "TOPLEFT", l.x, 0)
		header:SetSize(l.width, HEADER_HEIGHT)
	end
	self.ScrollBox:ForEachFrame(function(rowFrame)
		self:LayoutRow(rowFrame)
	end)
end

function TableMixin:LayoutRow(rowFrame)
	if not self.layout then
		return
	end
	for i, cell in ipairs(rowFrame.cells) do
		local l = self.layout[i]
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", rowFrame, "LEFT", l.x + PADDING, 0)
		cell:SetWidth(l.width - 2 * PADDING)
	end
end

function TableMixin:InitRow(rowFrame, row)
	if not rowFrame.cells then
		rowFrame.cells = {}
		for i, column in ipairs(self.columns) do
			local cell = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell:SetJustifyH(column.align or (column.money and "RIGHT") or "LEFT")
			cell:SetWordWrap(false)
			if column.trend then
				cell.trend = { rowFrame:CreateTexture(nil, "OVERLAY"), rowFrame:CreateTexture(nil, "OVERLAY") }
				cell.trend[1]:SetPoint("LEFT", cell, "LEFT")
				cell.trend[2]:SetPoint("LEFT", cell.trend[1], "RIGHT", -1, 0)
			end
			rowFrame.cells[i] = cell
		end
		local highlight = rowFrame:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		rowFrame.stripe = rowFrame:CreateTexture(nil, "BACKGROUND")
		rowFrame.stripe:SetAllPoints()
		rowFrame.stripe:SetColorTexture(1, 1, 1, 0.03)
		rowFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		rowFrame:SetScript("OnEnter", function(f)
			if self.opts.onEnter then
				self.opts.onEnter(f, f.row)
			end
		end)
		rowFrame:SetScript("OnLeave", GameTooltip_Hide)
		rowFrame:SetScript("OnClick", function(f, button)
			if self.opts.onClick then
				self.opts.onClick(f, f.row, button)
			end
		end)
		self:LayoutRow(rowFrame)
	end
	rowFrame.row = row
	rowFrame.stripe:SetShown((row._tableIndex or 0) % 2 == 0)
	for i, column in ipairs(self.columns) do
		local cell = rowFrame.cells[i]
		cell:SetText(CellText(column, row, cell))
		if cell.trend then
			ns.ApplyTrend(cell.trend, column.trend(row))
		end
		if column.color then
			cell:SetTextColor(column.color(row))
		else
			cell:SetTextColor(1, 1, 1)
		end
	end
end

function ns.CreateTable(parent, columns, opts)
	local t = CreateFrame("Frame", nil, parent)
	Mixin(t, TableMixin)
	t.columns, t.opts = columns, opts or {}
	t.columnsByKey = {}
	for _, c in ipairs(columns) do
		t.columnsByKey[c.key] = c
	end
	t.sortKey, t.sortDesc = t.opts.sortKey, t.opts.sortDesc

	t.headers = {}
	for i, column in ipairs(columns) do
		local header = CreateFrame("Button", nil, t)
		header.column = column
		header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.Text:SetPoint("LEFT", PADDING, 0)
		header.Text:SetPoint("RIGHT", -PADDING, 0)
		header.Text:SetJustifyH(column.align or (column.money and "RIGHT") or "LEFT")
		local hl = header:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		header:SetScript("OnClick", function()
			if t.sortKey == column.key then
				t:SetSort(column.key, not t.sortDesc)
			else
				-- Zahlen zuerst absteigend, Texte aufsteigend
				t:SetSort(column.key, column.defaultDesc or false)
			end
		end)
		t.headers[i] = header
	end

	t.ScrollBox = CreateFrame("Frame", nil, t, "WowScrollBoxList")
	t.ScrollBox:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - 2)
	t.ScrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
	t.ScrollBar = CreateFrame("EventFrame", nil, t, "MinimalScrollBar")
	t.ScrollBar:SetPoint("TOPLEFT", t.ScrollBox, "TOPRIGHT", 4, 0)
	t.ScrollBar:SetPoint("BOTTOMLEFT", t.ScrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(t.opts.rowHeight or 18)
	view:SetElementInitializer("Button", function(rowFrame, row)
		t:InitRow(rowFrame, row)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(t.ScrollBox, t.ScrollBar, view)

	t.ScrollBox:HookScript("OnSizeChanged", function()
		t:Layout()
	end)
	t.rows = {}
	return t
end
