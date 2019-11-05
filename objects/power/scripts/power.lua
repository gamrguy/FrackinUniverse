--[[
Generic script for pretty much anything utilizing the power system.
---  By Lucca  ---

Object settings:

	"power" : {
		"logicNodes" : [],     // Logical input nodes, for turning the device on and off
		"inputNodes" : [],     // Power input nodes
		"outputNodes" : [],    // Power output nodes
		"produces" : true,     // Whether this device produces (sends) energy
		"consumes" : true,     // Whether this device receives energy from producers
		"maxEnergy" : 1000,    // Amount of U this device can store internally
		"storedEnergy" : 1000, // Energy stored in this device. Typically used as a battery parameter for persistent storage.
		"maxPushRate" : 100,   // Maximum amount of energy that can be pushed, per second, from this device (if a producer)

		"relayDraw" : 100,     // Maximum amount of energy that a Relay will reserve transportation space for this device.
							   // A Relay will add up the total value of its connections and use that to determine its energy storage.
							   // Machines will individually use this to determine how much energy they can receive per second.
							   // Higher values means more energy can be put through at once.
							   // Always set higher than the machine's possible consumption rate!

		"priority" : 0,        // Priority; devices with higher priority are powered first
		
		"animStates" : {       // Animation states for various power-related status.
			"active" : {},     // Device is active (for machine running animations)
			"inactive" : {},   // Device is inactive (for machine running animations)
			
			"off" : {},        // The device is inactive. (for informative lights)
			"deficit" : {},    // The device is active, but was unable to consume power this update or the last. (for informative lights)
			"unstable" : {},   // The device consumed power this update, but is losing power in storage. (for informative lights)
			"stable" : {},     // The device is active and has a stable power flow. (for informative lights)
			
			"idle" : {},       // Idle state. (apply to both running animations and informative lights)
			
			"powerMeter" : {   // A subset of animations for displaying the current power level. Optional.
				{ "level" : 30, "anims" : {} },
				{ "level" : 50, "anims" : {} }
				...
			}
		}
	}
]]
require '/scripts/util.lua'


power = {}
powerVars = {}

-- Hooks for scripting purposes. Override these to integrate seamlessly with the system
function power.preInit() end
function power.postInit() end
function power.preUpdate() end
function power.postUpdate() end
function power.preNodeConnectionChange() end
function power.postNodeConnectionChange() end
function power.onBecomeIdle() end
function power.onWakeUp() end

function init()
	if not power.didSetup then
		local conf = config.getParameter('power')
		if not storage.powerVars then storage.powerVars = {} end
		local stored = storage.powerVars
		powerVars = {
			logicNodes = {},
			inputNodes = {},
			outputNodes = {},
			produces = false,
			consumes = false,
			maxEnergy = 0,
			storedEnergy = 0,
			maxPushRate = 0,
			genRate = 0,
			consumeRate = 0,
			priority = 0,
			idle = false,
			relayRefreshTime = 0,
			relayRemaining = 0,
			animStates = {}
		}
		powerVars = util.mergeTable(powerVars, util.mergeTable(conf, stored))
		powerVars.connected = { all = {}, producers = {}, consumers = {} }
		powerVars.priorityIndex = {}
		
		power.didSetup = true
		if powerVars.meterPos then
			power.applyAnims(powerVars.animStates.powerMeter[powerVars.meterPos].anims)
		end
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

