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
	table.insert(UISpecialFrames, name)
	frame:Hide()
	return frame
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
