--[[
Generic script for pretty much anything utilizing the power system.
---  By Lucca  ---
]]

power = {}

-- Hooks for scripting purposes. Override these to integrate seamlessly with the system
function power.preInit() end
function power.postInit() end
function power.preUpdate() end
function power.postUpdate() end
function power.preNodeConnectionChange() end
function power.postNodeConnectionChange() end

function init()
	if not power.didSetup then
		power.inputNode = config.getParameter("powerInputNode", nil)                           -- Power input node (currently unused; any node will work)
		power.outputNode = config.getParameter("powerOutputNode", nil)                         -- Power output node
		power.connectedConsumers = { battery = {}, normal = {} }                               -- Consumers connected to this device
		power.maxEnergy = config.getParameter("maxEnergy", 0)                                  -- Maximum energy storable by this device
		power.produces = config.getParameter("producesEnergy", false)                          -- Whether this device sends energy to other devices
		power.consumes = config.getParameter("consumesEnergy", false)                          -- Whether this device receives energy from other devices
		power.energyPushCap = config.getParameter("energyPushCap", nil)                        -- Cap on the energy pushed from this device, per second
		--power.priority = config.getParameter("powerPriority", 2)                               -- Priority of this device. Higher-priority devices are powered first.
		storage.energyGen = storage.energyGen or 0                                             -- Amount of energy this device is producing per second
		storage.energyConsume = storage.energyConsume or 0                                     -- Amount of energy this device consumes per second
		storage.storedEnergy = storage.storedEnergy or config.getParameter("storedEnergy", 0)  -- Energy currently stored by this device
		--storage.isFull = storage.isFull or storage.storedEnergy >= power.maxEnergy             -- Whether this device is full
		power.didSetup = true
	end
	if power.preInit() ~= false then
		power.init()
	end
	power.postInit()
end

function update(dt)
	if power.preUpdate(dt) ~= false then
		power.update(dt)
	end
	power.postUpdate(dt)
end

function onNodeConnectionChange()
	if power.preNodeConnectionChange() ~= false then
		power.onNodeConnectionChange()
	end
	power.postNodeConnectionChange()
end

function power.init()
	power.onNodeConnectionChange()
end

function power.update(dt)
	-- Insurance policy
	if not power.warmedUp then
		power.init()
		power.warmedUp=true
	end
	
	-- Generate energy passively
	if storage.energyGen > 0 then
		power.receiveEnergy(storage.energyGen * dt)
	end
	
	-- Consume energy passively
	if storage.energyConsume > 0 then
		local powerToConsume = storage.energyConsume * dt
		if powerToConsume > storage.storedEnergy then
			storage.notEnoughPower = true
		else
			power.removeEnergy(powerToConsume)
			storage.notEnoughPower = false
		end
	end
	
	-- If this is a producer, attempt to send power to connected consumers
	-- Batteries have lowered priority and only get sent to if there's leftover power
	local sentPower = false
	if power.produces and storage.storedEnergy > 0 then
		local powerPacket = math.min(storage.storedEnergy, power.energyPushCap * dt)
		local powerPerDevice = powerPacket / #power.connectedConsumers.normal
		for _,device in pairs(power.connectedConsumers.normal) do
			local leftovers = power.transferEnergy(powerPerDevice, device)
			if leftovers < powerPerDevice then sentPower = true end
			powerPacket = powerPacket + leftovers
			powerPerDevice = powerPacket / #power.connectedConsumers.normal
		end
		if powerPacket > 0 then
			powerPerDevice = powerPacket / #power.connectedConsumers.battery
			for _,device in pairs(power.connectedConsumers.battery) do
				local leftovers = power.transferEnergy(powerPerDevice, device)
				if leftovers < powerPerDevice then sentPower = true end
				powerPacket = powerPacket + leftovers
				powerPerDevice = powerPacket / #power.connectedConsumers.battery
			end
		end
	end
	if power.produces and power.outputNode then object.setOutputNodeLevel(power.outputNode, sentPower) end
end

function power.hasConsumedEnergy()
	return not storage.notEnoughPower
end

function power.hasNotConsumedEnergy()
	return storage.notEnoughPower
end

function power.getConsumeRate()
	return storage.energyConsume
end

function power.setConsumeRate(energy)
	storage.energyConsume = energy
end

function power.getStorageLeft()
	return power.maxEnergy - storage.storedEnergy
end

function power.setMaxEnergy(energy)
	power.maxEnergy = energy
	storage.storedEnergy = math.min(storage.storedEnergy, energy)
end

function power.getMaxEnergy()
	return power.maxEnergy
end

function power.setStoredEnergy(energy)
	storage.storedEnergy = math.min(power.maxEnergy, energy)
end

function power.getStoredEnergy()
	return storage.storedEnergy
end

-- Subtracts power from the device's storage.
-- Returns the amount of energy that couldn't be removed.
function power.removeEnergy(energy)
	local newEnergy = storage.storedEnergy - energy
	storage.storedEnergy = math.max(newEnergy, 0)
	--if storage.isFull and storage.storedEnergy < power.maxEnergy then
		-- We're full - broadcast to stop powering this device
	--end
	return storage.storedEnergy - newEnergy
end

-- Adds power to the device's storage.
-- Returns the excess energy, if any.
function power.receiveEnergy(energy)
	sb.logInfo("Received "..energy.." energy")
	local newEnergy = storage.storedEnergy + energy
	storage.storedEnergy = math.min(newEnergy, power.maxEnergy)
	return newEnergy - storage.storedEnergy
end

-- Attempts to transfer energy from this device to the other device.
-- If energy couldn't be sent, it is returned to this device.
-- Returns the amount of leftover energy.
function power.transferEnergy(energy, device)
	local failed = power.removeEnergy(energy)
	local leftover = callEntity(device, "power.receiveEnergy", energy - failed) or energy
	if leftover > 0 then power.receiveEnergy(leftover) end
	return leftover
end

function power.onNodeConnectionChange(arg)
	if power.produces and power.outputNode then
		power.connectedConsumers = { battery = {}, normal = {} }
		if object.isOutputNodeConnected(power.outputNode) then
			for e,_ in pairs(object.getOutputNodeIds(power.outputNode)) do
				sb.logInfo(e)
				if callEntity(e, "isConsumer") then
					if callEntity(e, "config.getParameter", "isBattery") then
						table.insert(power.connectedConsumers.battery, e)
					else
						table.insert(power.connectedConsumers.normal, e)
					end
				end
			end
		end
	end
end

function isConsumer()
	return power.consumes
end

function callEntity(id,...)
	if world.entityExists(id) then
		return world.callScriptedEntity(id,...)
	end
end