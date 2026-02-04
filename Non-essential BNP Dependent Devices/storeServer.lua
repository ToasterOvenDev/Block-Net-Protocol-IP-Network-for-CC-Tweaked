-- Store Server
-- Allows for online purchase of items listed in a create storage network
-- Asks bank to wire transfer from purchasee to the store's connected account
-- Has all features of Server Template

-- ==========================
-- SELF-LAUNCH IN MULTISHELL
-- ==========================
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    -- Only launch a new tab if we are running in the first tab
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

-- ==========================
-- DEBUG MODE
-- ==========================
local debugFile = "server.log"
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

local DEBUG = false
local function debugPrint(msg,fileOnly)
    fileOnly = fileOnly or false
    local time = os.date("%H:%M:%S")
	local f = fs.open(debugFile,"a")
	f.writeLine("[DEBUG "..time.."] " .. msg)
	f.close()
    if DEBUG and fileOnly then
		return
    elseif DEBUG then
        print("[DEBUG] " .. msg)
    end
end
debugPrint("[BOOT] Started logging",true)

-- ==========================
-- FINDS MODEMS (can also find other peripherals, just add a new var and a new if for p's type)
-- ==========================
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
 
local PRIVATE_CHANNEL = os.getComputerID()
modem.open(1)
modem.open(PRIVATE_CHANNEL)

-- CONFIGURATION VARIABLES
local BNP_FILE = "BNP.txt" -- the name of the BNP text file for loading/saving
local myBNP
local routerChannel = 1
local SERVERNAME = "storeServer.lua"
local serverConfigs = { items = {}, storeBankAcctUN = nil }
local configFile = "storeServer.config"

-- ==========================
-- LOAD OR CREATE BNP
-- ==========================
if not fs.exists(BNP_FILE) then
    local f = fs.open(BNP_FILE,"w")
    f.writeLine("")
    f.close()
    term.setTextColor(colors.red)
    print(BNP_FILE.." created. Use CLI command 'set BNP <BNP>' to assign BNP")
    term.setTextColor(colors.white)
    myBNP = nil
else
    local f = fs.open(BNP_FILE,"r")
    myBNP = f.readLine()
    f.close()
    if myBNP=="" then myBNP=nil end
end

local function saveBNP()
    local f = fs.open(BNP_FILE,"w")
    f.writeLine(myBNP)
    f.close()
end

if not fs.exsits(configFile) then
	local f = fs.open(configFile,"w")
	f.write("")
	f.close()
else
	local f = fs.open(configFile,"r")
	local config = f.readAll()
	if config == "" then
		serverConfigs = {
            items = {},
            storeBankAcctUN = nil
		}
	else
		-- placeholder
        items = config.items
        storeBankAcctUN = config.storeBankAcctUN
	end
end
-- ==========================
-- PACKET UTILITIES
-- ==========================
local seq = 0
local function makeUID()
    seq = seq + 1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

local function sendPacket(dst,payload)
    if not myBNP then
        print("Set your BNP first with 'set BNP <BNP>' before sending packets.")
        return
    end
    local packet = { uid=makeUID(), src=myBNP, dst=dst, ttl=64, payload=payload }
    modem.transmit(routerChannel, PRIVATE_CHANNEL, packet)
end

local function broadcast(payload)
    local packet = { uid=makeUID(), src=myBNP or "unknown", dst="0", ttl=64, payload=payload }
    modem.transmit(1,1,packet)
end


-- HELLO_REPLY
local function replyHello(requester, private_channel)
    if not myBNP then return end
    sendPacket(requester,{
        type = "HELLO_REPLY",
        private_channel = PRIVATE_CHANNEL
    })
    debugPrint("Replied to HELLO_REQUEST from "..requester)
    if private_channel and routerChannel == 1 then
        routerChannel = private_channel
        debugPrint("Router channel set to "..routerChannel)
    end
end

local function switchReply(side, packet)
    local payload = packet.payload
    -- Only respond if this is a switch hello from a switch
    if not payload.switch then return end
    -- Make sure the client has an BNP
    if not myBNP then
        debugPrint("Received S_H from switch but server BNP is not set, ignoring.")
        return
    end
    -- Respond to switch with our BNP and private channel
    local response = {
        type = "S_H",
        switch = false,          -- client, not a switch
        src_ip = myBNP,
        private_channel = PRIVATE_CHANNEL -- or whatever channel we learned from HELLO
    }
	routerChannel = payload.private_channel --Will ALWAYS override the router channel to account for network expansion
    -- Send back to the switch using the port we received from
    sendPacket(packet.src, response)
    debugPrint("Responded to S_H from switch " .. tostring(packet.src) .. " with BNP " .. myBNP)
end
-- ==========================
-- RECEIVE LOOP
-- ==========================

local function receiveLoop(packet,side)
    if type(packet)=="table" and myBNP and (packet.dst==myBNP or packet.dst=="0") then
        local payload = packet.payload
        if type(payload)~="table" then
            debugPrint("Invalid payload from "..tostring(packet.src))
			return
        else
            if payload.type == "HELLO_REQUEST" then
                replyHello(packet.src, payload.private_channel)
				return
            elseif payload.type == "S_H" then
                switchReply(side,packet)
                routerChannel = payload.private_channel -- Always overrides previous routerchannel to make network expansion easier
				return
            elseif payload.type == "PING" then
                debugPrint("Received PING from "..packet.src)
                sendPacket(packet.src,{ type="PING_REPLY", message="pong" })
				return
            else
                debugPrint(("Message from %s: %s"):format(packet.src, textutils.serialize(payload)))
				return
            end
        end
    end
end


local function listener()
    while true do
        local _, side, _, _, msg = os.pullEvent("modem_message")
        receiveLoop(msg,side)
    end
end
-- ==========================
-- CLI LOOP
-- ==========================
local function cliLoop()
    print("Server ready. Commands: set BNP <BNP>, set password <password>, BNP, list hosts, exit")
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args,word) end
        local cmd = args[1]
        if cmd=="exit" then return
        elseif cmd=="set" and args[2]=="BNP" and args[3] then
            myBNP=args[3]; saveBNP(); print("BNP set to "..myBNP)
        elseif cmd=="BNP" then print("Current BNP: "..tostring(myBNP))
        elseif cmd=="debugmode" and args[2] then
            if args[2] == "true" then
                DEBUG = true
           	elseif args[2] == "false" then
                DEBUG = false
			end
        else
            print("Commands: set BNP <BNP>, set password <password>, BNP, list hosts, exit")
        end
    end
