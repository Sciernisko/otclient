local preyWindow, preyWidget, preyButton, preyWidgetButton, msgWindow = nil
local bankGold = 0
local inventoryGold = 0
local rerollPrice = 0
local bonusRerolls = 0
local PREY_BONUS_DAMAGE_BOOST = 0
local PREY_BONUS_DAMAGE_REDUCTION = 1
local PREY_BONUS_XP_BONUS = 2
local PREY_BONUS_IMPROVED_LOOT = 3
local PREY_BONUS_NONE = 4
local PREY_ACTION_LISTREROLL = 0
local PREY_ACTION_BONUSREROLL = 1
local PREY_ACTION_MONSTERSELECTION = 2
local PREY_ACTION_REQUEST_ALL_MONSTERS = 3
local PREY_ACTION_CHANGE_FROM_ALL = 4
local PREY_ACTION_LOCK_PREY = 5

function updatePlayerBalance()
	local msg = OutputMessage.create()

	msg.addU8(msg, 237)
	msg.addU8(msg, 255)
	g_game.getProtocolGame():send(msg)

	return 
end

function bonusDescription(bonusType, bonusValue, bonusGrade)
	if bonusType == PREY_BONUS_DAMAGE_BOOST then
		return "Damage bonus (" .. bonusGrade .. "/10)"
	elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
		return "Damage reduction bonus (" .. bonusGrade .. "/10)"
	elseif bonusType == PREY_BONUS_XP_BONUS then
		return "XP bonus (" .. bonusGrade .. "/10)"
	elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
		return "Loot bonus (" .. bonusGrade .. "/10)"
	elseif bonusType == PREY_BONUS_DAMAGE_BOOST then
		return "-"
	end

	return "Uknown bonus"
end

function timeleftTranslation(timeleft, forPreyTimeleft)
	if timeleft == 0 then
		if forPreyTimeleft then
			return tr("infinite bonus")
		end

		return tr("Available now")
	end

	local minutes = math.ceil(timeleft/60)
	local hours = math.floor(minutes/60)
	minutes = minutes - hours*60

	if 0 < hours then
		if forPreyTimeleft then
			return "" .. hours .. "h " .. minutes .. "m"
		end

		return tr("Available in") .. " " .. hours .. "h " .. minutes .. "m"
	end

	if forPreyTimeleft then
		return "" .. minutes .. "m"
	end

	return tr("Available in") .. " " .. minutes .. "m"
end

function init()
	connect(g_game, {
		onGameStart = check,
		onGameEnd = hide,
		onResourceBalance = onResourceBalance,
		onPreyFreeRolls = onPreyFreeRolls,
		onPreyTimeLeft = onPreyTimeLeft,
		onPreyPrice = onPreyPrice,
		onPreyLocked = onPreyLocked,
		onPreyInactive = onPreyInactive,
		onPreyActive = onPreyActive,
		onPreySelection = onPreySelection
	})

	preyWindow = g_ui.displayUI("prey")

	preyWindow:hide()

	preyWidget = g_ui.loadUI("widget", modules.game_interface.getRightPanel())

	preyWidget:setup()
	preyWidget:setContentMaximumHeight(67)

	if g_game.isOnline() then
		check()
	end

	return 
end

function terminate()
	disconnect(g_game, {
		onGameStart = check,
		onGameEnd = hide,
		onResourceBalance = onResourceBalance,
		onPreyFreeRolls = onPreyFreeRolls,
		onPreyTimeLeft = onPreyTimeLeft,
		onPreyPrice = onPreyPrice,
		onPreyLocked = onPreyLocked,
		onPreyInactive = onPreyInactive,
		onPreyActive = onPreyActive,
		onPreySelection = onPreySelection
	})

	if preyButton then
		preyButton:destroy()
	end

	if preyWidgetButton then
		preyWidgetButton:destroy()
	end

	preyWindow:destroy()

	if msgWindow then
		msgWindow:destroy()

		msgWindow = nil
	end

	return 
end

