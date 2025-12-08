-- wirelessClient.lua Version 1.8
-- Merged: client.lua v1.7 features + wireless tower discovery/multi-channel support
-- Adds: multi-channel routing, file transfer, host sync, ACK, S_H handling
-- Preserves: automatic tower scanning, signal strength, reconnect logic
-- SELF-LAUNCH IN MULTISHELL (Forge-safe)
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

-- DEBUG MODE
local DEBUG = false
local function debugPrint(msg) if DEBUG then print("[DEBUG] " .. tostring(msg)) end end

-- NETWORK CONFIG / MULTI-CHANNEL
local routerChannel = 1                -- channel used to send via tower/router (learned)
local PRIVATE_CHANNEL = os.getComputerID()  -- per-client reply channel
local seq = 0

-- Attempt to automatically find a modem (robust to side)
local modem, modemSide
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
    local p = peripheral.wrap(side)
    if p and peripheral.getType(side) == "modem" then
        modem = p
        modemSide = side
        break
    end
end

if not modem then
    term.setTextColor(colors.red)
    print("No modem detected. Attach a modem and restart.")
    term.setTextColor(colors.white)
    return
else
    term.setTextColor(colors.green)
    print("Modem found on side: "..tostring(modemSide))
    term.setTextColor(colors.white)
end

-- Ensure we open channels we will use
local function openChannel(ch)
    if type(ch) ~= "number" then return end
    pcall(function() modem.open(ch) end)
    debugPrint("Opened channel "..tostring(ch))
end
openChannel(1)
openChannel(PRIVATE_CHANNEL)

-- FILES
local BNP_FILE = "BNP.txt"
local HOSTS_FILE = "hosts.txt"
local SERVER_FILE = "host_server_ip.txt"
local CONNECTED_TOWER_FILE = "connected_tower.txt"

-- STATE
local myBNP = nil
local hosts = {}
local hostServerBNP = nil
local connectedTowerBNP = nil
local towerSignal = math.huge -- lower = stronger (closer)
local TOWER_TIMEOUT = 30
local lastTowerContact = os.clock()
local oldTower = ""

-- UTILITIES
local function makeUID()
    seq = seq + 1
    return tostring(seq) .. "-" .. tostring(os.getComputerID())
end

local function saveBNP()
    local f = fs.open(BNP_FILE,"w") f.writeLine(myBNP or "") f.close()
end
local function loadBNP()
    if fs.exists(BNP_FILE) then
        local f = fs.open(BNP_FILE,"r")
        myBNP = f.readLine()
        f.close()
        if myBNP == "" then myBNP = nil end
    end
end
loadBNP()

local function saveHosts()
    local f = fs.open(HOSTS_FILE, "w")
    f.writeLine(textutils.serialize(hosts))
    f.close()
end
local function loadHosts()
    if fs.exists(HOSTS_FILE) then
        local f = fs.open(HOSTS_FILE, "r")
        local data = f.readAll()
        f.close()
        local ok, t = pcall(textutils.unserialize, data)
        if ok and type(t) == "table" then hosts = t else hosts = {} end
    else
        -- create empty hosts file
        local f = fs.open(HOSTS_FILE, "w")
        f.writeLine(textutils.serialize({}))
        f.close()
        hosts = {}
    end
end
loadHosts()

local function saveServerBNP()
    local f = fs.open(SERVER_FILE, "w")
    f.writeLine(hostServerBNP or "")
    f.close()
end
local function loadServerBNP()
    if fs.exists(SERVER_FILE) then
        local f = fs.open(SERVER_FILE, "r")
        hostServerBNP = f.readLine()
        f.close()
        if hostServerBNP == "" then hostServerBNP = nil end
    end
end
loadServerBNP()

local function saveTowerBNP()
    local f = fs.open(CONNECTED_TOWER_FILE,"w")
    f.writeLine(connectedTowerBNP or "")
    f.close()
end
local function loadTowerBNP()
    if fs.exists(CONNECTED_TOWER_FILE) then
        local f = fs.open(CONNECTED_TOWER_FILE,"r")
        connectedTowerBNP = f.readLine()
        f.close()
        if connectedTowerBNP == "" then connectedTowerBNP = nil end
    end
end
loadTowerBNP()

-- ADDRESS RESOLUTION
local function resolveAddress(input)
    if not input then return nil end
    if hosts[input] and hosts[input].BNP then return hosts[input].BNP end
    return input
end

