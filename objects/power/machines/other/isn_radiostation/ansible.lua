require '/objects/power/scripts/power.lua'

function power.postInit()
	object.setInteractive(true)
	storage.frequencies = storage.frequencies or config.getParameter("isn_baseFrequencies")
	storage.currentconfig = storage.currentconfig or storage.frequencies["isn_miningVendor"]
	storage.currentkey = storage.currentkey or "isn_miningVendor"
end

function onInteraction(args)
	if power.hasNotConsumedEnergy() then
		animator.burstParticleEmitter("noPower")
		animator.playSound("error")
	else
		local itemName = world.entityHandItem(args.sourceId, "primary")
		local tradingConfig = { config = storage.currentconfig, recipes = { } }
		for key, value in pairs(config.getParameter(storage.currentkey)) do
			local recipe = { input = { { name = "money", count = value } }, output = { name = key } }
			table.insert(tradingConfig.recipes, recipe)
		end
		return {"OpenCraftingInterface", tradingConfig}
	end
end

function power.postUpdate(dt)
	if power.hasConsumedEnergy() then
		object.setLightColor({30, 50, 90})
	else
		object.setLightColor({0, 0, 0})
	end
end