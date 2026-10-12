local _, ns = ...

local PREFIX = "|cffe5b04aKontor|r: "

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Kupferbetrag als Gold/Silber/Kupfer mit Muenz-Icons
function ns.Money(copper)
	if not copper then
		return "?"
	end
	copper = math.floor(copper + 0.5)
	if copper < 0 then
		return "-" .. GetMoneyString(-copper, true)
	end
	return GetMoneyString(copper, true)
end

-- ---- Buendige Geldbetraege -------------------------------------------------
-- In rechtsbuendigen Spalten sollen Gold, Silber und Kupfer genau untereinander stehen. Silber und
-- Kupfer bekommen deshalb eine feste Breite: Fehlende oder einstellige Werte werden links mit einer
-- unsichtbaren Textur aufgefuellt. Gemessen wird mit der Schrift der Zielspalte.

local BLANK = "Interface\\AddOns\\Kontor\\Media\\Blank"
local measure, measureFont
local metrics = {}

local function Spacer(units)
	return ("|T%s:1:%d|t"):format(BLANK, units)
end

local function Width(font, text)
	if not measure then
		measure = UIParent:CreateFontString(nil, "BACKGROUND")
		measure:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
		measure:SetAlpha(0)
	end
	if measureFont ~= font then
		measure:SetFontObject(font)
		measureFont = font
	end
	measure:SetText(text)
	return measure:GetUnboundedStringWidth()
end

local function Metrics(font)
	local key = (font:GetName() or tostring(font)) .. ":" .. tostring(select(2, font:GetFont()))
	local m = metrics[key]
	if m then
		return m
	end
	-- Breite einer Spacer-Einheit in Schrift-Koordinaten
	local unit = Width(font, Spacer(100)) / 100
	if unit <= 0 then
		return nil -- Schrift noch nicht bereit
	end
	m = { font = font, unit = unit, widths = {}, silver = 0, copper = 0 }
	-- Die breiteste zweistellige Zahl bestimmt die Spaltenbreite (Ziffern sind nicht gleich breit)
	for d = 0, 9 do
		m.silver = math.max(m.silver, Width(font, " " .. SILVER_AMOUNT_TEXTURE:format(d * 11, 0, 0)))
		m.copper = math.max(m.copper, Width(font, " " .. COPPER_AMOUNT_TEXTURE:format(d * 11, 0, 0)))
	end
	metrics[key] = m
	return m
end

-- Inhalt (nil = leer) rechtsbuendig auf die Spaltenbreite auffuellen. Rueckgabe: Text, tatsaechliche Breite
local function Slot(m, width, content)
	local w = 0
	if content then
		w = m.widths[content]
		if not w then
			w = Width(m.font, content)
			m.widths[content] = w
		end
	end
	local pad = math.floor((width - w) / m.unit + 0.5)
	if pad <= 0 then
		return content or "", w
	end
	return Spacer(pad) .. (content or ""), w + pad * m.unit
end

-- Wie ns.Money, aber spaltenbuendig. font: Font-Objekt der Spalte (Standard: Tooltip-Schrift).
function ns.MoneyAligned(copper, font)
	if not copper then
		return "?"
	end
	local m = Metrics(font or GameTooltipText)
	if not m then
		return ns.Money(copper)
	end
	copper = math.floor(copper + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local gold = math.floor(copper / COPPER_PER_GOLD)
	local silver = math.floor(copper / COPPER_PER_SILVER) % SILVER_PER_GOLD
	copper = copper % COPPER_PER_SILVER

	-- Angezeigte Teile wie bei GetMoneyString; das Minus steht vor dem ersten
	local goldText, silverText, copperText
	if gold > 0 then
		goldText = sign .. GOLD_AMOUNT_TEXTURE_STRING:format(FormatLargeNumber(gold), 0, 0)
		sign = ""
	end
	if silver > 0 then
		silverText = sign .. SILVER_AMOUNT_TEXTURE:format(silver, 0, 0)
		sign = ""
	end
	if copper > 0 or not (goldText or silverText) then
		copperText = sign .. COPPER_AMOUNT_TEXTURE:format(copper, 0, 0)
	end

	-- Von rechts nach links auffuellen: Die Silberspalte gleicht den Rundungsfehler der Kupferspalte aus
	local copperPart, copperWidth = Slot(m, m.copper, copperText)
	if not (goldText or silverText) then
		return copperPart
	end
	local silverPart = Slot(m, m.silver + m.copper - copperWidth, silverText)
	return (goldText or "") .. silverPart .. copperPart
end

-- ---- Preis-Pfeile ----------------------------------------------------------
-- trend: 1/2 = teurer (ein/zwei Pfeile, rot), -1/-2 = billiger (gruen), 0/nil = nichts

local TREND_ATLAS = { up = "ui-hud-actionbar-pageuparrow-up", down = "ui-hud-actionbar-pagedownarrow-up" }
local TREND_COLOR = { up = { 1, 0.3, 0.3 }, down = { 0.3, 1, 0.3 } }
local TREND_HEIGHT = 10

local function TrendStyle(trend)
	local dir = trend > 0 and "up" or "down"
	local info = C_Texture.GetAtlasInfo(TREND_ATLAS[dir])
	local width = info and math.floor(TREND_HEIGHT * info.width / info.height + 0.5)
	return dir, info and TREND_ATLAS[dir], width, TREND_COLOR[dir]
end

-- Pfeile als Text-Markup (fuer Tooltips), mit Leerzeichen dahinter
function ns.TrendMarkup(trend)
	if not trend or trend == 0 then
		return ""
	end
	local dir, atlas, width, color = TrendStyle(trend)
	local one
	if atlas then
		one = CreateAtlasMarkup(atlas, width, TREND_HEIGHT, 0, 0,
			math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
	else
		-- Atlas fehlt in diesem Client: Ersatzzeichen
		one = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, dir == "up" and "+" or "-")
	end
	return one:rep(math.abs(trend)) .. " "
end

-- Pfeile auf zwei Texturen (fuer Tabellen)
function ns.ApplyTrend(textures, trend)
	local level = trend and math.abs(trend) or 0
	local _, atlas, width, color
	if level > 0 then
		_, atlas, width, color = TrendStyle(trend)
	end
	for i, tex in ipairs(textures) do
		if atlas and i <= level then
			tex:SetAtlas(atlas)
			tex:SetSize(width, TREND_HEIGHT)
			tex:SetDesaturated(true)
			tex:SetVertexColor(color[1], color[2], color[3])
			tex:Show()
		else
			tex:Hide()
		end
	end
end

-- "vor 5 Min." / "vor 3 Std." / "vor 2 Tagen"
function ns.Ago(timestamp)
	if not timestamp then
		return "nie"
	end
	local diff = time() - timestamp
	if diff < 60 then
		return "gerade eben"
	elseif diff < 3600 then
		return ("vor %d Min."):format(diff / 60)
	elseif diff < 86400 then
		return ("vor %d Std."):format(diff / 3600)
	end
	local days = math.floor(diff / 86400)
	return days == 1 and "vor 1 Tag" or ("vor %d Tagen"):format(days)
end

function ns.DateTime(timestamp)
	return date("%d.%m.%Y %H:%M", timestamp)
end

-- Ein Auktionshaus pro Realm und Fraktion
function ns.RealmKey()
	return GetRealmName() .. "-" .. (UnitFactionGroup("player") or "Neutral")
end

function ns.SafeID(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end
