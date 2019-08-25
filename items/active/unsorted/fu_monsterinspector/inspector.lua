require "/scripts/vec2.lua"

function init()
	self=config.getParameter("scanSettings",{maxRange=15,cooldownTime=1.0})
	self.cooldownTimer = self.cooldownTime
	self.baseOffset=config.getParameter("baseOffset")
end

function update(dt, fireMode, shiftHeld)

	if mcontroller.crouching() then
		activeItem.setArmAngle(-0.15)
	else
		activeItem.setArmAngle(-0.5)
	end

	self.cooldownTimer = math.max(self.cooldownTimer - dt, 0.0)

	local position = activeItem.ownerAimPosition()
	local monsterList = world.monsterQuery(position,1) or {}
	
	local target = nil
	for _,v in pairs(monsterList) do
		target=v
		break
	end
	local rangecheck = world.magnitude(mcontroller.position(), position) <= self.maxRange and not world.lineTileCollision(vec2.add(mcontroller.position(), activeItem.handPosition(self.baseOffset)), position)
	local firing=fireMode=="primary" or fireMode=="alt"

	if rangecheck then
		if target then
			activeItem.setCursor("/cursors/chargeready.cursor")
		else
			activeItem.setCursor("/cursors/chargeidle.cursor")
		end
	else
		activeItem.setCursor("/cursors/reticle0.cursor")
	end
	
	if self.cooldownTimer == 0 then
		if rangecheck and target then
			if firing then
				playSound("fire")
				self.cooldownTimer = self.cooldownTime
				
				local monsterParams=root.monsterParameters(world.monsterType(target))
				local monsterName=world.entityName(target)
				local monsterDesc=world.entityDescription(target)
				local message="^yellow;"..(monsterName or "???") .."^reset;\n".. (monsterDesc or "")
				
				if monsterParams.capturable then
					if monsterParams.relocatable then
						message=message.."\n^green;Capturable^reset;, ^green;Relocatable^reset;."
					else
						message=message.."\n^green;Capturable^reset;."
					end
				else
					if monsterParams.relocatable then
						message=message.."\n^green;Relocatable^reset;."
					end
				end
				
				world.spawnStagehand(position, "fugenericmonstersaystagehand", {messageData={monsterId=target,message=message}})
			end
		else
			if firing then
				self.cooldownTimer = self.cooldownTime
				animator.playSound("error")
			end
		end
	end
end


function playSound(soundKey)
	if animator.hasSound(soundKey) then
		animator.playSound(soundKey)
	end
end