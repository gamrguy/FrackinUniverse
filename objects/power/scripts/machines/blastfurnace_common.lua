require '/scripts/fu_storageutils.lua'
require '/scripts/kheAA/transferUtil.lua'
require '/objects/power/scripts/power.lua'

function power.postInit()
	transferUtil.init()
	transferUtil.loadSelfContainer()
	object.setInteractive(true)

	self.blastRecipes = root.assetJson("/objects/power/recipes_blastfurnace.config")
end

function power.postUpdate(dt)
	if storage.smeltingOutputs and power.hasConsumedEnergy() then
		storage.smeltingTimer = storage.smeltingTimer - dt

		if storage.smeltingTimer <= 0 then
			for item,chance in pairs(storage.smeltingOutputs) do
				local base = chance.amount + (powerVars.isArc and chance.arcbonus or 0)
				local count = math.floor(base)
				if math.random() <= (base % 1) then
					count = count + 1
				end
				if count > 0 then
					local avoid = {}; avoid[0] = true
					fu_newStoreItems({name=item, count=count}, avoid, true)
				end
			end
			storage.smeltingOutputs = nil
			power.setConsumeRate(0)
		end
	end

	if not storage.smeltingOutputs and getRecipe() then
		if world.containerConsume(entity.id(), self.input) then
			power.setConsumeRate(powerVars.smeltingPower * (self.recipe.powerMult or 1))
			storage.smeltingTimer = powerVars.smeltingTime * (self.recipe.timeMult or 1)
			storage.smeltingOutputs = self.recipe.outputs
		end
	end
end

-- Grabs the input and output, saving them to variables.
-- Returns false if unsuccessful, or if the output won't fit into the container.
function getRecipe()
	local inputItem = world.containerItemAt(entity.id(),0)
	if inputItem and self.blastRecipes.recipes[inputItem.name] then
		self.recipe = self.blastRecipes.recipes[inputItem.name]
		if (self.recipe.arc_only and powerVars.isArc) or not self.recipe.arc_only then
			self.input = { name = inputItem.name, count = self.recipe.count or self.blastRecipes.defaultCount }
			if self.input.count > inputItem.count then
				return false
			end
			if not testOutputs(self.recipe.outputs) then
				return false
			end
		else
			return false
		end
	else
		return false
	end
	return true
end

-- Tests to see if the output can be placed in the container.
-- Returns false if any one of the given outputs can't fit at least one item.
function testOutputs(outputs)
	for item,info in pairs(outputs) do
		local chance = info.amount + ((powerVars.isArc and info.arcbonus) or 0)
		if chance > 0 then
			local itemobj = {
				name = item,
				count = math.max(1, math.floor(chance))
			}
			if world.containerItemsCanFit(entity.id(), itemobj) <= 0 then
				return false
			end
		end
	end
	return true
end
