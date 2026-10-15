local _, ns = ...

-- Rezepte erfassen, sobald ein eigenes Berufe-Fenster offen und geladen ist.
-- Gespeichert pro Charakter und Beruf:
--   db.characters["Name-Realm"].professions["Tailoring"].recipes[recipeID] =
--     { id, name, out = itemID, qmin, qmax, reagents = { { itemID, qty }, ... } }
-- Es werden nur Pflicht-Basisreagenzien beruecksichtigt (keine optionalen Zusaetze).

local CAPTURE_DELAY = 0.5

local function Call(name, ...)
	local fn = C_TradeSkillUI[name]
	if fn then
		return fn(...)
	end
end

function ns.CharacterKey()
	return UnitName("player") .. "-" .. GetRealmName()
end

local function CharacterData(key)
	ns.db.characters = ns.db.characters or {}
	key = key or ns.CharacterKey()
	local c = ns.db.characters[key]
	if not c then
		c = { professions = {} }
		ns.db.characters[key] = c
	end
	return c
end

-- Rezept aus dem aktuellen Schema lesen (funktioniert fuer die Rezepte des offenen Berufs)
function ns.RecipeFromSchematic(recipeID)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic or not schematic.outputItemID then
		return nil -- z.B. Verzauberungen ohne Ergebnis-Item
	end
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if slot.required and slot.reagentType == Enum.CraftingReagentType.Basic and reagent and reagent.itemID then
			reagents[#reagents + 1] = { itemID = reagent.itemID, qty = slot.quantityRequired }
		end
	end
	return {
		id = recipeID,
		name = schematic.name,
		out = schematic.outputItemID,
		qmin = schematic.quantityMin or 1,
		qmax = schematic.quantityMax or schematic.quantityMin or 1,
		reagents = reagents,
	}
end

function ns.CurrentProfessionName()
	local info = Call("GetBaseProfessionInfo")
	return info and info.professionName
end

local function IsOwnTradeSkill()
	if not Call("IsTradeSkillReady") or Call("IsDataSourceChanging") then
		return false
	end
	return not (Call("IsTradeSkillLinked") or Call("IsTradeSkillGuild") or Call("IsNPCCrafting"))
end

local indexCache = {}

local function Capture()
	if not IsOwnTradeSkill() then
		return
	end
	local info = Call("GetBaseProfessionInfo")
	if not info or not info.professionName then
		return
	end
	-- GetAllRecipeIDs ist auf Forever nicht dokumentiert; GetFilteredRecipeIDs haengt von Suchfiltern ab.
	-- Deshalb werden Rezepte nur hinzugefuegt/aktualisiert, nie entfernt.
	local ids = Call("GetAllRecipeIDs") or Call("GetFilteredRecipeIDs") or {}
	local professions = CharacterData().professions
	local store = professions[info.professionName] or { recipes = {} }
	professions[info.professionName] = store
	store.professionID, store.skill, store.maxSkill, store.scanned =
		info.professionID, info.skillLevel, info.maxSkillLevel, time()

	local added = 0
	for _, recipeID in ipairs(ids) do
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipeInfo and recipeInfo.learned and not recipeInfo.isDummyRecipe then
			local recipe = ns.RecipeFromSchematic(recipeID)
			if recipe then
				added = added + (store.recipes[recipeID] and 0 or 1)
				store.recipes[recipeID] = recipe
			end
		end
	end
	indexCache = {}
	if added > 0 then
		ns.Print("%s: %d Rezepte erfasst.", info.professionName, added)
	end
	if ns.OnRecipesChanged then
		ns.OnRecipesChanged()
	end
end

local pending = false
local function ScheduleCapture()
	if pending then
		return
	end
	pending = true
	C_Timer.After(CAPTURE_DELAY, function()
		pending = false
		local ok, err = pcall(Capture)
		if not ok then
			ns.Print("Rezepte konnten nicht erfasst werden: %s", tostring(err))
		end
	end)
end

ns.On("TRADE_SKILL_SHOW", ScheduleCapture)
ns.On("TRADE_SKILL_LIST_UPDATE", ScheduleCapture)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", ScheduleCapture)
ns.On("NEW_RECIPE_LEARNED", ScheduleCapture)

-- Alle gespeicherten Berufe: Liste von { character, profession, recipes }
function ns.AllProfessions()
	local list = {}
	for charKey, c in pairs(ns.db.characters or {}) do
		for profession, store in pairs(c.professions) do
			list[#list + 1] = { character = charKey, profession = profession, recipes = store.recipes }
		end
	end
	return list
end

-- Welche Rezepte eines Charakters/Berufs stellen ein Item her? (fuer Zwischenprodukte)
function ns.RecipesProducing(charKey, profession)
	local cacheKey = charKey .. "|" .. profession
	local index = indexCache[cacheKey]
	if not index then
		index = {}
		local c = ns.db.characters and ns.db.characters[charKey]
		local store = c and c.professions[profession]
		for _, recipe in pairs(store and store.recipes or {}) do
			index[recipe.out] = index[recipe.out] or {}
			table.insert(index[recipe.out], recipe)
		end
		indexCache[cacheKey] = index
	end
	return index
end
