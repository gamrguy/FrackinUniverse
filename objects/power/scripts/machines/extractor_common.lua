require '/scripts/fu_storageutils.lua'
require '/scripts/kheAA/transferUtil.lua'
require '/objects/power/scripts/power.lua'
local recipes

function power.postInit()
	transferUtil.init()
	transferUtil.loadSelfContainer()
	self.timer = self.timer or self.mintick
	self.crafting = false
	self.output = nil
	self.light = config.getParameter("lightColor")

	if self.light then
		object.setLightColor({0, 0, 0, 0})
	end

	-- Stores the input slot values as keys. For later use.
	self.inputSlots_inv = {}
	for i in pairs(powerVars.inputSlots) do
		self.inputSlots_inv[i] = true
	end

	recipes = root.assetJson(powerVars.extractRecipes or "/objects/power/recipes_extractor.config")

	self.recipeCache = {}
	-- generate recipe cache for fast lookups
	for _,recipe in pairs(recipes) do
		for input,_ in pairs(recipe.inputs) do
			if not self.recipeCache[input] then
				self.recipeCache[input] = {}
			end
			table.insert(self.recipeCache[input], recipe)
		end
		if recipe.reversible then
			local reversed = nil
			for output,_ in pairs(recipe.outputs) do
				if not self.recipeCache[output] then
					self.recipeCache[output] = {}
				end
				if not reversed then
					reversed = { inputs = recipe.outputs, outputs = recipe.inputs, timeScale = recipe.timeScale }
				end
				table.insert(self.recipeCache[output], reversed)
			end
			recipe.reversible = nil
		end
	end
end

function power.postUpdate(dt)
	if power.hasConsumedEnergy() then
		if storage.craftRecipe then
			storage.craftTimer = storage.craftTimer - dt
			if storage.craftTimer <= 0 then
				for k,v in pairs(storage.craftRecipe.outputs) do
					local avoid = self.inputSlots_inv
					fu_newStoreItems({name = k, count = techlevelMap(v)}, avoid, true)
				end
				storage.craftRecipe = nil
				power.setConsumeRate(0)
			end
		end
	end
	
	if not storage.craftRecipe and not startCrafting(getInputContents()) then
		if self.light then
			object.setLightColor({0, 0, 0, 0})
		end
	end
end

-- Enable "self-powering" for unpowered extraction devices
-- Basically tricks power.lua into thinking the device always has power
function power.getStoredEnergy()
	return (not powerVars.extractPower and 100) or powerVars.storedEnergy
end

function startCrafting(inputs)
	local craftRecipe = nil
	for _,input in ipairs(inputs) do
		if self.recipeCache[input.name] then
			for _,recipe in ipairs(self.recipeCache[input.name]) do
				craftRecipe = recipe
				for rInput,req in pairs(recipe.inputs) do
					if inputs[rInput] and inputs[rInput] < techlevelMap(req) then
						craftRecipe = nil
						break
					end
				end
				if craftRecipe then break end
			end
		end
		if craftRecipe then break end
	end

	if craftRecipe then
		for k, v in pairs(craftRecipe.inputs) do
			world.containerConsume(entity.id(), {item = k , count = techlevelMap(v)})
		end
		storage.craftTimer = ((techlevelMap(craftRecipe.timeScale) or 1) * powerVars.extractTime)
		storage.craftRecipe = craftRecipe
		if self.light then
			object.setLightColor(self.light)
		end
		power.setConsumeRate(powerVars.extractPower or 1)
	else
		return false
	end		
end

function techlevelMap(v)
	-- if the input is a table, do a lookup using the extractor tech level
	if type(v) == "table" then return v[powerVars.techLevel] end
	return v
end

function getInputContents()
	local contents = {}
	for i in ipairs(powerVars.inputSlots) do
		local item = world.containerItemAt(entity.id(),i)
		if item then
			table.insert(contents, item)
			if not contents[item.name] then
				contents[item.name] = item.count
			else
				contents[item.name] = contents[item.name] + item.count
			end
		end
	end
	return contents
end

