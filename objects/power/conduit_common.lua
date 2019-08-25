require '/objects/power/power.lua'

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

function power.preNodeConnectionChange()
	setObjectOn()
end

function power.postNodeConnectionChange()
	-- Automatically set priority to the highest connected.
	-- If no consumers connected, and therefore no prioritized machines, don't bother sending power to here (unless it's the only thing left)
	power.setPriority(power.priorityIndex[1] or -999)
end

function onInputNodeChange(args)
	setObjectOn()
end