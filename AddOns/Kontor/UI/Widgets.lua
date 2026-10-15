local _, ns = ...

-- Gemeinsame Bausteine fuer Kontor-Fenster

-- Verschiebbares Fenster mit Titel, schliesst mit ESC, startet versteckt
function ns.CreateWindow(name, title, width, height)
	local frame = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText(title)
	frame.isKontorWindow = true
	table.insert(UISpecialFrames, name)

	-- Zahnrad links neben dem Schliessen-Knopf: Optionen
	local options = CreateFrame("Button", nil, frame)
	options:SetSize(16, 16)
	options:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
	options:SetNormalAtlas("questlog-icon-setting")
	options:SetHighlightAtlas("questlog-icon-setting", "ADD")
	options:SetScript("OnClick", function()
		ns.OpenOptions()
	end)
	options:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Optionen")
		GameTooltip:Show()
	end)
	options:SetScript("OnLeave", GameTooltip_Hide)
	frame:Hide()
	return frame
end

-- ---- Tooltips neben dem Fenster ---------------------------------------------
-- Item-Tooltips zu Zeilen in Kontor-Fenstern stehen links ausserhalb des Fensters, rechtsbuendig an
-- dessen Kante, oben auf Hoehe der Zeile, damit sie nichts verdecken. Vergleichs-Tooltips ("Equipped")
-- werden dort nicht gezeigt: Blizzard setzt sie je nach Platz auch ins Fenster.

local function KontorWindow(region)
	while region and not region.isKontorWindow do
		region = region:GetParent()
	end
	return region
end

-- Bereits gesetzten Tooltip neben window verschieben (links, ausser das Fenster steht am linken
-- Bildschirmrand). Rueckgabe: false, wenn die Positionen noch nicht bekannt sind.
function ns.PlaceTooltipOutside(tooltip, owner, window)
	local top, windowTop, left = owner:GetTop(), window and window:GetTop(), window and window:GetLeft()
	if not top or not windowTop or not left then
		return false
	end
	tooltip:ClearAllPoints()
	local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale() / window:GetEffectiveScale()
	local right = screenWidth - window:GetRight()
	if left < 250 and right > left then
		tooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, top - windowTop)
	else
		tooltip:SetPoint("TOPRIGHT", window, "TOPLEFT", -2, top - windowTop)
	end
	return true
end

-- window: Fenster, neben das der Tooltip soll (Standard: das Kontor-Fenster von owner)
function ns.SetTooltipOwnerOutside(tooltip, owner, window)
	window = window or KontorWindow(owner)
	tooltip:SetOwner(owner, "ANCHOR_NONE")
	if not ns.PlaceTooltipOutside(tooltip, owner, window) then
		tooltip:SetOwner(owner, "ANCHOR_LEFT")
	end
end

-- Vergleichs-Tooltips gehoeren dem Haupt-Tooltip (TooltipComparisonManager:Initialize). Sie werden auf
-- mehreren Wegen eingeblendet (Platzierung, spaeter nachgeladene Item-Daten), daher an zwei Stellen:
-- beim Einblenden (OnShow) und nach der Platzierung, falls sie schon sichtbar waren.
local function IsKontorTooltip(tooltip)
	local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
	return owner ~= nil and KontorWindow(owner) ~= nil
end

local function HideIfKontor(shopping)
	if IsKontorTooltip(shopping:GetOwner()) then
		shopping:Hide()
	end
end

local function HideComparison(manager)
	if IsKontorTooltip(manager.tooltip) then
		for _, shopping in ipairs(manager.tooltip.shoppingTooltips or {}) do
			shopping:Hide()
		end
	end
end

for _, shopping in ipairs(GameTooltip.shoppingTooltips or { ShoppingTooltip1, ShoppingTooltip2 }) do
	shopping:HookScript("OnShow", HideIfKontor)
end
if TooltipComparisonManager then
	local ok, err = pcall(hooksecurefunc, TooltipComparisonManager, "AnchorShoppingTooltips", HideComparison)
	if not ok then
		ns.Print("Vergleichs-Tooltips lassen sich nicht ausblenden: %s", tostring(err))
	end
