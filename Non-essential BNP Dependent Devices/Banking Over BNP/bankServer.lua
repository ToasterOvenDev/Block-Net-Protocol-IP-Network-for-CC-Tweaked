-- bankServer.lua
-- All template features
-- Bank Packet handling
-- Account tracking by Account ID
-- Password protected balance requesting

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

-- CONFIGURATION VARIABLES
local IP_FILE = "ip.txt" -- the name of the IP text file for loading/saving
local ACCTS_FILE = "accts.txt" -- the name of the Accounts file for loading/saving
local Accts = {} -- Holds all the accounts and connected info in a dictionary
local userPswds = {} -- Holds all uncreated user passwords, and some created, gets cleared every boot
local userIPS = {}
local myIP
local routerChannel = 1
local SERVERNAME = "bankServer.lua" -- For ensure startup
local modems = {}
local interfaces = {}
local PRIVATE_CHANNEL = os.getComputerID()
local monitor = peripheral.wrap("top") -- Change this to whatever side the monitor is on


-- ==========================
-- FINDS MODEMS
-- ==========================
local function findModems()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "modem") then
            table.insert(modems, side)
        end
    end
end

findModems()

local publicInterface = modems[1]
local bankInterface = modems[2]

local function setUpInterfaces()
    findModems()
    local pi = peripheral.wrap(publicInterface)
    local bi = peripheral.wrap(bankInterface)
    interfaces[publicInterface] = pi
    interfaces[bankInterface] = bi
    pcall(function()
        pi.open(1)                -- broadcast/discovery
        pi.open(PRIVATE_CHANNEL)  -- unicast
        bi.open(1)                -- broadcast/discovery
        bi.open(PRIVATE_CHANNEL)  -- unicast
    end)
    print("Opened public modem on side "..publicInterface.." (channels 1 + "..PRIVATE_CHANNEL..")")
    print("Opened bank modem on side "..bankInterface.." (channels 1 + "..PRIVATE_CHANNEL..")")

    if next(interfaces) == nil then error("No modems found!") end
end
setUpInterfaces()
-- ==========================
-- LOAD OR CREATE IP
-- ==========================
if not fs.exists(IP_FILE) then
    local f = fs.open(IP_FILE,"w")
    f.writeLine("")
    f.close()
    term.setTextColor(colors.red)
    print(IP_FILE.." created. Use CLI command 'set ip <ip>' to assign IP")
    term.setTextColor(colors.white)
    myIP = nil
else
    local f = fs.open(IP_FILE,"r")
    myIP = f.readLine()
    f.close()
    if myIP=="" then myIP=nil end
end

local function saveIP()
    local f = fs.open(IP_FILE,"w")
    f.writeLine(myIP)
    f.close()
end
-- ==========================
-- LOAD OR CREATE ACCOUNTS
-- ==========================
if not fs.exists(ACCTS_FILE) then
    local f = fs.open(ACCTS_FILE, "w")
    f.writeLine("")
    f.close()
    term.setTextColor(colors.green)
    print(ACCTS_FILE.." created.")
    term.setTextColor(colors.white)
    Accts = {}
else
    local f = fs.open(ACCTS_FILE, "r")
    Accts = f.readAll()
    f.close()
    if Accts=="" then Accts=nil end
end

local function saveAccts()
    local f = fs.open(ACCTS_FILE,"w")
    for acct in pairs(Accts) do
        f.writeLine(textutils.serialize(Accts[acct]))
    end
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

