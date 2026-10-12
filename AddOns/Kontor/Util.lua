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
