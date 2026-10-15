local _, ns = ...

-- Zusätzlicher Reiter „Lernbar“ im Zauberbuch: Buchseite mit allen noch lernbaren Zaubern
-- (Daten aus Trainer.lua), sortiert nach Stufe. Zu hohe Stufe = ausgegraut, dazu Preis je Zauber
-- und Gesamtpreis aller jetzt lernbaren.
--
-- Blizzards Zauberbuch bleibt unangetastet: Zaubern aus dem Buch ist geschützt, und schon ein
-- einziger von uns geschriebener Wert in Blizzards Reiter- oder Seitendaten würde es blockieren.
-- Deshalb ist der Reiter ein eigener Button rechts neben Blizzards Reitern, und die Seite ist ein
-- eigenes Fenster über dem Seitenbereich. Blizzards Inhalt wird solange per Alpha ausgeblendet;
-- an Blizzards Frames werden nur C-Methoden (Alpha, Texturen ein/aus, Enable) aufgerufen.

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local TAB_TOOLTIP = "Lernbar"
local TITLE = "Lernbar"

-- Maße wie Blizzards Zauberbuch (SpellBookItemTemplate, PagedSpellsFrame)
local ITEM_WIDTH, ITEM_HEIGHT = 215, 64
local COLUMNS = 3
local X_PADDING, Y_PADDING = 15, 10
local HEADER_HEIGHT = 51
local HEADER_SPACING = 20
local UNLEARNED_ALPHA = 0.6
local BACKPLATE_ALPHA, BACKPLATE_HOVER_ALPHA = 0.25, 1

local ACTIVE_BORDER = { atlas = "spellbook-item-iconframe", x1 = -11, y1 = 1, x2 = 1, y2 = -7 }
local INACTIVE_BORDER = { atlas = "spellbook-item-iconframe-inactive", x1 = -10, y1 = 1, x2 = 2, y2 = -5 }

local book, tab, page, controls
local isOpen = false
local hookedTabs = {}
local items = {}
local headers = {}

local function S()
	return ns.db.settings.spellbook
end

local function TextColor()
	return SPELLBOOK_FONT_COLOR or HIGHLIGHT_FONT_COLOR
end

local function Money(copper)
	return GetMoneyString(copper, true)
end

-- ---- Blizzards Reiter (nur Darstellung) -------------------------------------------

local function ShowTabArt(button, selected)
	if button.squareMode then
		button.SquareBackground:SetShown(not selected)
		button.SquareBackgroundActive:SetShown(selected)
		button.SquareBackgroundActiveGlow:SetShown(selected)
	else
		button.Left:SetShown(not selected)
		button.Middle:SetShown(not selected)
		button.Right:SetShown(not selected)
		button.LeftActive:SetShown(selected)
		button.MiddleActive:SetShown(selected)
		button.RightActive:SetShown(selected)
	end
end

local Close

local function HookBlizzardTab(button)
	if hookedTabs[button] then
		return
	end
	hookedTabs[button] = true
	button:HookScript("OnClick", function()
		Close()
	end)
end

-- Blizzards aktiven Reiter wie abgewählt zeigen und anklickbar machen
local function DeselectBlizzardTabs()
	for _, button in ipairs(book.CategoryTabSystem.tabs) do
		HookBlizzardTab(button)
		if button.isSelected then
			ShowTabArt(button, false)
			button:Enable()
		end
	end
end

local function RestoreBlizzardTabs()
	for _, button in ipairs(book.CategoryTabSystem.tabs) do
		if button.isSelected then
			ShowTabArt(button, true)
			button:Disable()
		end
	end
end

-- ---- Eigener Reiter -------------------------------------------------------------------

local function SetTabSelected(selected)
	ShowTabArt(tab, selected)
	tab:SetEnabled(not selected)
end

-- Suchfeld schmaler machen, falls es unseren Reiter überdeckt
local function FitSearchBox()
	local search = book.SearchBox
	if not tab:IsShown() or not search:IsShown() then
		return
	end
	local right, left = tab:GetRight(), search:GetLeft()
	if right and left and right + 10 > left then
		search:SetWidth(math.max(50, search:GetWidth() - (right + 10 - left)))
	end
end

