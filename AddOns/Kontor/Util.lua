local _, ns = ...

local PREFIX = "|cffe5b04aKontor|r: "

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Kupferbetrag als Gold/Silber/Kupfer mit Muenz-Icons (fuer Fliesstext; spaltenbuendig: ns.CreateMoneyDisplay)
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

-- Breite eines Texts in der Schrift font, oder nil. Gemessen mit einem eigenen FontString ausserhalb
-- aller Blizzard-Fenster: Innerhalb eines Tooltips liefert WoW Breiten teils als Secret Value, mit dem
-- ein Addon nicht rechnen darf.
local measure

function ns.TextWidth(font, text)
	if not measure then
		measure = UIParent:CreateFontString(nil, "BACKGROUND")
		measure:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
		measure:SetAlpha(0)
	end
	measure:SetFontObject(font)
	measure:SetText(text)
	local width = measure:GetUnboundedStringWidth()
	if ns.IsSecret(width) then
		return nil
	end
	return width
end

-- Unsichtbare Textur als Platzhalter im Text, ungefaehr width breit (in Koordinaten der Schrift font)
local BLANK = "Interface\\AddOns\\Kontor\\Media\\Blank"
local spacerUnit = {}

local function Spacer(units)
	return ("|T%s:1:%d|t"):format(BLANK, units)
end

function ns.SpacerMarkup(width, font)
	local key = (font:GetName() or tostring(font)) .. ":" .. tostring(select(2, font:GetFont()))
	local unit = spacerUnit[key]
	if not unit then
		unit = (ns.TextWidth(font, Spacer(100)) or 0) / 100
		if unit <= 0 then
			unit = 1
		else
			spacerUnit[key] = unit
		end
	end
	return Spacer(math.ceil(width / unit))
end

-- ---- Preis-Pfeile ----------------------------------------------------------
-- trend: 1/2 = gestiegen (ein/zwei Pfeile), -1/-2 = gefallen, 0/nil = nichts.
-- upIsGood: Anstieg gruen statt rot (z.B. Erloes, Marge); sonst ist teurer rot (Materialkosten).

local TREND_ATLAS = { up = "ui-hud-actionbar-pageuparrow-up", down = "ui-hud-actionbar-pagedownarrow-up" }
local GOOD, BAD = { 0.3, 1, 0.3 }, { 1, 0.3, 0.3 }
ns.TREND_HEIGHT = 10

-- Pfeile auf zwei Texturen; Rueckgabe: Gesamtbreite der sichtbaren Pfeile
function ns.ApplyTrend(textures, trend, upIsGood)
	local level = trend and math.abs(trend) or 0
	local atlas, width, color
	if level > 0 then
		local up = trend > 0
		atlas = TREND_ATLAS[up and "up" or "down"]
		local info = C_Texture.GetAtlasInfo(atlas)
		if info then
			width = math.floor(ns.TREND_HEIGHT * info.width / info.height + 0.5)
		else
			atlas = nil -- Atlas fehlt in diesem Client: keine Pfeile
		end
		color = (up == (upIsGood or false)) and GOOD or BAD
	end
	local total = 0
	for i, tex in ipairs(textures) do
		if atlas and i <= level then
			tex:SetAtlas(atlas)
			tex:SetSize(width, ns.TREND_HEIGHT)
			tex:SetDesaturated(true)
			tex:SetVertexColor(color[1], color[2], color[3])
			tex:Show()
			total = total + width
		else
			tex:Hide()
		end
	end
	return total
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

function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

function ns.SafeID(value)
	if ns.IsSecret(value) then
		return nil
	end
	return value
end
