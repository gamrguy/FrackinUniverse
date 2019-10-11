require '/scripts/util.lua'
require '/objects/power/scripts/power.lua'
require "/scripts/kheAA/transferUtil.lua"

function power.preInit()
	self.heatData = config.getParameter('heat')
	self.fuelList = config.getParameter('acceptablefuel')
	storage.heatState = storage.heatState or 1
	storage.heat = storage.heat or 0	
	storage.fueltime = storage.fueltime or 0
	restoreState()
end

function power.postInit()
	transferUtil.init()
end

function power.onBecomeIdle()
	storage.heat = 0
	storage.heatState = 1
	applyState(self.heatData.heatStates[1])
	object.setLightColor({0,0,0})
end

function power.preUpdate(dt)
	transferUtil.loadSelfContainer()
	
	if storage.fueltime > 0 then
		storage.fueltime = math.max(storage.fueltime - dt,0)
	end
	
	if storage.fueltime == 0 then
		item = world.containerItemAt(entity.id(),0)
		if item and self.fuelList[item.name] then
			world.containerConsumeAt(entity.id(),0,1)
			storage.fueltime = self.fuelList[item.name]
		end
	end
	updateHeat(dt)
end

function updateHeat(dt)
	if storage.fueltime > 0 then
		storage.heat = math.min(storage.heat + dt * 0.05, 1)
	else
		storage.heat = math.max(storage.heat - dt * 0.05, 0)
	end
	power.setGenRate(self.heatData.maxPowerGen * storage.heat)
	
	local newLight = {}
	for i = 1,3 do
		newLight[i] = math.min(self.heatData.maxLight[i], util.lerp(storage.heat, 0, self.heatData.maxLight[i]))
	end
	object.setLightColor(newLight)
	
	local nextState = self.heatData.heatStates[storage.heatState + 1]
	local prevState = self.heatData.heatStates[storage.heatState - 1]
	if nextState and storage.heat >= nextState.heat then
		storage.heatState = storage.heatState + 1
		applyState(nextState)
	elseif prevState and storage.heat <= prevState.heat then
		storage.heatState = storage.heatState - 1
		applyState(prevState)
	end
end

function applyState(state)
	if state.sound ~= nil then object.setSoundEffectEnabled(state.sound) end
	for key,value in pairs(state.animator or {}) do
		animator.setAnimationState(key, value)
	end
end

-- Restores the current heat state when loading the object
function restoreState()
	for i = 1,storage.heatState do
		applyState(self.heatData.heatStates[i] or {})
	end
end
