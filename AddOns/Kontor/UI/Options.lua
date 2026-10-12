local _, ns = ...

-- Optionen im Blizzard-Menü (Optionen → AddOns → Kontor), auch über das Zahnrad in den Kontor-Fenstern
-- und /kontor optionen. Werte stehen in ns.db.settings, Standardwerte in ns.DEFAULTS (Core.lua).

local category

-- Offene Kontor-Fenster mit den neuen Werten neu zeichnen
local function Changed()
	if ns.OnPricesChanged then
		ns.OnPricesChanged()
	end
end

local function Register(key, varType, label, step)
	return Settings.RegisterProxySetting(category, "KONTOR_" .. key:upper(), varType, label, ns.DEFAULTS[key],
		function()
			return ns.db.settings[key]
		end,
		function(value)
			if step then
				-- Slider liefern Gleitkommawerte mit Rundungsfehlern
				value = math.floor(value / step + 0.5) * step
			end
			ns.db.settings[key] = value
			Changed()
		end)
end

local function AddCheckbox(key, label, tooltip)
	Settings.CreateCheckbox(category, Register(key, Settings.VarType.Boolean, label), tooltip)
end

local function AddSlider(key, label, minValue, maxValue, step, format, tooltip)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
	Settings.CreateSlider(category, Register(key, Settings.VarType.Number, label, step), options, tooltip)
end

local function AddHeader(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function Percent(value)
	return ("%.0f %%"):format(value)
end

local function CreateOptions()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Kontor")

	AddHeader(layout, "Preis-Pfeile")
	AddSlider("trendSignificant", "Ein Pfeil ab", 1, 50, 1, Percent)
	AddSlider("trendLarge", "Zwei Pfeile ab", 5, 100, 1, Percent)
	AddSlider("trendMinCopper", "Mindestens", 0, 100, 5, function(value)
		return ("%.0f Kupfer"):format(value)
	end, "Kleinere Änderungen bekommen keinen Pfeil.")
	AddSlider("trendMinAgeHours", "Vergleich mit Scan von vor", 0, 72, 1, function(value)
		return value < 0.5 and "vorletzter" or ("%.0f Std."):format(value)
	end, "Jüngster Scan, der mindestens so alt ist.")
	AddCheckbox("tooltipTrend", "Pfeil in Item-Tooltips")

	AddHeader(layout, "Tooltips")
	AddCheckbox("tooltipPrices", "AH- und Händlerpreise")
	AddCheckbox("tooltipMargins", "Margen im Berufe-Fenster")

	AddHeader(layout, "Auktionshaus")
	AddSlider("defaultCutRate", "AH-Gebühr (angenommen)", 0, 20, 0.5, function(value)
		return ("%.1f %%"):format(value)
	end, "Gilt, bis eigene Verkäufe die Gebühr belegen.")
	AddSlider("historyLimit", "Gespeicherte Scans", 10, 500, 10, function(value)
		return ("%.0f"):format(value)
	end, "Ältere werden beim nächsten Scan gelöscht.")

	AddHeader(layout, "Allgemein")
	local minimap = Settings.RegisterProxySetting(category, "KONTOR_MINIMAP", Settings.VarType.Boolean,
		"Minimap-Button", true, ns.IsMinimapButtonShown, ns.SetMinimapButtonShown)
	Settings.CreateCheckbox(category, minimap)

	Settings.RegisterAddOnCategory(category)
end

ns.On("PLAYER_LOGIN", CreateOptions)

function ns.OpenOptions()
	if InCombatLockdown() then
		ns.Print("Optionen im Kampf nicht verfügbar.")
		return
	end
	if not category then
		return
	end
	Settings.OpenToCategory(category:GetID())
	-- Gleiche Ebene wie die Kontor-Fenster: nach vorne holen
	if SettingsPanel then
		SettingsPanel:Raise()
	end
end

ns.commands.optionen = ns.OpenOptions
