--#region Required processes for bankApp
local bankChest
local interface = {}
local content = {} -- { ["coin_copper"] = { count = 64, slot = 1 }, ["coin_diamond"] = {count = 3, slot = 2 } }
local values = { -- [[ replace this table with your own currency system (this is the lightman's currency system, link to mod in Readme)
    		["coin_copper"] = 0.01,
    		["coinpile_copper"] = 0.09,
    		["coinblock_copper"] = 0.36,
    		["coin_iron"] = 0.10,
    		["coinpile_iron"] = 0.90,
			["coinblock_iron"] = 3.60,
			["coin_gold"] = 1.00,
    		["coinpile_gold"] = 9.00,
    		["coinblock_gold"] = 36.00,
    		["coin_emerald"] = 10.00,
    		["coinpile_emerald"] = 90.00,
    		["coinblock_emerald"] = 360.00,
    		["coin_diamond"] = 100.00,
    		["coinpile_diamond"] = 900.00,
    		["coinblock_diamond"] = 3600.00,
    		["coin_netherite"] = 1000.00,
    		["coinpile_netherite"] = 9000.00,
    		["coinblock_netherite"] = 36000.00
		}
local valuesNameOnly = { -- Sorted High to low and can be looped with ipairs instead of pairs
	"coinblock_netherite",
	"coinpile_netherite",
	"coin_netherite",
	"coinblock_diamond",
	"coinpile_diamond",
	"coin_diamond",
	"coinblock_emerald",
	"coinpile_emerald",
	"coin_emerald",
	"coinblock_gold",
	"coinpile_gold",
	"coin_gold",
	"coinblock_iron",
	"coinpile_iron",
	"coin_iron",
	"coinblock_copper",
	"coinpile_copper",
	"coin_copper"
}
local bankBNP = nil
local setupNeeded = true
local myBNP
local BNP_FILE = "BNP.txt"
local PRIVATE_CHANNEL = os.getComputerID()
local directConnetionChannel = 1

-- Try to automatically find a connected modem
local modem, modemSide
for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
    local p = peripheral.wrap(side)
    if p and peripheral.getType(side) == "modem" then
        modem = p
        modemSide = side
        break
    end
end

local debugFile = "bankApp.log"
if not fs.exists(debugFile) then
    local f = fs.open(debugFile,"w")
    f.write("")
    f.close()
else
    fs.delete(debugFile)
    local f = fs.open(debugFile,"w")
    f.write("")
    f.close()
end

local function debugPrint(msg)
    local time = os.date("%H:%M:%S")
	local f = fs.open(debugFile,"a")
	f.writeLine("[DEBUG "..time.."] " .. msg)
	f.close()
end
debugPrint("[BOOT] Started logging")

if not modem then
    term.setTextColor(colors.red)
    error("No modem detected on any side. Please attach a modem and restart.")
    term.setTextColor(colors.white)
    return
else
    term.setTextColor(colors.green)
    debugPrint("Modem found on side: "..modemSide)
    term.setTextColor(colors.white)
end

modem.open(PRIVATE_CHANNEL)
modem.open(1)

-- Wait for peripheral to be present
local function waitForPeripheral(side, time)
    local t0 = os.time()
    while not peripheral.isPresent(side) and (os.time() - t0) < time do
        os.sleep(0.5)
    end
    return peripheral.isPresent(side) and peripheral.wrap(side) or nil
end
-- Wait for chest to load its contents
local function waitForList(chest, side)
    local list
    repeat
        list = chest.list()
        if not list then
            print("Waiting for " .. side .. " to finish loading..")
            os.sleep(0.5)
        end
    until list
    return list
end

local function chestFind()
    -- Find connected chests/barrels and modem
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "minecraft:chest") or peripheral.hasType(side, "minecraft:barrel") then
            bankChest = side
        end
    end
end

local function lookIn(ch)
    -- Wrap and load contents of bank chest
    content = {}
    local chst = waitForPeripheral(ch, 5) -- Makes sure that the chests are still there
    local banklist = waitForList(chst, ch) -- Makes sure that the contents have loaded still
    for slot, item in pairs(banklist) do
        local iname = item.name:match(":(.+)")
        if content[iname] then
            content[iname].count = content[iname].count+item.count
        else
            content[iname] = {count = item.count, slot = slot } -- { ["coin_copper"] = { count = 64, slot = 1 }, ["coin_diamond"] = {count = 3, slot = 2 } }
        end
    end
	print(textutils.serialize(content))
end

chestFind()
lookIn(bankChest)

local configFile = "bankApp.conf"

local function loadConfigs()
	local f = fs.open(configFile,"r")
    local configs = textutils.unserialise(f.readAll())
    f.close()
	if configs == "" or configs == nil then
		print("Failed to load, using default variables")
		bankBNP = nil
		setupNeeded = true
	else
		print("Loaded correctly")
		bankBNP = configs.bankBNP
		setupNeeded = configs.setupNeeded
	end
end

if not fs.exists(configFile) then
	local f = fs.open(configFile,"w") f.writeLine("") f.close()
else
	loadConfigs()
end

local function saveConfigs()
	local f = fs.open(configFile,"w")
    local configs = textutils.serialize({ bankBNP = bankBNP, setupNeeded = setupNeeded --[[ Values should be hardcoded ]]})
	f.writeLine(configs)
    f.close()
end

-- Calculate total value of chest contents
local function addUp(chest)
    lookIn(chest)
	debugPrint("After LookIn")
    local total = 0
    for iname, itemData in pairs(content) do
		local amount = itemData.count
        local itemValue = values[iname] or 0
        total = total + (amount * itemValue)
    end
    return total
end

local function lookForCard(ch) -- Modified version of lookIn function to check if a card can be used to log in
	local chst = waitForPeripheral(ch, 5) -- Makes sure that the chests are still there
    local banklist = waitForList(chst, ch) -- Makes sure that the contents have loaded still
	local card = chst.getItemDetail(1)
	if card.nbt ~= nil then
		return card.nbt, card.displayName
	end
	return false
end

local seq = 0
local function makeUID()
	seq = seq+1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

local function sendPacket(payload)
	local packet = { uid=makeUID(), src=myBNP, dst=bankBNP, ttl=64, payload=payload }
	debugPrint("[SENDPACKET] Packet being sent: "..textutils.serialize(packet))
	modem.transmit(directConnetionChannel, PRIVATE_CHANNEL, packet)
end

-- Ensures startup on boot of Computer
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'bankApp.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('bankApp.lua')")
        f.close()
    end
end

--#endregion
--#region Bank App GUI
local basalt = require("basalt")

local loginF = false
local cAcctF = false

local main = basalt.getMainFrame():setBackground(colors.green)
local LoginFrame
local ATMframe
local username

local function errorPopup(msg)
	-- Make an error popup frame
	local errorFrame = main:addFrame()
		:centerHorizontal("parent")
		:centerVertical("parent")
		:setBackground(colors.orange)
		:setSize(31, 10)
	errorFrame:addLabel()
		:setText(msg)
		:setForeground(colors.red)
		:setPosition(2, 2)
		:setSize(29,4)
		:setAutoSize(false)
	errorFrame:addButton()
		:setText("OK")
		:setBackground(colors.orange)
		:setForeground(colors.red)
		:setSize(2,1)
		:setPosition(15, 8)
		:onClick(function()
			errorFrame:destroy()
		end)
end

local function fillLoginFrame()
	LoginFrame = main:addFrame():setBackground(colors.green):setSize(51,19)
	LoginFrame:addBigFont()
		:setText("BANK")
		:setPosition(21,3)
		:setBackground(colors.green)
	local userInput = LoginFrame:addInput()
		:centerHorizontal("parent")
		:setY(8)
		:setSize(25, 1)
		:setForeground(colors.white)
		:setBackground(colors.lightBlue)
		:setPlaceholder(" Enter Username here...")
		:setPlaceholderColor(colors.blue)
	local passInput = LoginFrame:addInput()
		:centerHorizontal("parent")
		:setY(10)
		:setSize(25, 1)
		:setForeground(colors.white)
		:setBackground(colors.lightBlue)
		:setPlaceholder(" Enter Password here...")
		:setPlaceholderColor(colors.blue)
	LoginFrame:addButton() -- Login Button
		:setPosition(16,12)
		:setSize(6, 1)
		:setText("Login")
		:setForeground(colors.white)
		:setBackground(colors.green)
		:onClick(
			function()
				username = userInput:getText()
				local password = passInput:getText()
				if username == "" or password == "" then
					local card,num = lookForCard(bankChest)
					if card then
						if password ~= "" then
							errorPopup("Login attempt accepted")
							sendPacket({type="LOGIN_ATTEMPT", card = card, pin = password, cardNum = num})
							loginF = true
						else
							errorPopup("Please enter pin in password feild")
						end
					else
						errorPopup("Missing Username or Password")
					end
				else
					errorPopup("Login attempt accepted")
					sendPacket({ type="LOGIN_ATTEMPT", user = username, pass = password })
					loginF = true
				end
			end)
	LoginFrame:addButton() -- Create Account Button
		:setPosition(23,12)
		:setSize(14, 1)
		:setText("Create Account")
		:setForeground(colors.white)
		:setBackground(colors.green)
		:onClick(
			function()
				username = userInput:getText()
				local password = passInput:getText()
				if username == "" or password == "" then
					errorPopup("Missing Username or Password")
				else
					errorPopup("Account info accepted")
					sendPacket({ type="ACCT_CREATE_REQ", user = username, pass = password })
					cAcctF = true
				end
			end)
end

fillLoginFrame()
local popup
local transactions
local balance
local balanceLabel
local transactionList
local loggedIn = false
local popupOpen = false
local cardLabel
local accountCards

local function buildATM(accountInfo)
	transactions = accountInfo.transactions
	balance = tostring(accountInfo.balance)
	ATMframe = main:addFrame():setBackground(colors.green):setSize(51,19):setVisible(true)
	loggedIn = true
	accountCards = accountInfo.cards

	local function deposit()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local label = popup:addLabel():setText("Please add deposit amount in inventory on the "..bankChest):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local submitted1 = false
		local total = 0
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		local button = popup:addButton():setSize(6,1):setPosition(2,10):setBackground(colors.green):setText("Submit")
		button:onClick(function()
			local packet = { type="BALANCE_UPDATE", deposit = 0, user = username, pass = accountInfo.pass }
			if submitted1 then
				if total > 0 then
					popup:destroy()
					packet.deposit = total
					sendPacket(packet)
					popupOpen = false
					label:setText("Please apply a redstone signal to packager")
				else
					errorPopup("Deposit must be at least $0.01")
				end
			else
				debugPrint("AddUp")
				total = addUp(bankChest)
				debugPrint("After AddUp")
				label:setText("You want to deposit $"..total..", correct?")
				button:setText("Yes"):setSize(3,1)
				popup:addButton():setSize(2,1):setPosition(7,10):setBackground(colors.red):setText("No"):onClick(function()
					total = addUp(bankChest)
					label:setText("You want to deposit $"..total..", correct? Place correct amount in "..bankChest.." and press No again to reconfirm")
				end)
				submitted1 = true
			end
		end)
	end
	local function withdrawl()
		local function specificWithdrawl()
			local total = 0
			local currentlySelected
			local coins = {}
			popup:destroy()
			popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6) -- Replace withdrawl with new popup frame
			local label = popup:addLabel():setText("What coins do you want?"):setPosition(2,2):setSize(23,1):setAutoSize(false)
			local totalLabel = popup:addLabel():setText("Total: "):setPosition(2,3):setSize(28,1):setAutoSize(false)
			local stopButton = popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
			popup:addButton():setSize(3,1):setPosition(26,8):setText("Add"):onClick(function(self)
				stopButton:setVisible(false)
				self:setVisible(false)
				local addPopup = popup:addFrame():setPosition(2,4):setSize(21,7)
				addPopup:addLabel():setText(currentlySelected.text):setPosition(2,2)
				addPopup:addLabel():setText("Negative #'s will remove from total"):setPosition(2,4):setSize(19,2):setAutoSize(false)
				local amountOfItem = addPopup:addInput():setPosition(2,3):setSize(19,1):setBackground(colors.white):setPlaceholder("Amount")
				local addPStopButton = popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop")
				addPStopButton:onClick(function() stopButton:setVisible(true) self:setVisible(true) addPopup:destroy() addPStopButton:destroy() end)
				addPopup:addButton():setSize(3,1):setPosition(2,6):setText("Add"):setBackground(colors.green):onClick(function()
					xpcall(function()
						total = total + tonumber(amountOfItem:getText())*currentlySelected.value
						table.insert(coins,{name=currentlySelected.name,amount=tonumber(amountOfItem:getText())})
						totalLabel:setText("Total: "..tostring(total))
					end,
					function()
						errorPopup("Amount must be a pure number eg. 1,2,3,-6")
					end)
					self:setVisible(true)
					stopButton:setVisible(true)
					addPopup:destroy()
					addPStopButton:destroy()
				end)
			end)
			local list = popup:addList():setPosition(2,4):setSize(21,7)
			list:onSelect(function() currentlySelected = list:getSelectedItem() end)
			for _,name in ipairs(valuesNameOnly) do
				local value = values[name]
				local displayName
				local prefix, material = name:match("^(%a+)_(%a+)$")
				
    			if prefix == "coin" then
    				displayName = material:gsub("^.", string.upper) .. " Coin"
				elseif prefix =="coinpile" then
					displayName = material:gsub("^.",string.upper).. " Coin Pile"
    			elseif prefix == "coinblock" then
        			displayName = material:gsub("^.", string.upper) .. " Coin Block"
    			end
				list:addItem({text=displayName,name=name,value=value})
			end
			popup:addButton():setSize(4,1):setPosition(26,6):setText("Send"):onClick(function()
				if next(coins) then
					sendPacket({type="WITHDRAWL",request=coins,user=username,pass=accountInfo.pass,address=myBNP})
					os.queueEvent("Withdrawl_start", total)
					label:setText("Waiting for withdrawl amount to arrive from Bank"):setSize(28,4)
					totalLabel:destroy()
					list:destroy()
				end
			end)
		end
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local submitted = false
		local label = popup:addLabel():setText("Please enter amount to withdrawl \n\n current balance: "..balance):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local amount = popup:addInput():setPosition(2,6):setPlaceholder("Amount")
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		popup:addButton():setSize(8,1):setPosition(10,10):setText("Specific"):onClick(function() specificWithdrawl() end)
		popup:addButton():setSize(6,1):setPosition(2,10):setText("Submit"):onClick(function()
			if submitted then
				popup:destroy()
				popupOpen = false
			else
				xpcall(
					function()
						local numAmount = tonumber(amount:getText())
						if numAmount < 0 then
							errorPopup("You can't withdrawl a negative number")
						elseif tonumber(balance) < numAmount then
							errorPopup("You can't withdrawl more than you have dummy")
						else
							label:setText("Waiting for withdrawl amount to arrive from Bank")
							sendPacket({ type="BALANCE_UPDATE", withdrawl = numAmount, user = username, pass = accountInfo.pass })
							os.queueEvent("Withdrawl_start", numAmount)
							amount:destroy()
							submitted = true
						end
					end,
					function()
						errorPopup("You cannot enter anything but a pure number example (13,27.1,1.99).")
					end)
			end
		end)
	end
	local function wire()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local label = popup:addLabel():setText("Please enter amount to wire and account name of wire destination | current balance: "..balance):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local dst = popup:addInput():setPosition(2,6):setPlaceholder("Dest")
		local amount = popup:addInput():setPosition(2,7):setPlaceholder("Amount")
		local submitted = false
		local dest
		local amt
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		popup:addButton():setSize(6,1):setPosition(2,10):setText("Submit"):onClick(function()
			if submitted then
				xpcall(function()
					dest = dst:getText()
					amt = amount:getText()
					debugPrint(dest.."  ,  "..amt)
					sendPacket({ type="WIRE_TRANSFER", user = username, pass = accountInfo.pass, wireDst = dest, amount = tonumber(amt) })
					popup:destroy()
					popupOpen = false
				end,
				function()
					errorPopup("You cannot enter anything but a pure number example (13,27.1,1.99).")
				end)
			else
				dest = dst:getText()
				amt = amount:getText()

				label:setText("You are trying to wire "..amt.." is that correct?")
				if tonumber(amt) < 0 then
					errorPopup("You can't wire a negative number")
				elseif tonumber(balance) < tonumber(amt)then
					errorPopup("You canot wire more than you have dummy")
				else
					submitted = true
				end
			end
		end)
	end
	local function card()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local overlayPopup
		cardLabel = popup:addLabel():setText("Do you want to Create a new card or change the pin of a existing card?"):setPosition(2,1):setSize(28,4):setAutoSize(false)
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		local function createNew()
			overlayPopup = popup:addFrame():setSize(30,8):setPosition(1,4)
			cardLabel:setText("Enter pin for new card.")
			local input = overlayPopup:addInput():setPlaceholder("Pin number..."):setPosition(2,1):setSize(13,1)
			overlayPopup:addButton():setText("Request Card Number"):setPosition(2,4):setSize(19,1):onClick(function()
				cardLabel:setText("Requesting a card number from bank server...")
				local pin = input:getText()
				sendPacket({type="REGISTER_PIN", register = true, pinNum=pin, pass = accountInfo.pass, user=username})
			end)
			overlayPopup:addButton():setSize(4,1):setPosition(26,7):setText("Back"):onClick(function() cardLabel:setText("Do you want to Create a new card or change the pin of a existing card?") overlayPopup:destroy() end)
		end
		local function editOld()
			overlayPopup = popup:addFrame():setSize(30,8):setPosition(1,4)
			cardLabel:setText("Choose a card")
			local keyedCards = {} -- Version of accountCards that is keyed by card Num to easily reference the data of specific cards
			local cardList = overlayPopup:addList():setPosition(1,1):setSize(13,5):setBackground(colors.blue):onSelect(function(self,index,item)
				local trf = "NO"
				if keyedCards[item.text].cardNBT then trf = "YES" end
				cardLabel:setText("Card:"..item.text.." Pin:"..keyedCards[item.text].pin.. " NBT:"..trf)
			end)
			for _,cData in pairs(accountCards) do
				debugPrint("cData = "..textutils.serialize(cData))
				cardList:addItem(cData.cardNum)
				keyedCards[cData.cardNum] = { pin = cData.pin, cardNBT = cData.cardNBT }
			end
			local input = overlayPopup:addInput():setPlaceholder("Pin number..."):setPosition(2,6):setSize(13,1)
			overlayPopup:addButton():setText("Change pin"):setPosition(2,7):setSize(10,1):onClick(function()
				cardLabel:setText("Requesting pin change...")
				local pin = input:getText()
				sendPacket({type="REGISTER_PIN", change = true, pinNum=pin, pass = accountInfo.pass, user=username, cardNum = cardList:getSelectedItem().text})
			end)
			overlayPopup:addButton():setSize(4,1):setPosition(26,7):setText("Back"):onClick(function() cardLabel:setText("Do you want to Create a new card or change the pin of a existing card?") overlayPopup:destroy() end)
		end
		popup:addButton():setText("Create"):setSize(6,1):setPosition(2,7):onClick(function() createNew() end)
		popup:addButton():setText("Edit"):setSize(4,1):setPosition(10,7):onClick(function() editOld() end)
    end

	LoginFrame:destroy()
	ATMframe:addLabel():setText("Username: "..username):setPosition(9,4):setSize(30,1):setBackground(colors.green):setForeground(colors.orange)
	balanceLabel = ATMframe:addLabel():setText("Balance: "..balance):setPosition(9,5):setSize(30,1):setBackground(colors.green):setForeground(colors.orange)
	transactionList = ATMframe:addList()
		:setEmptyText("No Transactions on account")
		:setPosition(9,6)
		:setSize(30,11)
		:setBackground(colors.orange)
		:setSelectedBackground(colors.orange)
		:setSelectedForeground(colors.black)
	for _,v in ipairs(transactions) do
		transactionList:addItem(v)
	end
	ATMframe:addButton():setText("Deposit"):setBackground(colors.green):setPosition(40,6):setSize(7,1):onClick(function()
			if popupOpen then -- Destroy any opened popups before opening
				popup:destroy()
			end
			deposit()
		end) -- Deposit Button
	ATMframe:addButton():setText("Withdrawl"):setBackground(colors.green):setPosition(40,8):setSize(9,1):onClick(function()
			if popupOpen then -- Destroy any opened popups before opening
				popup:destroy()
			end
			withdrawl()
		end) -- Withdrawl Button
	ATMframe:addButton():setText("Wire"):setBackground(colors.green):setPosition(40,10):setSize(4,1):onClick(function()
			if popupOpen then -- Destroy any opened popups before opening
				popup:destroy()
			end
			wire()
		end) -- Wire Button
	ATMframe:addButton():setText("Card"):setBackground(colors.green):setPosition(40,12):setSize(4,1):onClick(function()
            if popupOpen then -- Destroy any opened popups before opening
                popup:destroy()
            end
            card()
    end) -- Card Button
	ATMframe:addButton():setText("Leave"):setBackground(colors.green):setPosition(40,14):setSize(5,1):onClick(function()
			ATMframe:destroy()
			fillLoginFrame()
			loggedIn = false
		end) -- Leave Button
end

local function withdrawlLoop()
	local withdrawn = 0
	while true do
		local _,target = os.pullEvent("Withdrawl_start")
		debugPrint("Starting Withdrawl loop")
		repeat
			withdrawn = addUp(bankChest)
			os.sleep(5)
		until withdrawn == target
		if popupOpen then
			popup:destroy()
		end
		errorPopup("Check Inventory, Withdrawl has arrived")
	end
end

local function packetHandling(packet)
	local payload = packet.payload
	if packet.src ~= bankBNP then return end
	debugPrint(textutils.serialize(packet))
	if payload.type == "RESET" then
		bankBNP = nil
		os.reboot()
	elseif payload.type == "ATM_NUM" then
		ATMNum = payload.num
	elseif payload.type == "VALUES_RESP" then
		values = payload.values
	elseif payload.type == "ERROR" then
		errorPopup(payload.message)
	elseif payload.type == "ACCT_CREATED" and cAcctF then
		--move on to ATM with account info
		errorPopup("Account has been Created")
		cAcctF = false
		buildATM(payload.accountInfo)
	elseif payload.type == "LOGIN_RESP" and loginF then
		loginF = false
		if payload.confirm == "Allow" then
			-- move on to ATM with account info
			username = payload.name
			buildATM(payload.accountInfo)
		elseif payload.confirm == "Deny" then
			errorPopup("Passowrd Incorrect")
		elseif payload.confirm == "Void" then
			errorPopup("No account with current username")
		end
	elseif payload.type == "BALANCE_UPDATE_ACCT_RESP" and loggedIn then
		transactions = payload.accountInfo.transactions
		balance = payload.accountInfo.balance
		transactionList:clear()
		for _,v in ipairs(transactions) do
			transactionList:addItem(v)
		end
		balanceLabel:setText("Balance: "..balance)
		debugPrint("Tried to replace transactions and balance")
	elseif payload.type == "PIN_RESP" then
        if payload.removed then
			cardLabel:setText(payload.cardNum.." has been removed")
			accountCards = payload.cards
		elseif payload.cardNum then
            cardLabel:setText("New card number is "..payload.cardNum)
			accountCards = payload.cards
        elseif payload.changed then
            cardLabel:setText("Pin number changed to "..payload.newPin.." to see changes please back out and re-enter this screen")
			accountCards = payload.cards
        end
	end
end

local function listener()
    while true do
        local _, _, _, replyChannel, msg = os.pullEvent("modem_message")
        if interface and type(msg)=="table" and msg.uid then
			if directConnetionChannel == 1 then
				directConnetionChannel = replyChannel
			end
            packetHandling(msg)
        end
    end
end

local function setupCLI()
	local settingup = true
	while settingup do
		print("Please head to your bank to ask for a Server BNP to set up app, you may also try messaging them")
		write("Enter Bank Server BNP: ")
		local userin = read()
		bankBNP = userin
		if not myBNP then
			print("You don't have a BNP on this device please put one")
			write("Device BNP: ")
			userin = read()
			myBNP = userin
		end
		write("Do you want App to start on boot?(y/n)")
		userin = read()
		local startOnBootStr = "No"
		if userin == "y" then
			ensureStartup()
			startOnBootStr = "Yes"
			print("Ensured App starts when Computer is booted")
		else
			startOnBootStr = "No"
			print("App will not open on boot")
		end
		print("Current settings are: \nBank BNP: "..bankBNP.."\nStart on Boot: "..startOnBootStr.."\nDevice BNP: "..myBNP)
		print("\nDo you want to continue with these settings?(y/n)")
		userin = read()
		if userin == "y" then
			term.setTextColor(colors.yellow)
			print("Settings saved \n\nYou need to place a packager, and a frogport on top of the "..bankChest.." inventory.\n\nPlease name your frogport "..myBNP.." \n\nIf you do not do this you cannot withdrawl or deposit on this device\n\nPlease contact bank and ask what their frogport's adddress is, then place a sign on your packager and write \"[BankFrogportAddress] "..myBNP.."\"")
			term.setTextColor(colors.white)
			print("\nOnce you have finished all of this you may start the app.")
			settingup = false
		else
			print("resetting process")
			bankBNP = nil
		end
	end
end

--#endregion
if setupNeeded then
	setupCLI()
	setupNeeded = false
	saveConfigs()
else
	basalt.schedule(listener)
	basalt.schedule(withdrawlLoop)
	basalt.run()
end