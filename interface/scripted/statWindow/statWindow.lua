function init()
	self.data = root.assetJson("/interface/scripted/statWindow/statWindow.config")
	self.elements = self.data.elements
	self.statuses = self.data.statuses

	widget.setText("characterName", "^blue;"..world.entityName(player.id()))

	local playerRace = player.species()
	local recognized = false
	for _,race in ipairs(self.data.races) do
		if race == playerRace then
			recognized = true
			break
		end
	end
	
	if recognized then
		widget.setImage("characterSuit", "/interface/scripted/techupgrade/suits/"..playerRace.."-"..player.gender()..".png")
	else
		widget.setImage("characterSuit", "/interface/scripted/techupgrade/suits/novakid-"..player.gender()..".png") -- Novakid because it has the least amount features
	end
end

function update()
	for _, element in pairs(self.elements) do
		widget.setText(element.."Resist", math.floor(status.stat(element.."Resistance")*100+0.5).."%")
	end

	widget.clearListItems("immunitiesList.textList")
	for thing,stuff in pairs(self.statuses) do
		local skipping = false

		if stuff.skip then
			for _,skipped in pairs(stuff.skip) do
				if status.stat(skipped) >= 1 then
					skipping = true
					break
				end
			end
		end

		if not skipping then
			if status.stat(thing) >= 1 then
				local listItem = "immunitiesList.textList."..widget.addListItem("immunitiesList.textList")
				widget.setText(listItem..".immunity", stuff.name)
			end
		end
	end
end

function expand()
	player.interact("ScriptPane", "/interface/scripted/statWindow/extraStatsWindow.config", player.id())
end

function loreBook()
	player.interact("ScriptPane", "/interface/scripted/xcustomcodex/xcodexui.config", player.id())
end
function research()
	player.interact("ScriptPane", "/zb/researchTree/researchTree.config", player.id())
end

function mechEquip()
	player.interact("ScriptPane", "/interface/scripted/mechassembly/mechassemblygui.config", player.id())
end
function mechFuel()
	player.interact("ScriptPane", "/interface/mechfuel/mechfuel.config", player.id())
end

function techBuild()
	player.interact("ScriptPane", "/interface/scripted/techshop/techshop.config", player.id())
end
function techEquip()
	player.interact("ScriptPane", "/interface/scripted/techupgrade/techupgradegui.config", player.id())
end
function upgradeEquipmentMenu()
	player.interact("ScriptPane", "/interface/scripted/fu_multiupgrade/fu_multiupgrade.config", player.id())
end