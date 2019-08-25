require '/scripts/fu_storageutils.lua'
require '/scripts/kheAA/transferUtil.lua'
require '/objects/power/power.lua'

function power.postInit()
	transferUtil.init()
	transferUtil.loadSelfContainer()
	object.setInteractive(true)
	
	storage.currentinput = nil
	storage.currentoutput = nil
	storage.bonusoutputtable = nil

	self.extraConsumptionChance = powerVars.furnaceWasteChance
	self.timer = self.timerInitial
end

function power.preUpdate(dt)
	if not storage.currentoutput and oreCheck() and clearSlotCheck(storage.currentoutput) then
		if world.containerConsume(entity.id(), {name = storage.currentinput, count = 2, data={}}) then
			if math.random() <= self.extraConsumptionChance then
				world.containerConsume(entity.id(), {name = storage.currentinput, count = 2, data={}})
			end
			storage.timer = powerVars.furnaceTimer
		else
			storage.currentoutput = nil
		end
	end
end

function power.postUpdate(dt)
	if power.hasConsumedEnergy() then
		storage.timer = storage.timer - dt
				if hasBonusOutputs(storage.currentinput) then
					for key, value in pairs(storage.bonusoutputtable) do
						if clearSlotCheck(key) and math.random(1,100) <= value then 
							fu_sendOrStoreItems(0, {name = key, count = 1, data = {}}, {0}, true)
						end
					end
				end
				fu_sendOrStoreItems(0, {name = storage.currentoutput, count = math.random(1,2), data = {}}, {0}, true)
				self.timer = self.timerInitial
			end
		end
	end
end



function oreCheck()
	local content = world.containerItemAt(entity.id(),0)
	storage.currentoutput = nil
	if content then
		if content.name == currentinput then return true end
		local item = config.getParameter("inputsToOutputs")
		if item[content.name] then
			storage.currentinput = content.name
			storage.currentoutput = item[content.name]
			return true
		else
			return false
		end
	else
		return false
	end
end

function clearSlotCheck(checkname)
	return world.containerItemsCanFit(entity.id(), {name= checkname, count=1, data={}}) > 0
end

function hasBonusOutputs(checkname)
	local content = world.containerItemAt(entity.id(),0)
	if content then
		local item = config.getParameter("bonusOutputs")
		if item[content.name] then
			storage.bonusoutputtable = item[content.name]
			return true
		else
			return false
		end
	else
		return false
	end
end