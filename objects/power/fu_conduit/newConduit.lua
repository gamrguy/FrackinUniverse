require '/scripts/newPower.lua'

function power.postInit()
	onInputNodeChange()
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

function onInputNodeChange(args)
	setObjectOn()
	--[[for i=0,object.inputNodeCount()-1 do
		for value in pairs(object.getInputNodeIds(i)) do
			if world.callScriptedEntity(value,'isPower') then
				world.callScriptedEntity(value,'power.onNodeConnectionChange')
			end
		end
	end
	for i=0,object.outputNodeCount()-1 do
		for value in pairs(object.getOutputNodeIds(i)) do
			if world.callScriptedEntity(value,'isPower') then
				world.callScriptedEntity(value,'power.onNodeConnectionChange')
			end
		end
	end]]
end