function check()
	if g_game.getFeature(GamePrey) then
		if not preyButton then
			preyButton = modules.client_topmenu.addRightGameToggleButton("preyButton", tr("Open prey dialog"), "/images/topbuttons/preywindow", toggle, false, 5)
		end

		if not preyWidgetButton then
			preyWidgetButton = modules.client_topmenu.addRightGameToggleButton("preyWidgetButton", tr("Open prey window"), "/images/topbuttons/prey", toggleWidget, false, 6)

			preyWidgetButton:setOn(false)
		end

		if g_game.getWorldName() == "Fidelity" then
			if preyButton then
				preyButton:destroy()

				preyButton = nil
			end

			if preyWidgetButton then
				preyWidgetButton:destroy()

				preyWidgetButton = nil
			end
		end
	elseif preyButton then
		preyButton:destroy()

		preyButton = nil

		preyWidgetButton:destroy()

		preyWidgetButton = nil
	end

	return 
end

function hide()
	preyWindow:hide()

	if msgWindow then
		msgWindow:destroy()

		msgWindow = nil
	end

	return 
end

function show()
	if not g_game.getFeature(GamePrey) then
		return hide()
	end

	preyWindow:show()
	preyWindow:raise()
	preyWindow:focus()
	updatePlayerBalance()

	return 
end

function toggle()
	if preyWindow:isVisible() then
		return hide()
	end

	show()

	return 
end

function toggleWidget()
	if preyWidgetButton:isOn() then
		preyWidget:close()
		preyWidgetButton:setOn(false)
	else
		preyWidget:open()
		preyWidgetButton:setOn(true)
	end

	return 
end

function displayPreyList(slot, bonusType, bonusGrade, currentHolderName, currentHolderOutfit, timeLeft)
	local preyOutfit = preyWidget:recursiveGetChildById("preyCreatureOutfit" .. slot + 1)
	local preyBonus = preyWidget:recursiveGetChildById("preyBonus" .. slot + 1)
	local preyName = preyWidget:recursiveGetChildById("preyMonsterName" .. slot + 1)
	local timeLeftBar = preyWidget:recursiveGetChildById("preyProgressBar" .. slot + 1)
	local bonuses = {
		[0] = "dmg",
		"reduction",
		"xp",
		"loot"
	}
	local bonusTypes = {
		[0] = {
			text = "You deal %s extra damage against your prey creature.",
			name = "Damage Boost",
			start = 6,
			step = 1
		},
		{
			text = "You take %s less damage from your prey creature.",
			name = "Damage Reduction",
			start = 6,
			step = 1
		},
		{
			text = "Killing your prey monster rewards %s extra XP.",
			name = "Bonus XP",
			start = 7,
			step = 2
		},
		{
			text = "Your prey monster has a %s chance to drop additional loot.",
			name = "Improved Loot",
			start = 13,
			step = 3
		}
	}
	local nullOutfit = {
		head = 0,
		legs = 0,
		body = 0,
		type = 0,
		addons = 0,
		feet = 0
	}

	if currentHolderName then
		preyOutfit.setOutfit(preyOutfit, currentHolderOutfit)
		preyOutfit.setImageSource(preyOutfit, 0)
		preyBonus.setImageSource(preyBonus, "/images/prey/" .. bonuses[bonusType] .. "")
		preyName.setText(preyName, currentHolderName)
		timeLeftBar.setPercent(timeLeftBar, (math.ceil(timeLeft/60)*100)/120)
		timeLeftBar.setBackgroundColor(timeLeftBar, "orange")
		timeLeftBar.setTooltip(timeLeftBar, "Creature: " .. currentHolderName .. "\nDuration: " .. timeleftTranslation(timeLeft, true) .. "\nValue: " .. bonusGrade .. "/10\nType: " .. bonusTypes[bonusType].name .. "\n" .. string.format(bonusTypes[bonusType].text, "+" .. math.floor((bonusTypes[bonusType].start + bonusGrade*bonusTypes[bonusType].step) - bonusTypes[bonusType].step) .. "%"))
	else
		preyOutfit.setOutfit(preyOutfit, nullOutfit)
		preyOutfit.setImageSource(preyOutfit, "/images/prey/prey")
		preyBonus.setImageSource(preyBonus, "/images/prey/inactive")
		preyName.setText(preyName, "Inactive")
		timeLeftBar.setPercent(timeLeftBar, 0)
		timeLeftBar.setTooltip(timeLeftBar, "")
	end

	return 
end

