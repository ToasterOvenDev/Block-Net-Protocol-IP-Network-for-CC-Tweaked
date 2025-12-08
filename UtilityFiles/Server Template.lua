--This is a template for if you want to make your own server for my network
-- Features include multishell launch
-- Debug printing with a command to turn it on and off
-- Automatic locating of connected modems
-- Multi-channel BNP system
-- Reply to hello packets and switch hello packets
-- Receive loop to process recieved packets
-- Startup on boot

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
local DEBUG = false
local function debugPrint(msg)
    if DEBUG then print("[DEBUG] " .. msg) end
end

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
local SERVERNAME = "placeholder.lua" -- For ensure startup replace 'placeholder' with your server's name

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
    local packet = { uid=makeUID(), src=myBNP, dst=resolved, ttl=8, payload=payload }
    modem.transmit(routerChannel, PRIVATE_CHANNEL, packet)
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
local function receiveLoop()
    while true do
        local e, side, ch, reply, message, dist = os.pullEvent("modem_message")
        if type(message)=="table" and myBNP and (message.dst==myBNP or message.dst=="0") then
            local payload = message.payload
            if type(payload)~="table" then
                debugPrint("Invalid payload from "..tostring(message.src))
            else
                if payload.type == "HELLO_REQUEST" then
                    replyHello(message.src, payload.private_channel)
                elseif payload.type == "S_H" then
                    switchReply(side,message)
                    routerChannel = payload.private_channel -- Always overrides previous routerchannel to make network expansion easier
                elseif payload.type == "PING" then
                    debugPrint("Received PING from "..message.src)
                    sendPacket(message.src,{ type="PING_REPLY", message="pong" })
                else
                    debugPrint(("Message from %s: %s"):format(message.src, textutils.serialize(payload)))
                end
            end
        end
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

if not fs.exists(FILE_DIR) then fs.makeDir(FILE_DIR) end
parallel.waitForAny(receiveLoop, cliLoop)
