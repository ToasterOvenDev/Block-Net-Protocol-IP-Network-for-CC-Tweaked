--#region Required processes for ATM
local chests = {}
local interface = {}
local content = {}
local bank = 1 -- Setup bank index
local other = 2 -- Setup other chest index
local values = {}
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

local function lookInBank()
    -- Wrap and load contents of bank chest
    content = {}

    local chest1 = waitForPeripheral(chests[bank], 5) --Makes sure that the chests are still there
    local banklist = waitForList(chest1, chests[bank]) --Makes sure that the contents have loaded still
    for slot, item in pairs(banklist) do
        local iname = item.name:match(":(.+)")
        if content[iname] then
            content[iname].count = content[iname].count+item.count
        else
            content[iname] = {count = item.count, slot = slot } -- {coin_copper=64,coin_diamond=3}
        end
    end
	print(textutils.serialize(content))
end

chestsFind()
lookInBank()

local function resolveBankInv(name)
	for i,inv in pairs(chests) do
		if name == inv then
			return i
		end
	end
end

local configFile = "conf"

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
    local configs = textutils.serialize({ bankBNP = bankBNP, bank = chests[bank], setupNeeded = setupNeeded })
	f.writeLine(configs)
    f.close()
end

local bal = 0
-- Calculate total value of chest contents
local function addUp()
    lookInBank()
    local total = 0
    for iname, amount in pairs(content) do
        local itemValue = values[iname] or 0
        total = total + (amount * itemValue)
    end
    bal = total
    return total
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
local LoginFrame = main:addFrame():setBackground(colors.green):setSize(51,19)
local ATMframe

local function buildATM(accountInfo)
	LoginFrame:setVisible(false)
	ATMframe = main:addFrame():setBackground(colors.green):setSize(51,19)
end

-- Make an error popup frame
local errorFrame = main:addFrame()
	:setVisible(false)
	:centerHorizontal("parent")
	:centerVertical("parent")
	:setBackground(colors.orange)
	:setSize(31,10)
local errorLabel = errorFrame:addLabel()
	:setText("Error")
	:setForeground(colors.red)
	:setPosition(1,2)
errorFrame:addButton()
	:setText("OK")
	:setBackground(colors.orange)
	:setForeground(colors.red)
	:setPosition(10,8)
	:onClick(function()
		errorFrame:setVisible(false)
	end)
local function errorPopup(msg)
	errorFrame:setVisible(true)
	errorLabel:setText(" "..msg)
end

LoginFrame:addFrame():setBackground(colors.black):setSize(10,19)
LoginFrame:addFrame():setBackground(colors.black):setSize(10,19):setPosition(42,1)
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
    :setPosition(14,12)
    :setSize(6, 1)
    :setText("Login")
    :setForeground(colors.white)
    :setBackground(colors.green)
    :onClick(
        function()
			local username = userInput:getText()
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
    :setPosition(22,12)
    :setSize(14, 1)
    :setText("Create Account")
    :setForeground(colors.white)
    :setBackground(colors.green)
    :onClick(
        function()
			local username = userInput:getText()
			local password = passInput:getText()
			if username == "" or password == "" then
				errorPopup("Missing Username or Password")
			else
				errorPopup("Account info accepted")
				sendPacket({ type="ACCT_CREATE_REQ", user = username, pass = password })
				cAcctF = true
			end
		end)

local function packetHandling(packet)
	local payload = packet.payload
	if packet.src ~= bankBNP then return end
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
		if payload and payload.confirm == "Allow" then
			-- move on to ATM with account info
			buildATM(payload.accountInfo)
		elseif payload and payload.confirm == "Deny" then
			errorPopup("Passowrd Incorrect")
		elseif payload and payload.confirm == "Void" then
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
basalt.run()