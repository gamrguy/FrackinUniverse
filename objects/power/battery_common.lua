require '/objects/power/power.lua'

function power.postInit()
	object.setInteractive(true)
end

function onInteraction()
	print(math.floor(storage.storedEnergy+0.5))
end

function power.preUpdate(dt)
	object.setConfigParameter('description', isn_makeBatteryDescription())
end

function power.postUpdate(dt)
	local powerlevel = math.floor(storage.storedEnergy / power.maxEnergy * 10)
	animator.setAnimationState("meter", power.getStoredEnergy() == 0 and 'd' or tostring(math.floor(powerlevel)))
end

function die()
	if storage.storedEnergy > 0 then
		local charge = storage.storedEnergy / power.maxEnergy * 100
		local iConf = root.itemConfig(object.name())
		local newObject = { storedEnergy = storage.storedEnergy }

		if iConf and iConf.config then
			-- set the border colour according to the charge level (red → yellow → green)
			if iConf.config.inventoryIcon then
				local colour

				if     charge <  25 then colour = 'FF0000'
				elseif charge <  50 then colour = 'FF8000'
				elseif charge <  75 then colour = 'FFFF00'
				elseif charge < 100 then colour = '80FF00'
				else                     colour = '00FF00'
				end
				newObject.inventoryIcon = iConf.config.inventoryIcon .. '?border=1;' .. colour .. '?fade=' .. colour .. 'FF;0.1'
			end

			-- append the stored charge %age (rounded to 0.5) to the description
			newObject.description = isn_makeBatteryDescription(iConf.config.description or '', charge)
		end

		world.spawnItem(object.name(), entity.position(), 1, newObject)
		-- object.smash(true)
	else
		world.spawnItem(object.name(), entity.position())
	end
end

function isn_makeBatteryDescription(desc, charge)
	if desc == nil then
		desc = root.itemConfig(object.name())
		desc = desc and desc.config and desc.config.description or ''
	end
	charge = charge or storage.storedEnergy / power.maxEnergy * 100

	-- bat flattery
	if charge == 0 then return desc end

	-- round down to multiple of 0.5 (special case if < 0.5)
	if charge < 0.5 then
		charge = '< 0.5'
	else
		charge = math.floor (charge * 2) / 2
	end

	-- append charge state to default description; ensure that it's on a line of its own
	return desc .. (desc ~= '' and "\n" or '') .. "^yellow;Stored charge: " .. charge .. '%'
end
