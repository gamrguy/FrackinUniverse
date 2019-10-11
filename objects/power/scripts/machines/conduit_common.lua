require '/objects/power/scripts/power.lua'

function power.postInit()
	onInputNodeChange()
end

function power.preUpdate()
	
end

function power.postUpdate()

end

function setObjectOn()
	storage.on=not object.isInputNodeConnected(1) or object.getInputNodeLevel(1)
	animator.setAnimationState("switchState", storage.on and storage.storedEnergy > 0 and "on" or "off")
	power.produces = storage.on
	power.consumes = storage.on
	return storage.on
end

function isPower()
	return setObjectOn()
end

-- Relays take the highest priority of their connected consumers!
-- If a relay receives a priority change, usually from another relay, then this one needs to check that!
local p_update_orig = power.updatePriority
function power.updatePriority(device, priority)
	p_update_orig(device, priority)

	if priority > powerVars.priority then
		power.setPriority(priority)
	end
end

function power.preNodeConnectionChange()
	setObjectOn()
end

function power.postNodeConnectionChange()
	-- Automatically set priority to the highest connected.
	-- If no consumers connected, and therefore no prioritized machines, don't bother sending power to here. You won't be able to, anyway.
	power.setPriority(power.priorityIndex[1] or -999)

	if #powerVars.connected.consumers == 0 then
		-- If nothing's connected, do nothing
		power.setMaxEnergy(0)
		power.becomeIdle()
	else
		-- Set max energy to the total relay draw of connected consumers, accounting for tick rate
		local totalDraw = 0
		for _, consumer in pairs(powerVars.connected.consumers) do
			totalDraw = totalDraw + powerVars.connected.all[consumer].relayDraw or 0
		end
		power.setMaxEnergy(totalDraw * script.updateDt())
		-- Something's connected, wake the hell up!
		power.wakeUp()
	end
end

function onInputNodeChange(args)
	--setObjectOn()
end