-- fileServer.lua Version 1.4
-- CC:Tweaked server for file sharing with password protection
-- Uses HELLO_REPLY only, auto BNP and password files, restricts transfers to /files/
-- Added automatic multishell self-launch
-- Added ACK packets to ensure connections and for less clog in terminal with debug mode disabled

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
-- ORIGINAL FILE SERVER CODE STARTS HERE
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

-- CONFIGURATION
local CHUNK_SIZE = 512
local BNP_FILE = "BNP.txt"
local PASSWORD_FILE = "server_password.txt"
local FILE_DIR = "/files/"

-- STATE
local hosts = {}
local myBNP
local SERVER_PASSWORD 
local routerChannel = 1

-- LOAD OR CREATE BNP
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

-- LOAD OR CREATE SERVER PASSWORD
if not fs.exists(PASSWORD_FILE) then
    local f = fs.open(PASSWORD_FILE,"w")
    f.writeLine("")
    f.close()
    term.setTextColor(colors.green)
    print(PASSWORD_FILE.." created. Use CLI command 'set password <password>' to assign a server password.")
    term.setTextColor(colors.red)
    print("IF PASSWORD NOT SET FILE SERVER WILL NOT WORK; TO MAKE PUBLIC RESTART DEVICE AND DO NOT SET PASSWORD!!")
    term.setTextColor(colors.white)
    SERVER_PASSWORD = nil
else
    local f = fs.open(PASSWORD_FILE,"r")
    SERVER_PASSWORD = f.readLine()
    f.close()
end

local function savePassword()
    local f = fs.open(PASSWORD_FILE,"w")
    f.writeLine(SERVER_PASSWORD)
    f.close()
end

-- LOAD HOSTS KEYWORDS
if fs.exists("hosts.txt") then
    local file = fs.open("hosts.txt","r")
    while true do
        local line = file.readLine()
        if not line then break end
        local key, BNP = line:match("^(%S+)%s+(%S+)$")
        if key and BNP then hosts[key]=BNP end
    end
    file.close()
end

-- PACKET UTILITIES
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
    local resolved = hosts[dst] or dst
    if not resolved then
        print("Unknown destination: "..tostring(dst))
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
-- FILE TRANSFER FUNCTIONS
local function sendFile(dst, filename)
    local fullPath = FILE_DIR..filename
    if not fs.exists(fullPath) then
        debugPrint("File does not exist in "..FILE_DIR..": "..filename)
        return
    end

    local f = fs.open(fullPath,"r")
    local data = f.readAll()
    f.close()

    local chunks = {}
    for i=1,#data,CHUNK_SIZE do
        local chunk = data:sub(i, math.min(i+CHUNK_SIZE-1,#data))
        table.insert(chunks,chunk)
    end

    debugPrint("Sending file "..filename.." to "..dst.." in "..#chunks.." chunks")
    for i,chunk in ipairs(chunks) do
        sendPacket(dst,{ type="FILE_CHUNK", filename=filename, seq=i, total=#chunks, data=chunk })
    end
    sendPacket(dst,{ type="FILE_END", filename=filename })
    print("File "..filename.." sent successfully to " .. dst)
end

-- RECEIVE LOOP
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
                elseif payload.type == "ACK_START" then
                    if not SERVER_PASSWORD then
                        print("No server password set. Cannot process file requests.")
                        sendPacket(message.src,{ type="ERROR", message="Server has no password set and is not public" })
                    elseif payload.password == SERVER_PASSWORD then
                        debugPrint("ACK received establishing connection to send file")
                        sendPacket(message.src,{ type="ACK" })
                    else
                        debugPrint("Invalid password from "..message.src.." for "..payload.filename)
                        sendPacket(message.src,{ type="ERROR", message="Invalid password" })
                    end
                elseif payload.type == "FILE_REQUEST" then
                    term.setTextColor(colors.blue)
                    print("Connection fully established sending file to " .. message.src)
                    term.setTextColor(colors.white)
                    sendFile(message.src,payload.filename)
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

-- CLI LOOP
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
        elseif cmd=="set" and args[2]=="password" and args[3] then
            SERVER_PASSWORD=args[3]; savePassword(); print("Server password set")
        elseif cmd=="BNP" then print("Current BNP: "..tostring(myBNP))
        elseif cmd=="list" and args[2]=="hosts" then
            print("Known hosts:")
            for k,v in pairs(hosts) do print("  "..k.." -> "..v) end
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
    if not startupContent:match("shell%.run%(\'fileServer.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('fileServer.lua')")
        f.close()
    end
end

ensureStartup()

if not fs.exists(FILE_DIR) then fs.makeDir(FILE_DIR) end
parallel.waitForAny(receiveLoop, cliLoop)
