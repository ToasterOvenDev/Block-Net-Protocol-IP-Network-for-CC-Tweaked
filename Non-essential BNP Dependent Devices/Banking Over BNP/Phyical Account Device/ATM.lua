--#region Required processes for ATM
local chests = {}
local interface = {}
local content = {}
local bank = 1 -- Setup bank index
local other = 2 -- Setup other chest index
local values = { -- [[ replace this table with your own currency system (this is the lightman's currency system, link to mod in Readme)
    		["coin_copper"] = 0.01,
    		["coinpile_copper"] = 0.09,
    		["coinblock_copper"] = 0.36,
    		["coin_iorn"] = 0.10,
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
		} --]]
local bankBNP = nil
local ATMnum = os.getComputerID()
local setupNeeded = true

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

local debugFile = "log.txt"
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

local DEBUG = true
local function debugPrint(msg,fileOnly)
    fileOnly = fileOnly or false
    local time = os.date("%H:%M:%S")
	local f = fs.open(debugFile,"a")
	f.writeLine("[DEBUG "..time.."] " .. msg)
	f.close()
    if fileOnly then
		return
    elseif DEBUG then
        print("[DEBUG] " .. msg)
    end
end
debugPrint("[BOOT] Started logging",true)

if not modem then
    term.setTextColor(colors.red)
    print("No modem detected on any side. Please attach a modem and restart.")
    term.setTextColor(colors.white)
    return
else
    term.setTextColor(colors.green)
    print("Modem found on side: "..modemSide)
    term.setTextColor(colors.white)
end

modem.open(1200)

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

local function chestsFind()
    chests = {}
    interface = nil
    -- Find connected chests/barrels and modem
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "minecraft:chest") or peripheral.hasType(side, "minecraft:barrel") then
            table.insert(chests, side)
        elseif peripheral.hasType(side, "modem") then
            interface = peripheral.wrap(side)
        end
    end
    -- Validate number of connected chests
    if #chests < 2 then
        error("Need two chests connected!")
        return
    elseif #chests > 2 then
        error("Cannot have more than two chests connected!")
        return
    end
end

local function lookIn(ch)
    -- Wrap and load contents of bank chest
    content = {}
    local chest = waitForPeripheral(ch, 5) -- Makes sure that the chests are still there
    local banklist = waitForList(chest, ch) -- Makes sure that the contents have loaded still
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

chestsFind()
lookIn(chests[bank])

local function resolveBankInv(name)
	for i,inv in pairs(chests) do
		if name == inv then
			return i
		end
	end
end

local configFile = "ATM.conf"

local function loadConfigs()
	local f = fs.open(configFile,"r")
    local configs = textutils.unserialise(f.readAll())
    f.close()
	if configs == "" or configs == nil then
		print("Failed to load, using default variables")
		bankBNP = nil
		bank = 1
		setupNeeded = true
	else
		print("Loaded correctly")
		bankBNP = configs.bankBNP
		bank = resolveBankInv(configs.bank)
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
    local configs = textutils.serialize({ bankBNP = bankBNP, bank = chests[bank], setupNeeded = setupNeeded --[[ Values should be hardcoded ]]})
	f.writeLine(configs)
    f.close()
end

local bal = 0
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
    bal = total
    return total
end

local function sendChest(schest,dchest)
	debugPrint("SendChest Function")
	debugPrint(textutils.serialize(peripheral.getMethods(schest)))
	debugPrint(schest)
	debugPrint(dchest)
	for slot in pairs(waitForList(waitForPeripheral(schest, 5), schest)) do
		waitForPeripheral(schest, 5).pushItems(dchest, slot)
	end
end

local function withdrawlLoop()
	local o = chests[other]
	local b = chests[bank]
	local withdrawn = 0
	while true do
		local target = os.pullEvent("Withdrawl_start")
		repeat
			withdrawn = addUp(o)
			os.sleep(5)
		until withdrawn == target
		sendChest(o,b)
	end
end

local seq = 0
local function makeUID()
	seq = seq+1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

local function sendPacket(payload)
	local packet = { uid=makeUID(), src=ATMnum, dst=bankBNP, ttl=64, payload=payload }
	modem.transmit(1200, 1200, packet)
end

-- Ensures startup on boot of Computer
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'ATM.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('ATM.lua')")
        f.close()
    end
end

ensureStartup()

--#endregion
--#region ATM GUI
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
		:setText("Error")
		:setForeground(colors.red)
		:setPosition(2, 2)
		:setText(msg)
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
		:setText("ATM")
		:setPosition(22,3)
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
					errorPopup("Missing Username or Password")
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


