local _, ns = ...

-- Eintrag im Blizzard-Optionsmenü (Optionen → AddOns → Sanity Enricher)

local category
local enabledSetting

-- Checkbox für einen Wert in ns.db.settings[section][key] (section nil = oberste Ebene)
local function AddCheckbox(section, key, label, tooltip, onChange)
	local function Target()
		return section and ns.db.settings[section] or ns.db.settings
	end
	local default = (section and ns.DEFAULTS[section] or ns.DEFAULTS)[key]
	local variable = ("SANITYENRICHER_%s_%s"):format(section or "MAIN", key):upper()
	local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, label, default,
		function() return Target()[key] end,
		function(value)
			Target()[key] = value
			if onChange then
				onChange(value)
			end
		end)
	Settings.CreateCheckbox(category, setting, tooltip)
	return setting
end

local function AddHeader(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function CreateOptions()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Sanity Enricher")

	enabledSetting = AddCheckbox(nil, "enabled", "Aktiv", "Shift gedrückt = Pause")

	AddHeader(layout, "Quests")
	AddCheckbox("quests", "accept", "Annehmen")
	AddCheckbox("quests", "turnIn", "Abgeben", "Bei Belohnungswahl wird angehalten.")
	AddCheckbox("quests", "trivial", "Graue Quests")
	AddCheckbox("quests", "repeatable", "Wiederholbare/Tägliche")
	AddCheckbox("quests", "confirm", "Gruppenquests bestätigen")

	AddHeader(layout, "Händler")
	AddCheckbox("vendor", "sellJunk", "Müll verkaufen")
	AddCheckbox("vendor", "repair", "Reparieren")
	AddCheckbox("vendor", "guildRepair", "Gildenbank zuerst")

	AddHeader(layout, "Fenster")
	AddCheckbox("frames", "move", "Frei verschieben", "Taschen, Berufe, Auktionshaus usw. am Hintergrund ziehen.")
	AddCheckbox("frames", "remember", "Positionen merken", "Aus: nur bis zum Ausloggen.")
	layout:AddInitializer(CreateSettingsButtonInitializer("Positionen", "Zurücksetzen", function()
		ns.ResetFramePositions()
	end, nil, false))

	AddHeader(layout, "Zauberbuch")
	AddCheckbox("spellbook", "tab", "Reiter „Lernbar“", "Preise kommen vom Lehrer.", function()
		ns.UpdateSpellBookTab()
	end)

	Settings.RegisterAddOnCategory(category)
end

ns.On("PLAYER_LOGIN", CreateOptions)

ns.OnToggle(function()
	if enabledSetting then
		enabledSetting:NotifyUpdate()
	end
end)

ns.commands.options = function()
	if InCombatLockdown() then
		ns.Print("Optionen im Kampf nicht verfügbar.")
		return
	end
	Settings.OpenToCategory(category:GetID())
end