function onMiniWindowClose()
	preyWidgetButton:setOn(false)

	return 
end

function onPreyFreeRolls(slot, timeleft)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	if prey.state ~= "active" and prey.state ~= "selection" then
		return 
	end

	prey.bottomLabel:setText(tr("Free list reroll") .. ": \n" .. timeleftTranslation(timeleft*60))

	return 
end

function onPreyTimeLeft(slot, timeleft)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	if prey.state ~= "active" then
		return 
	end

	local bonusTypes = {
		[0] = {
			text = "You deal %s extra damage against your prey creature.",
			name = "Damage Boost",
			start = 6,
			step = 1
		},
		{
			text = "You take %s less damage from your prey creature.",
			name = "Damage Reduction",
			start = 6,
			step = 1
		},
		{
			text = "Killing your prey monster rewards %s extra XP.",
			name = "Bonus XP",
			start = 7,
			step = 2
		},
		{
			text = "Your prey monster has a %s chance to drop additional loot.",
			name = "Improved Loot",
			start = 13,
			step = 3
		}
	}
	local timeLeftBar = preyWidget:recursiveGetChildById("preyProgressBar" .. slot + 1)

	timeLeftBar.setPercent(timeLeftBar, (math.ceil(timeleft/60)*100)/120)
	timeLeftBar.setTooltip(timeLeftBar, "Creature: " .. prey.title:getText() .. "\nDuration: " .. timeleftTranslation(timeleft, true) .. "\nValue: " .. prey.bonusgrade:getText() .. "/10\nType: " .. bonusTypes[tonumber(prey.bonustype:getText())].name .. "\n" .. string.format(bonusTypes[tonumber(prey.bonustype:getText())].text, "+" .. math.floor((bonusTypes[tonumber(prey.bonustype:getText())].start + tonumber(prey.bonusgrade:getText())*bonusTypes[tonumber(prey.bonustype:getText())].step) - bonusTypes[tonumber(prey.bonustype:getText())].step) .. "%"))
	prey.description:setText(tr("Time left") .. ": " .. timeleftTranslation(timeleft, true))

	return 
end

function onPreyPrice(price)
	rerollPrice = price

	preyWindow.rerollPriceLabel:setText(comma_value(price))
	preyWindow.rerollPriceLabel.listPriceReroll:setItemId(3031)

	return 
end

function onPreyLocked(slot, unlockState, timeUntilFreeReroll)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	prey.state = "locked"

	prey.title:setText(tr("Prey Locked"))
	prey.list:hide()
	prey.creature:hide()
	prey.description:hide()
	prey.bonuses:hide()
	prey.button:hide()
	prey.bottomLabel:show()
	displayPreyList(slot)

	if unlockState == 0 then
		prey.bottomLabel:setText(tr("You need to have premium account and buy this prey slot in the game store."))
	elseif unlockState == 1 then
		prey.bottomLabel:setText(tr("You need to buy this prey slot in the game store."))
	else
		prey.bottomLabel:setText(tr("You can't unlock it."))
		prey.bottomButton:hide()
	end

	if (unlockState == 0 or unlockState == 1) and modules.game_shop then
		prey.bottomButton:setText("Open game store")

		prey.bottomButton.onClick = function ()
			hide()
			modules.game_shop.show()

			return 
		end

		prey.bottomButton:show()
	end

	return 
end

function onPreyInactive(slot, timeUntilFreeReroll)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	prey.state = "inactive"

	prey.title:setText(tr("Prey Inactive"))
	prey.list:hide()
	prey.creature:hide()
	prey.description:hide()
	prey.bonuses:hide()
	prey.button:hide()
	prey.bottomLabel:hide()
	prey.bottomLabel:setText(tr("Free list reroll") .. ": \n" .. timeleftTranslation(timeUntilFreeReroll*60))
	prey.bottomLabel:show()

	if 0 < timeUntilFreeReroll then
		prey.bottomButton:setText(tr("Buy list reroll"))
	else
		prey.bottomButton:setText(tr("Free list reroll"))
	end

	prey.bottomButton:show()
	displayPreyList(slot)

	prey.bottomButton.onClick = function ()
		g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)

		return 
	end

	return 
end