-- PACKET UTILITIES (multi-channel aware)
local function sendPacket(dst, payload)
    if not myBNP then
        print("Set your BNP with 'set BNP <BNP>' first.")
        return
    end
    local resolved = resolveAddress(dst)
    if not resolved then
        term.setTextColor(colors.red)
        print("Unknown destination: "..tostring(dst))
        term.setTextColor(colors.white)
        return
    end
    local packet = { uid = makeUID(), src = myBNP, dst = resolved, ttl = 8, payload = payload }
    -- ensure routerChannel is open
    openChannel(routerChannel)
    modem.transmit(routerChannel, PRIVATE_CHANNEL, packet)
    debugPrint("Transmitted packet to "..tostring(resolved).." via channel "..tostring(routerChannel))
end

local function broadcast(payload)
    if myBNP then
    	local packet = { uid = makeUID(), src = myBNP or "unknown", dst = "0", ttl = 8, payload = payload }
    	-- use public broadcast for discovery
    	modem.transmit(1, 1, packet)
    	debugPrint("Broadcasted on public channel 1, payload: "..tostring(payload.type or "<unknown>"))
    else
        print("Set your BNP with 'set BNP <BNP>' first.")
    end
   	
end

-- SMART TOWER DISCOVERY (wireless-specific)
local function discoverTowers()
    debugPrint("Scanning for nearby cell towers...")
    broadcast({ type="HELLO_REQUEST" })
end

local function selectBestTower(src, distance, towerChannel)
    if oldTower == nil or oltTower == "" then
        oldTower = connectedTowerBNP
    end
    if type(src) ~= "string" then return end
    if not src:match("^10%.10%.10%.") then
        debugPrint("Ignoring non-tower BNP: " .. tostring(src))
        return
    end
    if distance < towerSignal then
        towerSignal = distance
        connectedTowerBNP = src
        lastTowerContact = os.clock()
        -- If tower supplied its private/router channel, adopt it
        if type(towerChannel) == "number" then
            routerChannel = towerChannel
            openChannel(routerChannel)
        end
        saveTowerBNP()
        debugPrint(("Connected to tower %s (signal %.1f blocks) on channel %s"):format(src, distance, tostring(routerChannel)))
    end
    if oldTower == connectedTowerBNP then
        debugPrint("Connected to tower "..tostring(connectedTowerBNP).." (signal "..string.format("%.1f", distance)..")")
    elseif oldTower ~= connectedTowerBNP then
        print("Connected to new tower "..tostring(connectedTowerBNP).." (signal "..string.format("%.1f", distance)..")")
    end
end

local function checkTowerTimeout()
    if connectedTowerBNP and os.clock() - lastTowerContact > TOWER_TIMEOUT then
        oldTower = connectedTowerBNP
        connectedTowerBNP = nil
        towerSignal = math.huge
        discoverTowers()
        os.sleep(1)
        if connectedTowerBNP == nil then
        	print("Lost connection to Network all BNP functionality disabled")
        elseif oldTower == connectedTowerBNP then
            debugPrint("Connected to tower "..tostring(connectedTowerBNP).." (signal "..string.format("%.1f", towerSignal)..")")
        elseif oldTower ~= connectedTowerBNP then
        	print("Connected to new tower "..tostring(connectedTowerBNP).." (signal "..string.format("%.1f", towerSignal)..")")
        end
    end
end

-- FILE TRANSFER STATE
local receivingFile = false
local fileBuffer = {}
local expectedChunks = 0
local fileNameBeingReceived = ""
local requestedFile = ""

-- FILE TRANSFER HELPERS
local function requestFile(dst, filename)
    print("Requesting file '" .. filename .. "' from " .. tostring(dst) .. " (" .. tostring(resolveAddress(dst)) ..")")
    sendPacket(dst, { type = "FILE_REQUEST", filename = filename })
end

local function sendACK(serverKeyword, password)
    local dst = resolveAddress(serverKeyword)
    if not dst then
        print("Nil value for address, try again")
        print("You entered: " .. tostring(serverKeyword) .. " translated to " .. tostring(dst))
        return
    end
    if not dst:match("^%d+%.%d+%.%d+%.%d+$") then
        print("Unknown server keyword "..tostring(serverKeyword))
        return
    else
        term.setTextColor(colors.blue)
        print("Establishing Connection to " .. tostring(serverKeyword) .. " (" .. tostring(dst) .. ") if no response within 60s assume no connection")
        term.setTextColor(colors.white)
        sendPacket(dst, { type = "ACK_START", password = password })
    end
end

