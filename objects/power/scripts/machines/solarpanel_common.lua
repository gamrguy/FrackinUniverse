require '/objects/power/scripts/power.lua'
require '/scripts/util.lua'
--[[
	Extra Parameters:
	solarPower - Maximum amount of u/s this solar panel can generate.
	invertLight - Whether to instead check for darkness (nocturn panels)
	efficiency - Efficiency of solar panel. Degrades over time (slowly).
	effTimescale - Multiplier on the speed at which efficiency degrades.
	minEfficiency - Minimum efficiency rating that this solar panel can fall to.
	freeTime - Amount of time during which efficiency doesn't fall. Affected by effTimescale.
	degradeTime - Amount of time over which efficiency falls to the minimum. Affected by effTimescale.

	Note: Generation efficiency is now a function of both light and a solar panel's inherent efficiency rating.
	This means that old solar panels will be unable to generate at maximum capacity, and also won't animate as such.
]]

function power.postInit()
	-- Just don't do anything at all if placed invalidly (on a ship or underground)
	if invalidLocation() then
		animator.setAnimationState("meter", "1")
		script.setUpdateDelta(0)
	end

	powerVars.solarPower = powerVars.solarPower or 0
	powerVars.lifeTime = powerVars.lifeTime or 0
	powerVars.efficiency = powerVars.efficiency or 1
	powerVars.minEfficiency = powerVars.minEfficiency or 0.3
	powerVars.freeTime = powerVars.freeTime or 600
	powerVars.degradeTime = powerVars.degradeTime or 3000
	powerVars.effTimescale = powerVars.effTimescale or 1

	storage.checkticks = 0
end

function power.preUpdate(dt)
	-- Don't perform functions when not generating power.
	-- Also doesn't degrade efficiency either, for fairness.
	if not powerGenerationBlocked() then
		-- If check is successful, update the true position to allow for a new location check
		getTruePosition()

		storage.checkticks = (storage.checkticks or 0) + dt
		power.setVar('lifeTime', (powerVars.lifeTime + dt) * powerVars.effTimescale)

		-- First 10 minutes of use are free
		-- After that, slowly drops to 30% over 50 minutes
		if powerVars.lifeTime < powerVars.freeTime then
			power.setVar('efficiency', 1)
		elseif powerVars.lifeTime > powerVars.degradeTime then
			power.setVar('efficiency', powerVars.minEfficiency)
		else
			local effFactor = (powerVars.lifeTime - powerVars.freeTime) / (powerVars.degradeTime - powerVars.freeTime)
			power.setVar('efficiency', util.lerp(effFactor, 1, powerVars.minEfficiency))
		end
	else
		animator.setAnimationState("meter", "1")
		power.setGenRate(0)
	end

	-- Perform power output check every 10 seconds (if active)
	if storage.checkticks >= 10 then
		storage.checkticks = storage.checkticks - 10
		local location = getTruePosition()
		local genmult = 1
		if world.type() ~= 'playerstation' then
			local highNoonness = percentOfHighNoon()
			if highNoonness >= 0.75 then
				genmult = 1
			else
				genmult = util.lerp(highNoonness, 0, 1)
			end
			--genmult = getLight(location)
		end
		genmult = genmult * powerVars.efficiency

		if world.liquidAt(location) then genmult = genmult * 0.5 end -- water significantly reduces the output

		if genmult >= 0.9 then
			animator.setAnimationState("meter", "4")
		elseif genmult >= 0.7 then
			animator.setAnimationState("meter", "3")
		elseif genmult >= 0.5 then
			animator.setAnimationState("meter", "2")
		elseif genmult > 0 then
			animator.setAnimationState("meter", "1")
		else
			animator.setAnimationState("meter", "0")
		end

		power.setGenRate(powerVars.solarPower * genmult)
	end
end

-- Gets the ambient light of the given location.
-- Works by reducing the effect of artificial lighting, then restoring the values to normal
function getLight(location)
	local objects = world.objectQuery(entity.position(), 20)
	local lights = {}
	for i=1,#objects do
		local light = world.callScriptedEntity(objects[i],'object.getLightColor')
		if light and (light[1] > 0 or light[2] > 0 or light[3] > 0) then
			lights[objects[i]] = light
			world.callScriptedEntity(objects[i],'object.setLightColor',{light[1]/3,light[2]/3,light[3]/3})
		end
	end
	local light = world.lightLevel(location)
	for key,value in pairs(lights) do
		world.callScriptedEntity(key,'object.setLightColor',value)
	end
	return light
end

-- Returns how close you are (during the day) to High Noon, Novakid approved!
function percentOfHighNoon()
	local dayTime = world.timeOfDay()

	-- If it isn't day we're 0% towards High Noon
	if dayTime > 0.55 then return 0 end

	-- If we're 50% through the day then it's 100% High Noon
	return -math.abs(dayTime / 0.275 - 1) + 1
end

-- Returns true if the solar panel can't generate power under certain conditions.
-- These include light being too low or the time being night.
-- Uses the stored true position; update with getTruePosition
function powerGenerationBlocked()
	-- Power generation does not occur if...
	local location = storage.truepos or getTruePosition()
	local material = world.material(location, 'background')
	local matcheck = material and not root.materialConfig(material).config.renderParameters.lightTransparent
	return (world.timeOfDay() > 0.55 and world.type() ~= 'playerstation') or matcheck
end

-- Returns a random location within the bounds of this solar panel.
-- Updates the stored "true" position of this object.
function getTruePosition()
	local corner1 = powerVars.boundingBox[1]
	local corner2 = powerVars.boundingBox[2]
	storage.truepos = {
		entity.position()[1] + math.random(corner1[1], corner2[1]),
		entity.position()[2] + math.random(corner1[2], corner2[2])
	}
	return storage.truepos
end

-- Returns true if solar panel has been placed in an invalid location, where it will never function.
-- Current criteria include being underground and being on a ship.
function invalidLocation()
	return world.type == 'unknown' or world.underground(entity.position())
end