local function buildATM(accountInfo)
	local transactions = accountInfo.transactions
	local balance = tostring(accountInfo.balance)
	ATMframe = main:addFrame():setBackground(colors.green):setSize(51,19):setVisible(true)
	local popupOpen = false

	local function deposit()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local label = popup:addLabel():setText("Please add deposit amount in inventory on the "..chests[bank].." inventory"):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local submitted1 = false
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		local button = popup:addButton():setSize(6,1):setPosition(2,10):setBackground(colors.green):setText("Submit")
		button:onClick(function()
			local total
			if submitted1 then
				popup:destroy()
				sendChest(chests[bank],chests[other])
				sendPacket({ type="BALANCE_UPDATE", deposit = total, user = username, pass = accountInfo.pass })
				popupOpen = false
			else
				debugPrint("AddUp")
				total = addUp(chests[bank])
				debugPrint("After AddUP")
				label:setText("You want to deposit $"..total..", correct? After submitting press the button above your head.")
				button:setText("Yes"):setSize(3,1)
				popup:addButton():setSize(2,1):setPosition(7,10):setBackground(colors.red):setText("No"):onClick(function()
					total = addUp(chests[bank])
					label:setText("You want to deposit "..total..", correct? After submitting press the button above your head.")
				end)
				submitted1 = true
			end
		end)
	end
	local function withdrawl()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		local submitted = false
		local label = popup:addLabel():setText("Please enter amount to withdrawl | current balance: "..balance):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local amount = popup:addInput():setPosition(2,6):setPlaceholder("Amount")
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		popup:addButton():setSize(6,1):setPosition(2,10):setText("Submit"):onClick(function()
			if submitted then
				popup:destroy()
				popupOpen = false
			else
				if tonumber(amount:getText()) < 0 then
					errorPopup("You can't withdrawl a negative number")
				else
					label:setText("Waiting for withdrawl amount to arrive from Bank...")
					sendPacket({ type="BALANCE_UPDATE", withdrawl = tonumber(amount:getText()), user = username, pass = accountInfo.pass })
					os.queueEvent("Withdrawl_start", tonumber(amount:getText()))
					amount:destroy()
					submitted = true
				end
			end
		end)
	end
	local function wire()
		popupOpen = true
		popup = ATMframe:addFrame():setSize(30,11):setPosition(9,6)
		popup:addLabel():setText("Please enter amount to wire and account name of wire destination | current balance: "..balance):setPosition(2,1):setSize(28,4):setAutoSize(false)
		local amount = popup:addInput():setPosition(2,6):setPlaceholder("Amount")
		local dst = popup:addInput():setPosition(2,7):setPlaceholder("Dest")
		popup:addButton():setSize(4,1):setPosition(26,10):setText("Stop"):onClick(function() popup:destroy() popupOpen = false end)
		popup:addButton():setSize(6,1):setPosition(2,10):setText("Submit"):onClick(function()
			if tonumber(amount:getText()) < 0 then
				errorPopup("You can't wire a negative number")
			else
				sendPacket({ type="WIRE_TRANSFER", user = username, pass = accountInfo.pass, wireDst = dst.getText(), amount = amount.getText() })
				popup:destroy()
				popupOpen = false
			end
		end)
	end

	LoginFrame:destroy()
	ATMframe:addLabel():setText("Username: "..username):setPosition(9,4):setSize(30,1):setBackground(colors.green):setForeground(colors.orange)
	ATMframe:addLabel():setText("Balance: "..balance):setPosition(9,5):setSize(30,1):setBackground(colors.green):setForeground(colors.orange)
	local transactionList = ATMframe:addList()
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
	ATMframe:addButton():setText("Leave"):setBackground(colors.green):setPosition(40,12):setSize(5,1):onClick(function()
			ATMframe:destroy()
			fillLoginFrame()
		end) -- Leave Button
end


local function packetHandling(packet)
	local payload = packet.payload
	if packet.src ~= bankBNP then return end
	debugPrint(textutils.serialize(packet))
	if payload.type == "RESET" then
		bankBNP = nil
		os.reboot()
	elseif payload.type == "BAL_RESP" then
		bal = payload.balance
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
			buildATM(payload.accountInfo)
		elseif payload.confirm == "Deny" then
			errorPopup("Passowrd Incorrect")
		elseif payload.confirm == "Void" then
			errorPopup("No account with current username")
		end
	end
end

local function listener()
    while true do
        local _, _, _, _, msg = os.pullEvent("modem_message")
        if interface and type(msg)=="table" and msg.uid then
            packetHandling(msg)
        end
    end
end

local function setupCLI()
	local settingup = true
	while settingup do
		write("Enter Bank Server BNP: ")
		local userin = read()
		bankBNP = userin
		print("Pick a inventory to be the input ")
		for _,inv in pairs(chests) do
			print("- "..inv)
		end
		userin = read()
		for i,inv in pairs(chests) do
			if userin == inv then
				print("Picked "..inv.." as input inventory")
				bank = i
			end
		end
		print("Current settings are: \nBank BNP: "..bankBNP.."\nInput Inventory: "..chests[bank])
		print("\nDo you want to continue with these settings? (y/n)")
		userin = read()
		if userin == "y" then
			print("Settings saved, please restart device")
			settingup = false
		else
			print("resetting process")
			bankBNP = nil
			bank = 1
		end
	end
end

if setupNeeded then
	setupCLI()
	setupNeeded = false
	saveConfigs()
end
--#endregion
basalt.schedule(listener)
basalt.schedule(withdrawlLoop)
basalt.run()