end

-- Dropdown mit Radio-Eintraegen. options: Liste { label, value } oder Funktion, die eine liefert
-- (wird bei jedem Oeffnen neu erzeugt).
function ns.CreateDropdown(parent, width, options, isSelected, onSelect)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(function(_, root)
		local list = type(options) == "function" and options() or options
		for _, option in ipairs(list) do
			root:CreateRadio(option.label, isSelected, onSelect, option.value)
		end
	end)
	return dropdown
end

-- ---- Geldbetrag mit Muenzen in festen Spalten -------------------------------
-- Ziffern und Muenz-Icons sind eigene Elemente in festen Pixel-Abstaenden vom rechten Rand. Als Text
-- (GetMoneyString) springen die Muenzen um ein paar Pixel, weil WoW rechtsbuendigen Text nicht
-- pixelgenau setzt.

local COINS = { -- von links nach rechts
	{ key = "gold", atlas = "coin-gold" },
	{ key = "silver", atlas = "coin-silver" },
	{ key = "copper", atlas = "coin-copper" },
}
local ICON_GAP = 2 -- Ziffern bis Muenze
local PART_GAP = 4 -- Muenze bis naechste Ziffern
local TREND_GAP = 4 -- Pfeile bis Betrag
local digitWidths = {}

local MoneyMixin = {}

function MoneyMixin:Setup(font)
	local _, size = font:GetFont()
	local iconSize = math.floor((size or 12) + 0.5)
	self:SetSize(1, iconSize + 2)
	self.font = font
	self.parts = {}
	for _, coin in ipairs(COINS) do
		local part = { text = self:CreateFontString(nil, "OVERLAY"), icon = self:CreateTexture(nil, "OVERLAY") }
		part.text:SetFontObject(font)
		part.text:SetJustifyH("RIGHT")
		part.text:SetWordWrap(false)
		part.icon:SetAtlas(coin.atlas)
		part.icon:SetSize(iconSize, iconSize)
		self.parts[coin.key] = part
	end

	-- Platz fuer Silber und Kupfer: die breiteste zweistellige Zahl (Ziffern sind nicht gleich breit)
	local key = (font:GetName() or tostring(font)) .. ":" .. tostring(size)
	local digits = digitWidths[key]
	if not digits then
		digits = 0
		for d = 0, 9 do
			digits = math.max(digits, ns.TextWidth(font, d .. d) or 0)
		end
		digits = math.ceil(digits)
		if digits > 0 then
			digitWidths[key] = digits
		else
			digits = math.ceil(iconSize * 1.2) -- Schrift noch nicht bereit: Schaetzwert
		end
	end

	local x = 0
	for i = #COINS, 1, -1 do
		local part = self.parts[COINS[i].key]
		part.icon:SetPoint("RIGHT", self, "RIGHT", -x, 0)
		part.textRight = x + iconSize + ICON_GAP
		part.text:SetPoint("RIGHT", self, "RIGHT", -part.textRight, 0)
		x = part.textRight + digits + PART_GAP
	end

	self.trend = { self:CreateTexture(nil, "OVERLAY"), self:CreateTexture(nil, "OVERLAY") }
	self.trend[2]:SetPoint("RIGHT", self.trend[1], "LEFT", 1, 0)
	self.trendWidth = ns.ApplyTrend(self.trend, nil)
end

