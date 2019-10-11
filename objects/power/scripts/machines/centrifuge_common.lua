require "/scripts/fu_storageutils.lua"
require "/scripts/kheAA/transferUtil.lua"
require '/objects/power/scripts/power.lua'

function power.preInit()
	transferUtil.init()
	transferUtil.loadSelfContainer()

	self.centrifugeType = config.getParameter("centrifugeType") or error("centrifugeType is undefined in .object file") -- die horribly

	self.itemChances = config.getParameter("itemChances")
	self.inputSlot = config.getParameter("inputSlot",1)
	self.inputSlots = {}
	for i=0,self.inputSlot do
		self.inputSlots[i] = true
	end

	self.initialCraftDelay = config.getParameter("craftDelay",0)
	storage.craftDelay = storage.craftDelay or self.initialCraftDelay
	storage.combsProcessed = storage.combsProcessed or { count = 0 }
	--sb.logInfo("centrifuge: %s", storage.combsProcessed)

	self.combsPerJar = 3 -- ref. recipes

	self.recipeTable = root.assetJson("/objects/power/recipes_centrifuge.config")
	self.recipeTypes = self.recipeTable.recipeTypes[self.centrifugeType]

	object.setInteractive(true)
end

function deciding(item)
	for i=#self.recipeTypes,1,-1 do
		if self.recipeTable[self.recipeTypes[i]][item.name] then
			return self.recipeTable[self.recipeTypes[i]][item.name]
		end
	end
	return nil
end

function power.postUpdate(dt)
	if storage.input and power.hasConsumedEnergy() then
		if storage.timer > 0 then
			storage.timer = math.max(storage.timer - dt,0)
		elseif storage.timer == 0 then
			stashHoney(storage.input.name)
			storage.input = nil
			local rnd = math.random()
			for item, chancePair in pairs(storage.output) do
				local chanceBase,chanceDivisor = table.unpack(chancePair)
				local chance = self.itemChances[chanceBase] / chanceDivisor
				local done=false
				local throw=nil
				if rnd <= chance then
					fu_newStoreItems({name=item, count=1, data={}}, self.inputSlots, true)
				end
				rnd = rnd - chance
			end
			power.setConsumeRate(0)
		end
	end

	if storage.combsProcessed and storage.combsProcessed.count > 0 then
		-- discard the stash if unclaimed by a jarrer within a reasonable time (twice the craft delay)
		storage.combsProcessed.stale = (storage.combsProcessed.stale or (self.initialCraftDelay * 2)) - dt
		if storage.combsProcessed.stale == 0 then
			drawHoney() -- effectively clear the stash, stopping the jarrer from getting it
		end
	end

	-- Grab the current centrifuge/sifter recipe
	-- Start processing last - this is better for the flow of operations
	-- Having this here means you can both output and start in the same update,
	-- and processing doesn't start with one "free" update when it begins
	if not storage.input then
		local input
		local found
		for i=0,self.inputSlot do
			input = world.containerItemAt(entity.id(),i)
			if input then
				local output = deciding(input)
				if output then
					storage.output = output
					storage.input = input
					storage.timer = self.initialCraftDelay
					break
				end
			end
		end
		if storage.input then
			-- Take an item and begin consuming power
			world.containerConsume(entity.id(), { name = storage.input.name, count = 1, data={}})
			power.setConsumeRate(powerVars.centrifugePower)
		end
	end
end

function stashHoney(comb)
	-- For any nearby jarrer (if this is an industrial centrifuge),
	-- Record that we've processed a comb.
	-- The stashed type is the jar object name for the comb type.
	-- If the stashed type is different, reset the count.

	local jar = honeyCheck and honeyCheck(comb)

	if jar then
		if storage.combsProcessed == nil then storage.combsProcessed = { count = 0 } end
		if storage.combsProcessed.type == jar then
			storage.combsProcessed.count = math.min(storage.combsProcessed.count + 1, self.combsPerJar) -- limit to one jar's worth	in stash at any given time
			storage.combsProcessed.stale = nil
		else
			storage.combsProcessed = { type = jar, count = 1 }
		end
		--sb.logInfo("STASH: %s %s", storage.combsProcessed.count,storage.combsProcessed.type)
	end
end

-- Called by the honey jarrer
function drawHoney()
	if not storage.combsProcessed or storage.combsProcessed.count == 0 then return nil end
	local ret = storage.combsProcessed
	storage.combsProcessed = { count = 0 }
	--sb.logInfo("STASH: Withdrawing")
	return ret
end