--[[	Validation code - run only from a command shell

		require "extractionlab_common.lua"
		validateRecipes()

	Example test data, if not using live recipes:
	{ inputs = { a = 1 }, outputs = { b = 1 } }, -- loop
	{ inputs = { b = 1 }, outputs = { c = 1 } }, -- loop
	{ inputs = { c = 1 }, outputs = { a = 1 } }, -- loop
	{ inputs = { d = 1 }, outputs = { e = 1 } }, -- reversible
	{ inputs = { e = 1 }, outputs = { d = 1 } }, -- reversible
	{ inputs = { f = 1 }, outputs = { g = 2 } }, -- mismatch
	{ inputs = { g = 1 }, outputs = { f = 2 } }, -- mismatch
	{ inputs = { h = 1 }, outputs = { i = i } } -- control
]]
function validateRecipes(testData)
	testData = testData or recipes

	local printfunc = sb and sb.logWarn or print

	local ikeys = {}
	local okeys = {}
	local pair = {}

	for i = 1, table.getn(testData) do
		ikeys[i] = {}
		okeys[i] = {}
		for key, _ in pairs(testData[i].inputs) do
			table.insert(ikeys[i], key)
		end
		for key, _ in pairs(testData[i].outputs) do
			table.insert(okeys[i], key)
		end
	end

	-- http://stackoverflow.com/questions/25922437/how-can-i-deep-compare-2-lua-tables-which-may-or-may-not-have-tables-as-keys
	local table_eq
	table_eq = function(table1, table2)
		local avoid_loops = {}
		local function recurse(t1, t2)
			-- compare value types
			if type(t1) ~= type(t2) then return false end
			-- Base case: compare simple values
			if type(t1) ~= "table" then return t1 == t2 end
			-- Now, on to tables.
			-- First, let's avoid looping forever.
			if avoid_loops[t1] then return avoid_loops[t1] == t2 end
			avoid_loops[t1] = t2
			-- Copy keys from t2
			local t2keys = {}
			local t2tablekeys = {}
			for k, _ in pairs(t2) do
				if type(k) == "table" then table.insert(t2tablekeys, k) end
				t2keys[k] = true
			end
			-- Let's iterate keys from t1
			for k1, v1 in pairs(t1) do
				local v2 = t2[k1]
				if type(k1) == "table" then
					-- if key is a table, we need to find an equivalent one.
					local ok = false
					for i, tk in ipairs(t2tablekeys) do
						if table_eq(k1, tk) and recurse(v1, t2[tk]) then
							table.remove(t2tablekeys, i)
							t2keys[tk] = nil
							ok = true
							break
						end
					end
					if not ok then return false end
				else
					-- t1 has a key which t2 doesn't have, fail.
					if v2 == nil then return false end
					t2keys[k1] = nil
					if not recurse(v1, v2) then return false end
				end
			end
			-- if t2 has a key which t1 doesn't have, fail.
			if next(t2keys) then return false end
			return true
		end
		return recurse(table1, table2)
	end

	local containsAll = function (full, partial)
		local fullmatch = true
		for _, i in pairs(partial) do
			local match = false
			for _, j in pairs(full) do
				if i == j then match = true break end
			end
			if not match then fullmatch = false end
		end
		return fullmatch
	end

	local containsAny = function(full, partial)
		for _, i in pairs(partial) do
			for _, j in pairs(full) do
				if i == j then return true end
			end
		end
		return false
	end

	local dumpChain = function(chain)
		local ret = ''
		for _,v in ipairs(chain) do
			ret = ret .. ' ' .. ikeys[v][1]
		end
		return ret
	end

	local huntOutput
	huntOutput = function(chain)
		local last = chain[table.getn(chain)]
		for i = 1, table.getn(testData) do
			if i ~= last and containsAny(ikeys[i], okeys[last]) then
				if --[[containsAny(chain, {i})]] i == chain[1] then
					printfunc("chain loop:" .. dumpChain(chain))
				elseif not containsAny(chain, {i}) then
					table.insert(chain, i)
					huntOutput(chain)
					table.remove(chain, table.getn(chain))
				end
			end
		end
	end

	for i = 1, table.getn(testData) - 1 do
		for j = i + 1, table.getn(testData) do
			if containsAll(ikeys[i], okeys[j]) and containsAll(okeys[i], ikeys[j]) then
				if table_eq(testData[i].inputs, testData[j].outputs) and table_eq(testData[i].outputs, testData[j].inputs) then
					printfunc(string.format("reversible: %s <-> %s", ikeys[i][1], ikeys[j][1]))
					pair[i] = true
					pair[j] = true
				else
					printfunc(string.format("mismatched pair: %s <-> %s", ikeys[i][1], ikeys[j][1]))
					pair[i] = true
					pair[j] = true
				end
			end
		end

		if not pair[i] then huntOutput({i}) end
	end
	huntOutput({table.getn(testData)}) -- last entry
end