local function CreateTab()
	tab = CreateFrame("Button", nil, book, "SpellBookCategoryTabTemplate")
	tab:SetPoint("TOPLEFT", book.CategoryTabSystem, "TOPRIGHT", 1, 0)

	-- Wie TabSystemButtonMixin:Init/SetSquareMode, aber ohne Blizzards Funktionen aufzurufen
	-- (SetSquareMode schreibt eine gemeinsame Variable von Blizzards Reiter-Code)
	tab.squareMode = true
	for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
		"LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
		tab[key]:Hide()
	end
	tab.SquareBackground:SetAtlas("spellbook-Tab-Frame-C60", true)
	tab.SquareBackgroundActive:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
	tab.SquareBackgroundActiveGlow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
	tab.Icon:SetTexture(ICON)
	tab.Icon:ClearAllPoints()
	tab.Icon:SetPoint("CENTER")
	tab.Icon:Show()
	tab.IconMask:Show()
	tab:SetWidth(tab.Icon:GetWidth() + 8)

	tab:SetScript("OnClick", function()
		if not isOpen then
			PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
			ns.OpenLearnablePage()
		end
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -12, -6)
		GameTooltip_AddNormalLine(GameTooltip, TAB_TOOLTIP)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)
	SetTabSelected(false)
end

-- ---- Einträge -------------------------------------------------------------------------

local function ApplyBorder(item, border)
	item.Border:SetAtlas(border.atlas, false)
	item.Border:ClearAllPoints()
	item.Border:SetPoint("TOPLEFT", item.IconFrame, "TOPLEFT", border.x1, border.y1)
	item.Border:SetPoint("BOTTOMRIGHT", item.IconFrame, "BOTTOMRIGHT", border.x2, border.y2)
end

local function NewFontString(parent, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(TextColor():GetRGB())
	return fs
end

local function ItemOnEnter(item)
	item.Backplate:SetAlpha(BACKPLATE_HOVER_ALPHA)
	local entry = item.entry
	GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
	if entry.spellID then
		GameTooltip:SetSpellByID(entry.spellID)
	else
		GameTooltip:SetText(entry.name)
	end
	GameTooltip:Show()
end

local function ItemOnLeave(item)
	item.Backplate:SetAlpha(BACKPLATE_ALPHA)
	GameTooltip_Hide()
end

local function CreateItem()
	local item = CreateFrame("Frame", nil, page)
	item:SetSize(ITEM_WIDTH, ITEM_HEIGHT)
	item:EnableMouse(true)
	item:SetScript("OnEnter", ItemOnEnter)
	item:SetScript("OnLeave", ItemOnLeave)

	item.Backplate = item:CreateTexture(nil, "BACKGROUND")
	item.Backplate:SetAtlas("spellbook-item-backplate", true)
	item.Backplate:SetPoint("CENTER", 5, -5)
	item.Backplate:SetAlpha(BACKPLATE_ALPHA)

	local iconFrame = CreateFrame("Frame", nil, item)
	iconFrame:SetSize(40, 40)
	iconFrame:SetPoint("LEFT")
	item.IconFrame = iconFrame

	item.Icon = iconFrame:CreateTexture(nil, "ARTWORK", nil, -1)
	item.Icon:SetSize(36, 36)
	item.Icon:SetPoint("CENTER")
	local mask = iconFrame:CreateMaskTexture()
	mask:SetAtlas("spellbook-item-spellicon-mask", false)
	mask:SetAllPoints(item.Icon)
	item.Icon:AddMaskTexture(mask)

	local shadow = iconFrame:CreateTexture(nil, "ARTWORK", nil, 1)
	shadow:SetAtlas("spellbook-item-iconframe-shadow", false)
	shadow:SetPoint("TOPLEFT", -12, 3)
	shadow:SetPoint("BOTTOMRIGHT", 2, -8)

	item.Border = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)

	local text = CreateFrame("Frame", nil, item)
	text:SetPoint("LEFT", 50, -1)
	text:SetPoint("RIGHT")
	item.Text = text

	item.Name = NewFontString(text, "SystemFont_Large")
	item.Name:SetPoint("TOPLEFT")
	item.Name:SetPoint("TOPRIGHT")
	item.Name:SetMaxLines(2)
	item.Name:SetWordWrap(true)

	item.Info = NewFontString(text, "SystemFont_Med1")
	item.Info:SetPoint("TOPLEFT", item.Name, "BOTTOMLEFT", 0, -2)
	item.Info:SetPoint("TOPRIGHT", item.Name, "BOTTOMRIGHT", 0, -2)
	item.Info:SetMaxLines(1)

	item.Price = NewFontString(text, "SystemFont_Med1")
	item.Price:SetPoint("TOPLEFT", item.Info, "BOTTOMLEFT", 0, -2)
	item.Price:SetMaxLines(1)

	return item
end

