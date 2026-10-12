local _, ns = ...

local PREFIX = "|cff7fd4ffSanity Enricher|r: "

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

function ns.SafeID(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end
