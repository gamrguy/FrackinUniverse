require "/scripts/fu_storageutils.lua"
require "/scripts/kheAA/transferUtil.lua"
require '/objects/power/power.lua'
local deltaTime=0


function power.preInit()
	transferUtil.init()

	self.centrifugeType = config.getParameter("centrifugeType") or error("centrifugeType is undefined in .object file") -- die horribly

	self.itemChances = config.getParameter("itemChances")
	self.inputSlot = config.getParameter("inputSlot",1)

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

function power.preUpdate(dt)
	-- Transfer network updatey thing
	if deltaTime>1 then
		transferUtil.loadSelfContainer()
		deltaTime=0
	else
		deltaTime=deltaTime+dt
	end
	
	-- Grab the current centrifuge/sifter recipe
	if not storage.input then
		local input
		local found
		for i=0,self.inputSlot-1 do
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
			power.setConsumeRate(config.getParameter("energyConsume"))
			wakeUp()
		else
			-- No input; enter idle mode
			becomeIdle()
		end
	end
end

function power.postUpdate(dt)
	if power.hasConsumedEnergy() then
		wakeUp()
		if storage.timer > 0 then
			storage.timer = math.max(storage.timer - dt,0)
		elseif storage.timer == 0 then
			stashHoney(storage.input.name)
			storage.input = nil
			storage.activeConsumption = false
			local rnd = math.random()
			for item, chancePair in pairs(storage.output) do
				local chanceBase,chanceDivisor = table.unpack(chancePair)
				local chance = self.itemChances[chanceBase] / chanceDivisor
				local done=false
				local throw=nil
				if rnd <= chance then
					local contSize=world.containerSize(entity.id())
					for i=self.inputSlot,contSize-1 do
						throw = world.containerPutItemsAt(entity.id(), { name = item, count = 1, data={}},i)
						if not throw then
							done=true
							break
						end
					end
					if done then
						break
					end
				end
				if throw then world.spawnItem(throw, entity.position()) end -- hope that the player or an NPC which collects items is around
				rnd = rnd - chance
			end
		end
	else
		becomeIdle()
	end

	if storage.combsProcessed and storage.combsProcessed.count > 0 then
		-- discard the stash if unclaimed by a jarrer within a reasonable time (twice the craft delay)
		storage.combsProcessed.stale = (storage.combsProcessed.stale or (self.initialCraftDelay * 2)) - dt
		if storage.combsProcessed.stale == 0 then
			drawHoney() -- effectively clear the stash, stopping the jarrer from getting it
		end
	end
end

function becomeIdle()
	if not storage.idle then
		storage.idle = true
		animator.setAnimationState("centrifuge", "idle")
		storage.activeConsumption = false
	end
end

function wakeUp()
	if storage.idle then
		storage.idle = false
		animator.setAnimationState("centrifuge", "working")
		storage.activeConsumption = true
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