-- Wie GetMoneyString: Nullen weglassen, 0 als Kupfer zeigen; Minus vor dem ersten Teil
function MoneyMixin:SetValue(copper)
	for _, part in pairs(self.parts) do
		part.text:Hide()
		part.icon:Hide()
	end
	self.leftmost = nil
	if not copper then
		return
	end
	copper = math.floor(copper + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local values = {
		gold = math.floor(copper / COPPER_PER_GOLD),
		silver = math.floor(copper / COPPER_PER_SILVER) % SILVER_PER_GOLD,
		copper = copper % COPPER_PER_SILVER,
	}
	for _, coin in ipairs(COINS) do
		local value = values[coin.key]
		if value > 0 or (coin.key == "copper" and not self.leftmost) then
			local part = self.parts[coin.key]
			part.label = sign .. (coin.key == "gold" and FormatLargeNumber(value) or value)
			part.text:SetText(part.label)
			sign = ""
			part.text:Show()
			part.icon:Show()
			self.leftmost = self.leftmost or part
		end
	end
end

function MoneyMixin:SetTextColor(r, g, b)
	for _, part in pairs(self.parts) do
		part.text:SetTextColor(r, g, b)
	end
end

-- Pfeile direkt links vor dem Betrag
function MoneyMixin:SetTrend(trend, upIsGood)
	self.trendWidth = ns.ApplyTrend(self.trend, trend, upIsGood)
	self.trend[1]:ClearAllPoints()
	if self.leftmost then
		self.trend[1]:SetPoint("RIGHT", self.leftmost.text, "LEFT", -TREND_GAP, 0)
	end
end

-- Breite vom rechten Rand bis zum linken Ende (Betrag und Pfeile)
function MoneyMixin:GetContentWidth()
	if not self.leftmost then
		return 0
	end
	-- Nicht am eigenen FontString messen: im Tooltip kaeme die Breite teils als Secret Value
	local text = self.leftmost.label
	local width = self.leftmost.textRight + (ns.TextWidth(self.font, text) or #text * 7)
	if self.trendWidth > 0 then
		width = width + TREND_GAP + self.trendWidth
	end
	return width
end

function ns.CreateMoneyDisplay(parent, font)
	local display = CreateFrame("Frame", nil, parent)
	Mixin(display, MoneyMixin)
	display:Setup(font)
	return display
end

-- ---- Tooltip-Zeile mit Betrag ----------------------------------------------
-- Der rechte Text der Zeile haelt mit einer unsichtbaren Textur nur den Platz frei; darueber liegt
-- eine Geldanzeige. Die Anzeigen werden beim Leeren des Tooltips wieder freigegeben.

local WHITE = { 1, 1, 1 }
local pools = {}

local function ReleaseAll(tooltip)
	local pool = pools[tooltip]
	for i = #pool.active, 1, -1 do
		local display = pool.active[i]
		pool.active[i] = nil
		display:Hide()
		display:ClearAllPoints()
		pool.free[#pool.free + 1] = display
	end
end

local function Acquire(tooltip)
	local pool = pools[tooltip]
	if not pool then
		pool = { active = {}, free = {} }
		pools[tooltip] = pool
		tooltip:HookScript("OnTooltipCleared", ReleaseAll)
		tooltip:HookScript("OnHide", ReleaseAll)
	end
	local display = table.remove(pool.free) or ns.CreateMoneyDisplay(tooltip, GameTooltipText)
	pool.active[#pool.active + 1] = display
	return display
end

-- opts: { leftColor = {r,g,b}, color = {r,g,b} (Betrag), trend, upIsGood }
function ns.AddMoneyLine(tooltip, left, copper, opts)
	opts = opts or {}
	local lc, rc = opts.leftColor or WHITE, opts.color or WHITE
	local name = tooltip:GetName()
	local lines, level = tooltip:NumLines(), tooltip:GetFrameLevel()
	-- Tooltips mit Secret Values: Betrag als normaler Text
	if not copper or not name or ns.IsSecret(lines) or ns.IsSecret(level) then
		tooltip:AddDoubleLine(left, ns.Money(copper), lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
		return
	end
	local display = Acquire(tooltip)
	display:SetValue(copper)
	display:SetTextColor(rc[1], rc[2], rc[3])
	display:SetTrend(opts.trend, opts.upIsGood)
	tooltip:AddDoubleLine(left, ns.SpacerMarkup(display:GetContentWidth(), GameTooltipText), lc[1], lc[2], lc[3], 1, 1, 1)
	local right = _G[name .. "TextRight" .. (lines + 1)]
	if not right then
		display:Hide()
		return
	end
	display:SetPoint("RIGHT", right, "RIGHT")
	display:SetFrameLevel(level + 5)
	display:Show()
end