-- HOST SYNC HANDLERS
local function handleUpdateHosts(payload)
    if type(payload.hosts) == "table" then
        hosts = payload.hosts
        saveHosts()
        debugPrint("[HostSync] Full hosts list updated.")
        print("Hosts list updated ("..tostring(#hosts).." entries).")
    end
end

local function handleHostsDiff(payload)
    local diff = payload.diff
    if not diff then return end
    for _, name in ipairs(diff.removed or {}) do hosts[name] = nil end
    for name, info in pairs(diff.added or {}) do hosts[name] = info end
    for name, info in pairs(diff.updated or {}) do hosts[name] = info end
    saveHosts()
    debugPrint("[HostSync] Hosts diff applied.")
    print("Hosts diff applied.")
end

local function discoverHostServer()
    debugPrint("[HostSync] Discovering host server...")
    broadcast({ type = "DISCOVER_HOST_SERVER" })
end

local function requestFullHosts()
    if hostServerBNP then
        debugPrint("[HostSync] Requesting full host table from " .. tostring(hostServerBNP))
        sendPacket(hostServerBNP, { type = "REQUEST_HOSTS" })
    else
        discoverHostServer()
    end
end

-- HELLO reply (respond to router/tower discovery)
local function replyHello(requester, requesterPrivate)
    if not myBNP then return end
    local payload = { type = "HELLO_REPLY", private_channel = PRIVATE_CHANNEL }
    -- If we are wireless and have connected tower, include that info? leave standard
    sendPacket(requester, payload)
    debugPrint("Replied to HELLO_REQUEST from "..tostring(requester))
end

-- RECEIVE LOOP (correct event unpacking)
local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        -- message should be packet table
        if type(message) ~= "table" or type(message.payload) ~= "table" then
            debugPrint("Received non-packet or malformed message.")
        else
            local payload = message.payload
            -- Only accept if destined to us, or broadcast "0"
            if message.dst == myBNP or message.dst == "0" then
                -- Track tower contact if message came with distance and from a tower-like BNP
                if distance and type(distance) == "number" then
                    -- treat messages from 10.10.10.x as towers for contact updates
                    if type(message.src) == "string" and message.src:match("^10%.10%.10%.") then
                        lastTowerContact = os.clock()
                    end
                end

                -- Handle payload types
                if payload.type == "HELLO_REQUEST" then
                    -- Tower/router discovery: accept their private channel if included
                    if payload.private_channel and type(payload.private_channel) == "number" then
                        -- learn router channel if default
                        if routerChannel == 1 then
                            routerChannel = payload.private_channel
                            openChannel(routerChannel)
                            debugPrint("Learned router channel from HELLO_REQUEST: " .. tostring(routerChannel))
                        end
                    end
                    -- reply with our private info
                    replyHello(message.src, payload.private_channel)
                elseif payload.type == "HELLO_REPLY" then
                    -- Tower reply should include its private channel optionally
                    local towerChan = payload.private_channel
                    selectBestTower(message.src, distance or math.huge, towerChan)
                elseif payload.type == "FILE_CHUNK" then
                    if not receivingFile then
                        receivingFile = true
                        fileBuffer = {}
                        expectedChunks = payload.total or 1
                        fileNameBeingReceived = payload.filename or ("unknown_"..makeUID())
                        print("Receiving file "..fileNameBeingReceived.." ("..tostring(expectedChunks).." chunks)")
                    end
                    fileBuffer[payload.seq] = payload.data
                    if payload.seq % 5 == 0 or payload.seq == expectedChunks then
                        print("Received chunk "..tostring(payload.seq).."/"..tostring(expectedChunks))
                    end
                elseif payload.type == "FILE_END" then
                    local tbl = {}
                    for i=1,(expectedChunks or #fileBuffer) do
                        table.insert(tbl, fileBuffer[i] or "")
                    end
                    local data = table.concat(tbl)
                    local out = fs.open(fileNameBeingReceived, "w")
                    if out then
                        out.write(data) out.close()
                        print("File '"..fileNameBeingReceived.."' saved successfully.")
                    else
                        term.setTextColor(colors.red)
                        print("Failed to write file: "..tostring(fileNameBeingReceived))
                        term.setTextColor(colors.white)
                    end
                    receivingFile, fileBuffer, expectedChunks, fileNameBeingReceived, requestedFile = false, {}, 0, "", ""
                elseif payload.type == "ERROR" then
                    term.setTextColor(colors.red)
                    print("Packet Error: "..(payload.message or "Unknown"))
                    term.setTextColor(colors.white)
                elseif payload.type == "ACK" then
                    term.setTextColor(colors.blue)
                    print("ACK received, starting FTP")
                    term.setTextColor(colors.white)
                    if requestedFile and requestedFile ~= "" then
                        requestFile(message.src, requestedFile)
                    else
                        term.setTextColor(colors.red)
                        print("ACK received but no requestedFile set.")
                        term.setTextColor(colors.white)
                    end
                elseif payload.type == "PING" then
                    sendPacket(message.src,{ type="PING_REPLY", message="pong" })
                elseif payload.type == "PING_REPLY" then
                    print("Reply from "..tostring(message.src)..": "..tostring(payload.message or "pong"))
                elseif payload.type == "UPDATE_HOSTS" then
                    handleUpdateHosts(payload)
                elseif payload.type == "HOSTS_DIFF" then
                    handleHostsDiff(payload)
                elseif payload.type == "HOST_SERVER_HERE" then
                    if payload.server_ip then
                        hostServerBNP = payload.server_ip
                        saveServerBNP()
                        debugPrint("[HostSync] Host server discovered at " .. tostring(hostServerBNP))
                        requestFullHosts()
                    end
                elseif payload.type == "DISCOVER_HOST_SERVER" then
                    -- If we are a client we should not act as host server; ignore unless we want to become one
                    -- But reply with HOST_SERVER_HERE if we are the server (not a client). Left as no-op.
                    debugPrint("DISCOVER_HOST_SERVER received.")
                else
                    debugPrint("Unhandled packet payload: "..textutils.serialize(payload))
                end
            else
                debugPrint("Packet not for us ("..tostring(message.dst).."), ignoring.")
            end
        end
    end
end

-- CLI
local colorsList = { colors.cyan, colors.yellow, colors.green, colors.magenta }

local function printCommands()
    local cmds = {
        "set BNP <BNP>",
        "ping <host/BNP>",
        "getfile <server> <filename> <password>",
        "list hosts",
        "sync hosts",
        "tower",
        "BNP",
        "exit",
        "debugmode <true|false>"
    }
    print("Wireless Client v1.8 Ready. Commands:")
    for i, cmd in ipairs(cmds) do
        term.setTextColor(colorsList[(i-1) % #colorsList + 1])
        print("  "..cmd)
    end
    term.setTextColor(colors.white)
end

local function cliLoop()
    printCommands()
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args, word) end
        local cmd = args[1]
        if cmd == "exit" then return
        elseif cmd == "set" and args[2] == "BNP" and args[3] then
            myBNP = args[3]; saveBNP(); print("BNP set to "..tostring(myBNP))
        elseif cmd == "ping" and args[2] then
            if connectedTowerBNP then
                sendPacket(args[2], { type = "PING" })
                print("Ping sent via tower "..tostring(connectedTowerBNP))
            else
                print("No connected tower. Use 'tower' to scan.")
            end
        elseif cmd == "list" and args[2] == "hosts" then
            print("Known hosts:")
            for k,v in pairs(hosts) do
                print(("  %-12s -> %s"):format(k, v.BNP or "??"))
            end
        elseif cmd == "sync" and args[2] == "hosts" then
            requestFullHosts()
        elseif cmd == "getfile" and args[2] and args[3] and args[4] then
            sendACK(args[2], args[4])
            requestedFile = args[3]
        elseif cmd == "BNP" then
            print("Current BNP: "..tostring(myBNP))
        elseif cmd == "tower" then
            discoverTowers()
        elseif cmd == "debugmode" and args[2] then
            if args[2] == "false" then DEBUG = false; print("Debug mode OFF")
            elseif args[2] == "true" then DEBUG = true; print("Debug mode ON")
            else
                term.setTextColor(colors.red)
                print("Error: Unrecognized argument | usage: debugmode true || debugmode false")
                term.setTextColor(colors.white)
            end
        else
            term.setTextColor(colors.red)
            print("Error: Unrecognized command")
            term.setTextColor(colors.white)
            printCommands()
        end
    end
end

-- STARTUP BEHAVIOR
-- If we have no host server BNP, try to discover it (goes over public/tower)
if not hostServerBNP then
    discoverHostServer()
else
    requestFullHosts()
end

-- Background maintenance thread (tower timeout check)
local function maintLoop()
    while true do
        checkTowerTimeout()
        os.sleep(5)
    end
end

local function cleanupChannels()
    while true do
		if modem and type(modem.getChannels) == "function" then
            local open = modem.getChannels()
        	for _, ch in ipairs(open) do
            	if ch ~= 1 and ch ~= PRIVATE_CHANNEL and ch ~= routerChannel then
                	modem.close(ch)
                	debugPrint("Auto-closed stale channel " .. ch)
            	end
        	end
		end
        os.sleep(TOWER_TIMEOUT*2)
    end
end

-- autostart setup
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'wirelessClient.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('wirelessClient.lua')")
        f.close()
    end
end

-- Run receiver, maint, CLI
ensureStartup()

local function crashDebug(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        printError("[CRASH in " .. name .. "] " .. tostring(err))
        os.sleep(30)
    end
end

parallel.waitForAny(
    function() crashDebug("receiveLoop", receiveLoop) end,
    function() crashDebug("maintLoop", maintLoop) end,
    function() crashDebug("cliLoop", cliLoop) end,
    function() crashDebug("cleanupChannels", cleanupChannels) end
)
