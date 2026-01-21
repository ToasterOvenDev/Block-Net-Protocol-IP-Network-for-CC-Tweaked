local M = {}

M.chests = {}
M.interface = {}
M.content = {}
M.bank = 1 -- Setup bank index
M.other = 2 -- Setup other chest index
M.values = {}
M.bankBNP = nil
M.ATMnum = os.getComputerID()
M.setupNeeded = true

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

function M.chestsFind()
    M.chests = {}
    M.interface = nil
    -- Find connected chests/barrels and modem
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "minecraft:chest") or peripheral.hasType(side, "minecraft:barrel") then
            table.insert(M.chests, side)
        elseif peripheral.hasType(side, "modem") then
            M.interface = peripheral.wrap(side)
        end
    end
    -- Validate number of connected chests
    if #M.chests < 2 then
        error("Need two chests connected!")
        return
    elseif #M.chests > 2 then
        error("Cannot have more than two chests connected!")
        return
    end
end

function M.lookInBank()
    -- Wrap and load contents of bank chest
    M.content = {}

    local chest1 = waitForPeripheral(M.chests[M.bank], 5) --Makes sure that the chests are still there
    local banklist = waitForList(chest1, M.chests[M.bank]) --Makes sure that the contents have loaded still
    for slot, item in pairs(banklist) do
        local iname = item.name:match(":(.+)")
        if M.content[iname] then
            M.content[iname].count = M.content[iname].count+item.count
        else
            M.content[iname] = {count = item.count, slot = slot } -- {coin_copper=64,coin_diamond=3}
        end
    end
	print(textutils.serialize(M.content))
end

M.chestsFind()
M.lookInBank()

local function resolveBankInv(name)
	for i,inv in pairs(M.chests) do
		if name == inv then
			return i
		end
	end
end

local configFile = "ATM.conf"

function M.loadConfigs()
	local f = fs.open(configFile,"r")
    local configs = textutils.unserialise(f.readAll())
    f.close()
	if configs == "" or configs == nil then
		print("Failed to load, using default variables")
		M.bankBNP = nil
		M.bank = 1
		M.setupNeeded = true
	else
		print("Loaded correctly")
		M.bankBNP = configs.bankBNP
		M.bank = resolveBankInv(configs.bank)
		M.setupNeeded = configs.setupNeeded
	end
end

if not fs.exists(configFile) then
	local f = fs.open(configFile,"w") f.writeLine("") f.close()
else
	M.loadConfigs()
end

function M.saveConfigs()
	local f = fs.open(configFile,"w")
    local configs = textutils.serialize({ bankBNP = M.bankBNP, bank = M.chests[M.bank], setupNeeded = M.setupNeeded })
	f.writeLine(configs)
    f.close()
end

M.bal = 0
-- Calculate total value of chest contents
function M.addUp()
    M.lookInBank()
    local total = 0
    for iname, amount in pairs(M.content) do
        local itemValue = M.values[iname] or 0
        total = total + (amount * itemValue)
    end
    M.bal = total
    return total
end

local seq = 0
local function makeUID()
	seq = seq+1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

function M.sendPacket(payload)
	local packet = { uid=makeUID(), src=M.ATMnum, dst=M.bankBNP, ttl=64, payload=payload }
	modem.transmit(1200, 1200, packet)
end

local function packetHandling(packet)
	local payload = packet.payload
	if packet.src ~= M.bankBNP then return end
	if payload.type == "RESET" then
		M.bankBNP = nil
		os.reboot()
	elseif payload.type == "BAL_RESP" then
		M.bal = payload.balance
	elseif payload.type == "ATM_NUM" then
		M.ATMNum = payload.num
	elseif payload.type == "VALUES_RESP" then
		M.values = payload.values
	elseif payload.type == "HELLO_REQUEST" then

	end
end

function M.listener()
    while true do
        local _, _, _, _, msg = os.pullEvent("modem_message")
        if M.interface and type(msg)=="table" and msg.uid then
            packetHandling(msg)
        end
    end
end

-- Ensures startup on boot of Computer
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'ATMgui.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('ATMgui.lua')")
        f.close()
    end
end

ensureStartup()

return M