end

-- START SERVER
-- autostart setup
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'"..SERVERNAME.."\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('"..SERVERNAME.."')")
        f.close()
    end
end

ensureStartup()

parallel.waitForAny(listener, cliLoop)






--#region Old beta version of storeServer
--[[
local stockTicker = peripheral.find("Create_StockTicker")
local function lookInStock()
    local storage = stockTicker.stock(false)

    local function titleCase(str)
        return (str:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end))
    end

    for i,v in ipairs(storage) do
        local item = v.name:match(":(.+)")
        local itemSpaced = item:gsub("_"," ")
        local itemCapped = titleCase(itemSpaced)
        v.dname = itemCapped -- Provides a user friendly display name
    end

    local selection = {}

    for i,v in ipairs(storage) do
        selection[i] = (tostring(i)..":"..tostring(v.count).." "..v.dname)
    end

    return selection, storage
end

peripheral.find("modem",rednet.open)

local stock, storage = lookInStock()
print(textutils.serialise(stock))
rednet.host("shopping","Store")

local function matchDNametoName(dname) -- Returns the index of the display name provieded with its match in storage
    stock,storage = lookInStock()
    for i,v in ipairs(storage) do
        if v.dname == dname then
            return i
        end
    end
    return false
end

local function listener()
    while true do
        local id,mes = rednet.receive()
        local payload = mes.payload
        print("Got a message!!")
        if not payload then
            print("Bad Packet Dropping...")
            print(textutils.serialize(mes))
        elseif payload.type == "STOCK_REQ" then
            stock,storage = lookInStock()
            local payload = {
                type = "STORE_STOCK",
                stock = stock
            }
            rednet.send(id,{payload = payload})
        elseif payload.type == "BUY_REQ" then
            local itemNum = matchDNametoName(payload.itemName)
            if not itemNum then
                local payload = {
                    type = "ERROR",
                    message = "Item not in stock, we apologize!"
                }
                rednet.send(id,{payload = payload})
            else
                local itemAmt = tonumber(payload.itemAmmount)
                local address = payload.homeAdd
                local item =  storage[itemNum].name
                if itemAmt <= storage[itemNum].count then
                    stockTicker.requestFiltered(address,{ name = item, _requestCount = itemAmt })
                    stock,storage = lookInStock()
                    print(payload.itemAmmount.." "..item.."s purchased")
                else
                    local payload = {
                        type = "ERROR",
                        message = "Not enough in stock, we apologize!"
                    }
                    rednet.send(id,{payload = payload})
                end
            end
        end
    end
end

listener()

]]
--#endregion
--#region Old beta version of Customer
--[[
local function listener()
    while true do
        local _,mes = rednet.receive()
        local payload = mes.payload
        if payload.type == "STORE_STOCK" then
            local y = 15
            for i,v in ipairs(payload.stock) do
                if i <= y then
                print(v)
                else
                    os.pullEvent("key")
                    y = y*2
                end
            end
        elseif payload.type == "ERROR" then
            print(payload.message)
        end
    end
end


local function CLI()
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args, word) end
        local cmd = args[1]
        if cmd == "exit" then return
        elseif cmd == "Stock?" then
            rednet.send(8,{payload = {type = "STOCK_REQ"}})
        elseif cmd == "buy" then
            if not args[4] then 
                print("Not enough arguments")
            else
                local payload = {
                    type = "BUY_REQ",
                    itemNum = args[2],
                    itemAmmount = args[3],
                    homeAdd = args[4],
                }
                rednet.send(8,{payload = payload})
            end
        end
    end
end

parallel.waitForAny(CLI,listener)
]]

--#endregion