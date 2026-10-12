local _, ns = ...

-- Scan-Button ueber dem Auktionshausfenster. Blizzard_AuctionHouseUI wird erst beim
-- ersten Oeffnen des Auktionshauses geladen.

local button

local function UpdateButton()
	if not button then
		return
	end
	local progress = ns.ScanProgress()
	local cooldown = ns.ScanCooldownRemaining()
	if progress then
		button:SetText(("Scan läuft … %d%%"):format(progress * 100))
		button:Disable()
	elseif cooldown > 0 then
		button:SetText("Scan bereit in " .. ns.FormatDuration(cooldown))
		button:Disable()
	else
		button:SetText("Kontor: Komplett-Scan")
		button:Enable()
	end
end

ns.OnScanProgress = UpdateButton

local function CreateButton()
	if button or not AuctionHouseFrame then
		return
	end
	button = CreateFrame("Button", "KontorScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
	button:SetSize(180, 22)
	button:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 2)
	button:SetScript("OnClick", function()
		ns.StartScan()
	end)
	-- Countdown jede Sekunde aktualisieren, solange das Auktionshaus offen ist
	local elapsed = 0
	button:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 1 then
			elapsed = 0
			UpdateButton()
		end
	end)
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnEnter", function(self)
		local realm = ns.RealmData()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Kontor: Komplett-Scan")
		GameTooltip:AddLine("Liest alle Auktionen auf einmal und speichert einen Snapshot.", 1, 1, 1, true)
		if realm.lastScan then
			GameTooltip:AddDoubleLine("Letzter Scan", ns.DateTime(realm.lastScan.meta.time) .. " (" .. ns.Ago(realm.lastScan.meta.time) .. ")")
		end
		local cooldown = ns.ScanCooldownRemaining()
		if cooldown > 0 and not ns.IsScanning() then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("Der Server erlaubt vermutlich nur alle 15 Minuten einen Komplett-Scan. Nächster Scan in %s."):format(ns.FormatDuration(cooldown)), 1, 0.82, 0, true)
			GameTooltip:AddLine("Erzwingen: /kontor scan force", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	UpdateButton()
end

ns.On("ADDON_LOADED", function(name)
	if name == "Blizzard_AuctionHouseUI" then
		CreateButton()
	end
end)

ns.On("PLAYER_LOGIN", function()
	if C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
		CreateButton()
	end
end)