-- XOR encrypt/decrypt
local function xor(data, key)
    local out = {}
    for i = 1, #data do
        local db = string.byte(data, i)
        local kb = string.byte(key, (i - 1) % #key + 1)
        out[i] = string.char(bit32.bxor(db, kb))
    end
    return table.concat(out)
end

local function sendPacketPublic(dst,payload)
    if not myIP then
        print("Set your IP first with 'set ip <ip>' before sending packets.")
        return
    end
    local packet = { uid=makeUID(), src=myIP, dst=dst, ttl=8, payload=payload }
    interfaces[publicInterface].transmit(routerChannel, PRIVATE_CHANNEL, packet)
end

local function sendPacketBank(dst,payload)
    if not myIP then
        print("Set your IP first with 'set ip <ip>' before sending packets.")
        return
    end
    local packet = { uid=makeUID(), src=myIP, dst=dst, ttl=8, payload=payload }
    interfaces[bankInterface].transmit(1,1,packet)
end

-- HELLO_REPLY
local function replyHello(requester, private_channel)
    if not myIP then return end
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
    -- Make sure the client has an IP
    if not myIP then
        debugPrint("Received S_H from switch but server IP is not set, ignoring.")
        return
    end
    -- Respond to switch with our IP and private channel
    local response = {
        type = "S_H",
        switch = false,          -- client, not a switch
        src_ip = myIP,
        private_channel = PRIVATE_CHANNEL -- or whatever channel we learned from HELLO
    }
	routerChannel = payload.private_channel --Will ALWAYS override the router channel to account for network expansion
    -- Send back to the switch using the port we received from
    sendPacket(packet.src, response)
    debugPrint("Responded to S_H from switch " .. tostring(packet.src) .. " with IP " .. myIP)
end

-- Makes the bank send a broadcast toward all physical accounts to ask for an update on funds
local function updateAccts()
    while true do
        local payload = { type="BALANCE_REQUEST" }
        sendPacketBank(0,payload)
        os.sleep(15)
    end
end

-- When Constructed is received this function adds the new account and it's balance to the Accts dictionary
local function learnAccount(payload)
    local ID = payload.ACCTID
    local balance = payload.balance
    local userPswd = userPswds[ID]
    local entry = { Balance=balance, UserPassword=userPswd }
    Accts[ID] = entry
    saveAccts()
end

-- ==========================
-- RECEIVE LOOP
-- ==========================
local function receiveLoop()
    while true do
        local e, side, ch, reply, message, dist = os.pullEvent("modem_message")
        if type(message)=="table" and myIP and (message.dst==myIP or message.dst=="0") then
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
                    sendPacketPublic(message.src,{ type="PING_REPLY", message="pong" })
                elseif payload.type == "BALANCE_REPLY" then -- Updates balance on server from the physical account devices
                    Accts[payload.ID].Balance = payload.balance
                elseif payload.type == "BALANCE_REQUEST" then -- From the client sends the amount if client's password is correct
                    local packet
                    if xor(payload.pass,payload.ACCTID) == Accts[payload.ID].userPassword then
                        packet = { type="BALANCE_REPLY", balance=Accts[payload.ID].Balance }
                    else 
                        packet = { type="ERROR", message="Invalid Password." }
                    end
                    sendPacketPublic(message.src,packet)
                elseif payload.type == "TRANSACTION_DENY" then -- Bank will basically forward this to original requester
                    sendPacketPublic(payload.rqsterIP,payload)
                elseif payload.type == "TRANSACTION_ACPT" then -- Bank will also basically forward this to the original requester
                    sendPacketPublic(payload.rqsterIP,payload)
                elseif payload.type == "TRANSACTION_REQUEST" then -- Basically forwards the request to the account specified
                    sendPacketBank(payload.ACCTID,payload)
                elseif payload.type == "C_ACCT_REQUEST" then
                    -- From a client requesting to make an account with the bank, will update a monitor connected to let employees know about the request (Doesn't add new acct ID to accts)
                    -- Will also add a password that is given through the request to a dictonary called userPswds
                    userPswds[payload.ACCTID] = xor(payload.password,payload.ACCTID)
                    userIPS[payload.ACCTID] = message.src
                    --put on montitor ("Physical Account for Account ID: " .. payload.ACCTID .. " Needed")
                elseif payload.type == "CONSTRUCTED" then -- From a physical account device letting the server know about the new account
                    learnAccount(payload)
                    local packet = { type="ACCT_CONFIRMED", message="Account has been made, you owe $10 within 7 business days to keep account open. Contact for more information or exemptions." }
                    sendPacketPublic(userIPS[payload.ID],packet)
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
    print("Server ready. Commands: set ip <ip>, set password <password>, ip, list hosts, exit")
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args,word) end
        local cmd = args[1]
        if cmd=="exit" then return
        elseif cmd=="set" and args[2]=="ip" and args[3] then
            myIP=args[3]; saveIP(); print("IP set to "..myIP)
        elseif cmd=="ip" then print("Current IP: "..tostring(myIP))
        elseif cmd == "setpublicinterface" then --> Set interfaces, public side and private side
            for i,side in ipairs(modems) do 
                if side == args[2] and publicInterface ~= modems[i] then -- Change public interface
                    bankInterface = publicInterface
                    publicInterface = modems[i]
                    print("public interface set to:", publicInterface)
                    break
                elseif side == args[2] and publicInterface == modems[i] then -- Already public interface
                    print("Interface is already set as public.")
                    break
                end
            end
        elseif cmd=="debugmode" and args[2] then
            if args[2] == "true" then
                DEBUG = true
           	elseif args[2] == "false" then
                DEBUG = false
			end
        else
            print("Commands: set ip <ip>, set password <password>, ip, list hosts, exit")
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

parallel.waitForAny(receiveLoop, cliLoop, updateAccts)