function onInputNodeChange()
	power.onInputNodeChange()
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
	if power.getGenRate() > 0 then
		power.receiveEnergy(power.getGenRate() * dt)
	end
	
	-- Consume energy passively
	if power.getConsumeRate() > 0 then
		local powerToConsume = power.getConsumeRate() * dt
		local consumedPower = true
		if powerToConsume > power.getStoredEnergy() then
			consumedPower = false
		else
			power.removeEnergy(powerToConsume)
			power.applyAnims(powerVars.animStates.active)
		end
		power.setVar('consumedPower', consumedPower)
		if consumedPower and powerVars.consumedPowerPrev then
			if powerVars.storedEnergyPrev then
				if powerVars.storedEnergyPrev > power.getStoredEnergy() then
					power.applyAnims(powerVars.animStates.unstable)
				elseif powerVars.storedEnergyPrev <= power.getStoredEnergy() then
					power.applyAnims(powerVars.animStates.stable)
				end
			end
		else
			power.applyAnims(powerVars.animStates.deficit)
		end
		power.setVar('storedEnergyPrev', power.getStoredEnergy())
		power.setVar('consumedPowerPrev', consumedPower)
		if not consumedPower then
			power.applyAnims(powerVars.animStates.inactive)
		end
	elseif powerVars.consumes then
		power.setVar('consumedPower', false)
		power.applyAnims(powerVars.animStates.inactive)
		power.applyAnims(powerVars.animStates.off)
	end
	
	-- If this is a producer, attempt to send power to connected consumers
	-- Batteries have lowered priority and only get sent to if there's leftover power
	local sentPower = false
	if powerVars.produces and power.getStoredEnergy() > 0 then
		local consumers = powerVars.connected.consumers
		local powerPacket = math.min(power.getStoredEnergy(), powerVars.maxPushRate * dt)
		for _,p in ipairs(powerVars.priorityIndex) do
			local devices = consumers[p].devices
			local powerPerDevice = powerPacket / #devices
			for _,device in pairs(devices) do
				local leftovers = power.transferEnergy(powerPerDevice, device)
				if leftovers < powerPerDevice then sentPower = true end
				powerPacket = powerPacket + leftovers
				powerPerDevice = powerPacket / #devices
			end
			if powerPacket <= 0 then break end
		end
	end
	for _,node in pairs(powerVars.produces and powerVars.outputNodes or {}) do
		object.setOutputNodeLevel(node, sentPower)
	end
	
	power.setPowerMeter(power.getStoredEnergy() / power.getMaxEnergy())

	if power.consumes then
		power.setVar('relayRefreshTime', powerVars.relayRefreshTime - dt)
		if powerVars.relayRefreshTime <= 0 then
			power.setVar('relayRefreshTime', powerVars.relayRefreshTime + 1)
			power.setVar('relayRemaining', powerVars.relayDraw)
		end
	end
end

function power.hasConsumedEnergy()
	return powerVars.consumedPower
end

function power.hasNotConsumedEnergy()
	return not powerVars.consumedPower
end

function power.getGenRate()
	return powerVars.genRate
end

function power.setGenRate(rate)
	power.setVar('genRate', rate)
end

function power.getConsumeRate()
	return powerVars.consumeRate
end

function power.setConsumeRate(rate)
	power.setVar('consumeRate', rate)
end

function power.getStorageLeft()
	return power.getMaxEnergy() - power.getStoredEnergy()
end

function power.setMaxEnergy(energy)
	power.setVar('maxEnergy', energy)
	power.setStoredEnergy(math.min(power.getStoredEnergy(), energy))
end

function power.getMaxEnergy()
	return powerVars.maxEnergy
end

function power.setStoredEnergy(energy)
	power.setVar('storedEnergy', math.min(power.getMaxEnergy(), energy))
end

function power.getStoredEnergy()
	return powerVars.storedEnergy
end

function power.getPriority()
	return powerVars.priority
end

function power.setPriority(p)
	power.setVar('priority', p)
	-- Broadcast priority change to connected producers (mostly used by relays)
	for _, producer in pairs(powerVars.connected.producers) do
		util.callEntity(producer, 'power.updatePriority', entity.id(), p)
	end
end

-- Sets a connected device's priority. Used for propagation of priority, usually by relays
-- Relays actually override this function, to continue upwards if this causes a change in the relay's priority
function power.updatePriority(device, priority)
	powerVars.connected.all[device].priority = priority
end

function power.setVar(var, val)
	powerVars[var] = val
	storage.powerVars[var] = val
end

-- Subtracts power from the device's storage.
-- Returns the amount of energy that couldn't be removed.
function power.removeEnergy(energy)
	local newEnergy = power.getStoredEnergy() - energy
	power.setStoredEnergy(math.max(newEnergy, 0))
	--if storage.isFull and storage.storedEnergy < power.maxEnergy then
		-- We're full - broadcast to stop powering this device
	--end
	return power.getStoredEnergy() - newEnergy
end

-- Adds power to the device's storage.
-- Returns the excess energy, if any.
function power.receiveEnergy(energy)
	--sb.logInfo("Received "..energy.." energy")
	-- Account for relay energy per second rates
	local newEnergy = math.min(energy, powerVars.relayRemaining, (powerVars.relayDraw or 9999) * script.updateDt())
	power.setVar('relayRemaining', powerVars.relayRemaining - newEnergy)

	newEnergy = power.getStoredEnergy() + newEnergy
	power.setStoredEnergy(math.min(newEnergy, power.getMaxEnergy()))
	return newEnergy - power.getStoredEnergy()
end