local function SetItem(item, entry)
	item.entry = entry
	local alpha = entry.available and 1 or UNLEARNED_ALPHA

	item.Icon:SetTexture(entry.icon or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)) or 134400)
	item.Icon:SetDesaturated(not entry.available)
	item.Icon:SetAlpha(alpha)
	ApplyBorder(item, entry.available and ACTIVE_BORDER or INACTIVE_BORDER)

	item.Name:SetText(entry.name)
	if entry.rank then
		item.Info:SetFormattedText("%s, Stufe %d", entry.rank, entry.level)
	else
		item.Info:SetFormattedText("Stufe %d", entry.level)
	end
	item.Price:SetText(entry.cost and Money(entry.cost) or "Preis ?")
	for _, fs in ipairs({ item.Name, item.Info, item.Price }) do
		fs:SetAlpha(alpha)
	end

	-- Textblock vertikal zentrieren
	local nameHeight = math.min(item.Name:GetStringHeight(), item.Name:GetLineHeight() * 2)
	item.Name:SetHeight(nameHeight)
	item.Text:SetHeight(nameHeight + item.Info:GetLineHeight() + item.Price:GetLineHeight() + 4)
end

local function AcquireItem(index)
	local item = items[index]
	if not item then
		item = CreateItem()
		items[index] = item
	end
	return item
end

-- ---- Kopfzeile ------------------------------------------------------------------------

local function CreateHeader(view)
	local header = CreateFrame("Frame", nil, view)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")

	local backplate = header:CreateTexture(nil, "BACKGROUND")
	backplate:SetAtlas("spellbook-list-backplate", false)
	backplate:SetSize(416, 106)
	backplate:SetPoint("LEFT", -85, 10)
	backplate:SetAlpha(0.65)

	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("spellbook-divider", false)
	divider:SetHeight(11)
	divider:SetPoint("BOTTOMLEFT", -32, 0)
	divider:SetPoint("BOTTOMRIGHT", -60, 0)

	header.Title = NewFontString(header, "SystemFont_Huge2")
	header.Title:SetPoint("LEFT", -8, 4)
	header.Title:SetText(TITLE)

	header.Total = NewFontString(header, "SystemFont_Med3")
	header.Total:SetJustifyH("RIGHT")
	header.Total:SetPoint("BOTTOMRIGHT", divider, "TOPRIGHT", 0, 6)

	header.Note = NewFontString(header, "SystemFont_Med1")
	header.Note:SetJustifyH("RIGHT")
	header.Note:SetPoint("BOTTOMRIGHT", header.Total, "TOPRIGHT", 0, 3)
	return header
end

local function UpdateHeader(header, total, count, unknown)
	if count == 0 then
		header.Total:SetText("Jetzt nichts lernbar")
	else
		header.Total:SetFormattedText("Jetzt lernbar: %d für %s", count, Money(total))
	end
	if not ns.TrainerDataTime() then
		header.Note:SetText("Preise: Lehrer besuchen")
	elseif unknown > 0 then
		header.Note:SetFormattedText("%d ohne Preis", unknown)
	else
		header.Note:SetText("")
	end
end

-- ---- Seite ----------------------------------------------------------------------------

local function ViewCount()
	return book.isMinimized and 1 or 2
end

local function RowsFor(view, withHeader)
	local height = view:GetHeight()
	if withHeader then
		height = height - HEADER_HEIGHT - HEADER_SPACING
	end
	return math.max(1, math.floor((height + Y_PADDING) / (ITEM_HEIGHT + Y_PADDING)))
end