function onPreyActive(slot, currentHolderName, currentHolderOutfit, bonusType, bonusValue, bonusGrade, timeLeft, timeUntilFreeReroll)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	prey.state = "active"

	prey.title:setText(currentHolderName)
	prey.list:hide()
	prey.creature:show()
	prey.creature:setOutfit(currentHolderOutfit)
	prey.description:setText(tr("Time left") .. ": " .. timeleftTranslation(timeLeft, true))
	prey.description:show()
	prey.bonuses:setText(bonusDescription(bonusType, bonusValue, bonusGrade))
	prey.bonuses:show()
	prey.bonusgrade:setText(bonusGrade)
	prey.bonustype:setText(bonusType)
	prey.button:setText(tr("Bonus reroll"))
	prey.button:show()
	prey.bottomLabel:setText(tr("Free list reroll") .. ": \n" .. timeleftTranslation(timeUntilFreeReroll*60))
	prey.bottomLabel:show()

	if 0 < timeUntilFreeReroll then
		prey.bottomButton:setText(tr("Buy list reroll"))
	else
		prey.bottomButton:setText(tr("Free list reroll"))
	end

	prey.bottomButton:show()
	displayPreyList(slot, bonusType, bonusGrade, currentHolderName, currentHolderOutfit, timeLeft)

	prey.button.onClick = function ()
		if bonusRerolls == 0 then
			return showMessage(tr("Error"), tr("You don't have any bonus rerolls.\nYou can buy them in ingame store."))
		end

		g_game.preyAction(slot, PREY_ACTION_BONUSREROLL, 0)

		return 
	end
	prey.bottomButton.onClick = function ()
		g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)

		return 
	end

	return 
end

function onPreySelection(slot, bonusType, bonusValue, bonusGrade, names, outfits, timeUntilFreeReroll)
	local prey = preyWindow["slot" .. slot + 1]

	if not prey then
		return 
	end

	prey.state = "selection"

	prey.title:setText(tr("Select monster"))
	prey.list:show()
	prey.creature:hide()
	prey.description:hide()
	prey.bonuses:hide()
	prey.button:setText(tr("Select"))
	prey.button:show()
	prey.bottomLabel:setText("Free list reroll: \n" .. timeleftTranslation(timeUntilFreeReroll*60))
	prey.bottomLabel:show()

	if 0 < timeUntilFreeReroll then
		prey.bottomButton:setText(tr("Buy list reroll"))
	else
		prey.bottomButton:setText(tr("Free list reroll"))
	end

	prey.bottomButton:show()
	displayPreyList(slot)

	prey.bottomButton.onClick = function ()
		g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)

		return 
	end

	prey.list:destroyChildren()

	for i, name in ipairs(names) do
		local label = g_ui.createWidget("PreySelectionLabel", prey.list)
		local thingType = g_things.getThingType(outfits[i].type, 1)

		label.creature:setWidth(thingType.getExactSize(thingType)/g_sprites.getOffsetFactor())
		label.creature:setHeight(thingType.getExactSize(thingType)/g_sprites.getOffsetFactor())
		label.creature:setOutfit(outfits[i])
		label.creature:setTooltip(name)
	end

	prey.button.onClick = function ()
		local child = prey.list:getFocusedChild()

		if not child then
			return showMessage(tr("Error"), tr("Select monster to proceed."))
		end

		local index = prey.list:getChildIndex(child)

		g_game.preyAction(slot, PREY_ACTION_MONSTERSELECTION, index - 1)

		return 
	end

	return 
end

function onResourceBalance(type, balance)
	if type == 0 then
		bankGold = balance
	elseif type == 1 then
		inventoryGold = balance
	elseif type == 10 then
		bonusRerolls = balance

		preyWindow.bonusRerollLabel:setText(balance)
		preyWindow.bonusRerollLabel.rerollIcon:setItemId(7641)
	end

	if type == 0 or type == 1 then
		preyWindow.balanceLabel:setText(comma_value(bankGold + inventoryGold))
		preyWindow.balanceLabel.balanceIcon:setItemId(3031)
	end

	return 
end

function showMessage(title, message)
	if msgWindow then
		msgWindow:destroy()
	end

	msgWindow = displayInfoBox(title, message)

	msgWindow:show()
	msgWindow:raise()
	msgWindow:focus()

	return 
end

return 