-- Attempts to transfer energy from this device to the other device.
-- If energy couldn't be sent, it is returned to this device.
-- Returns the amount of leftover energy.
function power.transferEnergy(energy, device)
	local failed = power.removeEnergy(energy)
	local leftover = util.callEntity(device, 'power.receiveEnergy', energy - failed) or energy
	if leftover > 0 then power.receiveEnergy(leftover) end
	return leftover
end

function power.onInputNodeChange()
	power.logicIdle()
end

function power.onNodeConnectionChange()
	power.logicIdle()
	
	local inputWires = {}
	local outputWires = {}
	powerVars.connected = { all = {}, producers = {}, consumers = {} }
	powerVars.priorityIndex = {}
	for _,node in pairs(powerVars.produces and powerVars.outputNodes or {}) do
		if object.isOutputNodeConnected(node) then
			outputWires = util.mergeTable(outputWires, object.getOutputNodeIds(node))
		end
	end
	for _,node in pairs(powerVars.consumes and powerVars.inputNodes or {}) do
		if object.isInputNodeConnected(node) then
			inputWires = util.mergeTable(inputWires, object.getInputNodeIds(node))
		end
	end
	for e,node in pairs(outputWires) do
		local powerData = util.callEntity(e, 'power.getPowerData')
		if powerData and contains(powerData.inputNodes, node) then
			powerVars.connected.all[e] = powerData
			power.connectConsumer(e)
		end
	end
	for e,node in pairs(inputWires) do
		local powerData = util.callEntity(e, 'power.getPowerData')
		if powerData and contains(powerData.outputNodes, node) then
			powerVars.connected.all[e] = powerData
			power.connectProducer(e)
		end
	end

	-- If we have 2 or more priorities to handle after connecting, sort them
	if #powerVars.priorityIndex >= 2 then
		table.sort(powerVars.priorityIndex, function(a,b)
			local consumers = powerVars.connected.consumers
			if a>b then -- no change, no swapping
				return true
			else
				-- swap mapped indexes when performing a swap in the sort
				consumers[a].index,consumers[b].index = consumers[b].index,consumers[a].index
				return false
			end
		end)
	end
end

function power.getPowerData()
	return powerVars
end

function power.logicIdle()
	local hasLogic = false
	local becomeIdle = true
	local isEmpty = true
	for _,node in pairs(powerVars.logicNodes) do
		hasLogic = true
		if object.isInputNodeConnected(node) then
			if object.getInputNodeLevel(node) then
				becomeIdle = false
			end
			isEmpty = false
		end
	end
	if not powerVars.idle and hasLogic and becomeIdle and not isEmpty then
		power.becomeIdle()
	elseif powerVars.idle then
		power.wakeUp()
	end
end

function power.becomeIdle()
	power.setVar('idle', true)
	script.setUpdateDelta(0) -- We're idle now. Enter a deep sleep, never to return...?
	power.applyAnims(powerVars.animStates.idle)
	power.onBecomeIdle()
end

function power.wakeUp()
	power.setVar('idle', false)
	script.setUpdateDelta(config.getParameter('scriptDelta', 5))
	power.onWakeUp()
end

function power.connectProducer(device)
	local powerData = powerVars.connected.all[device]
	if powerData.produces then
		table.insert(powerVars.connected.producers, device)
	end
end

function power.connectConsumer(device)
	local powerData = powerVars.connected.all[device]
	if powerData.consumes then
		local consumers = powerVars.connected.consumers
		if consumers[powerData.priority] then
			table.insert(consumers[powerData.priority].devices, device)
		else
			consumers[powerData.priority] = { devices = {} }
			table.insert(consumers[powerData.priority].devices, device)
			table.insert(powerVars.priorityIndex, powerData.priority)
			consumers[powerData.priority].index = #powerVars.priorityIndex
		end
	end
end

function power.setPowerMeter(energyLevel)
	local meterStates = powerVars.animStates.powerMeter
	if meterStates then
		local meterPos = powerVars.meterPos or 1
		local nextMeter = meterStates[meterPos+1]
		local prevMeter = meterStates[meterPos-1]
		if nextMeter and energyLevel >= nextMeter.level then
			power.applyAnims(nextMeter.anims)
			power.setVar('meterPos', meterPos+1)
		elseif prevMeter and energyLevel <= prevMeter.level then
			power.applyAnims(prevMeter.anims)
			power.setVar('meterPos', meterPos-1)
		end
	end
end

function power.applyAnims(anims)
	for k,v in pairs(anims or {}) do
		if animator.animationState(k) ~= v then
			animator.setAnimationState(k, v)
		end
	end
end

function util.callEntity(id,...)
	if world.entityExists(id) then
		return world.callScriptedEntity(id,...)
	end
end