local function Render()
	if not isOpen or not page:IsVisible() then
		return
	end
	local list, total, count, unknown = ns.GetLearnableSpells()
	local numViews = ViewCount()

	-- Jede Doppelseite beginnt links mit der Kopfzeile
	local capacities, perPage = {}, 0
	for v = 1, numViews do
		capacities[v] = RowsFor(page.views[v], v == 1) * COLUMNS
		perPage = perPage + capacities[v]
	end
	controls:SetMaxPages(math.ceil(#list / perPage))
	local first = (controls:GetCurrentPage() - 1) * perPage + 1

	local used = 0
	local index = first
	for v = 1, 2 do
		local view = page.views[v]
		local header = headers[v]
		header:SetShown(v == 1 and v <= numViews)
		if v == 1 then
			UpdateHeader(header, total, count, unknown)
		end
		if v <= numViews then
			local top = v == 1 and (HEADER_HEIGHT + HEADER_SPACING) or 0
			for slot = 1, capacities[v] do
				local entry = list[index]
				if not entry then
					break
				end
				used = used + 1
				local item = AcquireItem(used)
				local col = (slot - 1) % COLUMNS
				local row = math.floor((slot - 1) / COLUMNS)
				item:ClearAllPoints()
				item:SetPoint("TOPLEFT", view, "TOPLEFT", col * (ITEM_WIDTH + X_PADDING), -(top + row * (ITEM_HEIGHT + Y_PADDING)))
				SetItem(item, entry)
				item:Show()
				index = index + 1
			end
		end
	end
	for i = used + 1, #items do
		items[i]:Hide()
	end

	page.Empty:SetShown(#list == 0)
	if #list == 0 then
		page.Empty:SetText(ns.TrainerDataTime() and "Alles gelernt." or "Keine Daten. Lehrer besuchen.")
	end
end

local function CreatePage()
	local spells = book.PagedSpellsFrame
	page = CreateFrame("Frame", nil, book)
	page:SetPoint("TOPLEFT", spells, "TOPLEFT", 0, -10)
	page:SetPoint("BOTTOMRIGHT", spells, "BOTTOMRIGHT")
	page:SetFrameLevel(spells:GetFrameLevel() + 30)
	-- Maus abfangen, damit die unsichtbaren Zauber darunter nicht reagieren
	page:EnableMouse(true)
	page:EnableMouseWheel(true)
	page:Hide()

	page.views = {}
	for v = 1, 2 do
		local view = CreateFrame("Frame", nil, page)
		view:SetAllPoints(spells.ViewFrames[v])
		page.views[v] = view
		headers[v] = CreateHeader(view)
	end

	page.Empty = NewFontString(page.views[1], "SystemFont_Large")
	page.Empty:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + HEADER_SPACING))

	controls = CreateFrame("Frame", nil, page, "PagingControlsHorizontalTemplate")
	controls:SetPoint("BOTTOMRIGHT", spells, "BOTTOMRIGHT", -75, 40)
	controls.PageText:SetFontObject("SystemFont_Med3")
	controls.PageText:SetTextColor(TextColor():GetRGB())
	controls.prevPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN
	controls.nextPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN
	controls:SetOverridePagedContentFrame(page)
	page.OnPageChanged = Render

	page:SetScript("OnMouseWheel", function(_, delta)
		controls:OnMouseWheel(delta)
	end)
	page:SetScript("OnShow", Render)

	-- Ziehen an der Seite an das Fenster weitergeben (Fenster verschieben, Frames.lua)
	page:RegisterForDrag("LeftButton")
	for _, script in ipairs({ "OnDragStart", "OnDragStop" }) do
		page:SetScript(script, function()
			local handler = PlayerSpellsFrame:GetScript(script)
			if handler then
				handler(PlayerSpellsFrame)
			end
		end)
	end
end

-- ---- Öffnen/Schließen -----------------------------------------------------------------

function ns.OpenLearnablePage()
	if not page or not tab:IsShown() then
		return
	end
	isOpen = true
	SetTabSelected(true)
	DeselectBlizzardTabs()
	book.PagedSpellsFrame:SetAlpha(0)
	controls:SetCurrentPage(1)
	page:Show()
	Render()
end

Close = function()
	if not isOpen then
		return
	end
	isOpen = false
	page:Hide()
	book.PagedSpellsFrame:SetAlpha(1)
	SetTabSelected(false)
	RestoreBlizzardTabs()
end

local function UpdateTabShown()
	local shown = ns.db.settings.spellbook.tab
	if not shown then
		Close()
	end
	tab:SetShown(shown)
	FitSearchBox()
end

ns.UpdateSpellBookTab = function()
	if tab then
		UpdateTabShown()
	end
end

-- ---- Einrichtung ------------------------------------------------------------------------

local function Setup()
	book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if not book or tab then
		return
	end
	CreateTab()
	CreatePage()

	-- Blizzard wählt bei jeder Zauberänderung den Reiter neu aus; dann wieder abgewählt zeigen
	hooksecurefunc(book.CategoryTabSystem, "SetTabVisuallySelected", function()
		if isOpen then
			DeselectBlizzardTabs()
		end
	end)
	hooksecurefunc(book, "SetMinimized", function()
		if isOpen then
			controls:SetCurrentPage(1)
			Render()
		end
	end)
	hooksecurefunc(book, "ResizeSearchBox", FitSearchBox)
	book.CategoryTabSystem:HookScript("OnSizeChanged", FitSearchBox)
	-- Suchergebnisse zeigt Blizzard im Seitenbereich, also die eigene Seite schließen
	book.SearchBox:HookScript("OnTextChanged", function(box)
		if box:GetText() ~= "" then
			Close()
		end
	end)

	UpdateTabShown()
end

ns.OnLearnableChanged(Render)

ns.On("PLAYER_LOGIN", function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", Setup)
end)
