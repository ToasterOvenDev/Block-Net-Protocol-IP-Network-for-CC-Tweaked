-- cell_tower.lua v2.2 (Multi-channel support + NAT + automatic cleanup)
local VERSION = "2.2"
local DEBUG = false
local function dprint(msg) if DEBUG then print("[DEBUG] "..msg) end end

-- SELF-LAUNCH IN MULTISHELL
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

-- CONFIG
local TOWER_BNP_FILE = "BNP.txt"
local DEFAULT_TTL = 8
local HELLO_INTERVAL = 60
local NAT_TIMEOUT = 60  -- seconds before NAT entry expires
local PRIVATE_CHANNEL = os.getComputerID()

-- INTERFACES (support multiple modems but we expect exactly 1 wireless and 1 wired)
local sides = {"top","bottom","left","right","front","back"}
local wirelessSide, wiredSide
local interfaces = {}
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        interfaces[side] = m
        if m.isWireless() then wirelessSide = side else wiredSide = side end
    end
end
if not wirelessSide or not wiredSide then error("Need 1 wireless and 1 wired modem!") end

-- open discovery (1) + private channel
for s, m in pairs(interfaces) do
    pcall(function()
        m.open(1)
        m.open(PRIVATE_CHANNEL)
    end)
    dprint("Opened modem on "..s.." (channels 1 + "..tostring(PRIVATE_CHANNEL)..")")
end

local wireless = interfaces[wirelessSide]
local wired = interfaces[wiredSide]
print("Wireless: "..wirelessSide..", Wired: "..wiredSide)

-- LOAD OR CREATE TOWER BNP
local towerBNP
if fs.exists(TOWER_BNP_FILE) then
    local f = fs.open(TOWER_BNP_FILE,"r") towerBNP = f.readLine() f.close()
else
    towerBNP = "10.10.10."..os.getComputerID()
    local f = fs.open(TOWER_BNP_FILE,"w") f.writeLine(towerBNP) f.close()
    print("Assigned BNP: "..towerBNP)
end

-- STATE
local seq = 0
local function makeUID() seq = seq + 1; return tostring(seq) .. "-" .. tostring(os.getComputerID()) end
local seen = {}
local hosts = {}           -- learned hosts (BNP -> side name)
local lastSeen = {}
local natTable = {}        -- NAT: client BNP -> {originalDst, lastSeen}
local knownChannels = {}   -- BNP -> private_channel learned from HELLO_REPLY / S_H

-- HELPERS
local function learnHost(BNP, side)
    if not BNP or not side then return end
    hosts[BNP] = side
    lastSeen[BNP] = os.clock()
    dprint("Learned host "..BNP.." via "..side)
end

local function transmitToSide(side, packet)
    local m = interfaces[side]
    if not m then return end
    local dstCh = knownChannels[packet.dst] or 1
    m.transmit(dstCh, PRIVATE_CHANNEL, packet)
    dprint(("Transmitted to %s on ch %s (from private %s): %s"):format(side, tostring(dstCh), tostring(PRIVATE_CHANNEL), tostring(packet.uid)))
end

local function broadcastExcept(excludeSide, packet)
    for s, m in pairs(interfaces) do
        if s ~= excludeSide then transmitToSide(s, packet) end
    end
end

-- PACKET HANDLING
local function handlePacket(packet, incomingSide)
    if not packet or type(packet)~="table" or not packet.uid then return end
    if seen[packet.uid] then return end
    seen[packet.uid] = true
    packet.ttl = (packet.ttl or DEFAULT_TTL) - 1
    if packet.ttl <= 0 then return end

    -- learn host and last-seen
    learnHost(packet.src, incomingSide)

    local payload = packet.payload

    -- If payload table, process control messages first
    if type(payload)=="table" then
        if payload.type=="HELLO_REQUEST" then
            -- reply with HELLO_REPLY including our private channel
            local reply = { uid = makeUID(), src = towerBNP, dst = packet.src, ttl = DEFAULT_TTL, payload = { type = "HELLO_REPLY", private_channel = PRIVATE_CHANNEL } }
            -- reply using the sender's known channel if we have it, else broadcast on the incoming side
            transmitToSide(incomingSide, reply)
            dprint("Replied to HELLO_REQUEST from "..tostring(packet.src).." on side "..incomingSide)
            return
        elseif payload.type=="HELLO_REPLY" then
            -- learn the private channel of whoever replied (this helps for directed replies)
            if payload.private_channel then knownChannels[packet.src] = payload.private_channel; dprint("Learned private channel "..tostring(payload.private_channel).." for side "..incomingSide) end
            learnHost(packet.src, incomingSide)
            return
        elseif payload.type=="PING" then
            if packet.dst==towerBNP then
                local reply = { uid = makeUID(), src = towerBNP, dst = packet.src, ttl = DEFAULT_TTL, payload = { type = "PING_REPLY", message = "pong" } }
                transmitToSide(incomingSide, reply)
                dprint("Ping reply sent to "..packet.src)
                return
            end
        end
    end

    -- NAT forwarding
    -- If incoming is wireless -> forward to wired (rewrite src to towerBNP)
    if incomingSide == wirelessSide then
        -- record NAT mapping for this client
        natTable[packet.src] = { originalDst = packet.dst, lastSeen = os.clock() }
        local forwardPacket = { uid = makeUID(), src = towerBNP, dst = packet.dst, ttl = packet.ttl, payload = packet.payload }
        transmitToSide(wiredSide, forwardPacket)
        return
    end

    -- incoming from wired: try to map back to client
    if incomingSide == wiredSide then
        for clientBNP, info in pairs(natTable) do
            -- if the incoming packet looks like a reply from the external dest back to towerBNP, forward to client
            if packet.dst == towerBNP and packet.src == info.originalDst then
                local forwardPacket = { uid = makeUID(), src = packet.src, dst = clientBNP, ttl = packet.ttl, payload = packet.payload }
                transmitToSide(wirelessSide, forwardPacket)
                info.lastSeen = os.clock()
                return
            end
        end
    end

    -- default: if dst is broadcast -> forward to other side(s)
    if packet.dst == "0" then
        broadcastExcept(incomingSide, packet)
        return
    end

    -- if we know exact host mapping, send directly (avoid sending back to incoming side)
    local targetSide = hosts[packet.dst]
    if targetSide and interfaces[targetSide] then
        if targetSide ~= incomingSide then transmitToSide(targetSide, packet) end
        return
    end

    -- no mapping: forward to the other side as fallback
    if incomingSide == wirelessSide then transmitToSide(wiredSide, packet) else transmitToSide(wirelessSide, packet) end
end

-- CLEANUPS
local function natCleanup()
    while true do
        for clientBNP, info in pairs(natTable) do
            if os.clock() - info.lastSeen > NAT_TIMEOUT then
                dprint("Removing stale NAT entry for "..clientBNP)
                natTable[clientBNP] = nil
            end
        end
        os.sleep(5)
    end
end

local function seenCleanup()
    while true do
        seen = {}
        dprint("Cleared seen UID cache")
        os.sleep(300)
    end
end

local function channelCleanup()
    while true do
    	knownChannels = {} -- empties out knownChannels so that it doesn't eat up too much memory
        dprint("Cleared channels cache")
        os.sleep(HELLO_INTERVAL*10)
    end
end

-- PERIODIC HELLO
local function periodicHello()
    while true do
        local packet = { uid = makeUID(), src = towerBNP, dst = "0", ttl = DEFAULT_TTL, payload = { type = "HELLO_REQUEST", private_channel = PRIVATE_CHANNEL } }
        -- broadcast on all interfaces
        for s,_ in pairs(interfaces) do transmitToSide(s, packet) end
        os.sleep(HELLO_INTERVAL)
    end
end

-- LISTENER
local function listener()
    while true do
        local e, side, ch, reply, msg, dist = os.pullEvent("modem_message")
        if interfaces[side] and type(msg)=="table" and msg.uid then
            handlePacket(msg, side)
        end
    end
end
--print commands
local function help()
    local cmds = {
        "help",
        "show hosts",
        "show nat",
        "show channels",
      	"BNP",
        "exit"
    }
    print("Cell tower version " .. VERSION .. " commands: ")
    for i,cmd in ipairs(cmds) do
        print("    "..cmd)
    end
end
-- CLI
local function cli()
    help()
    while true do
        write("(tower "..towerBNP..")> ")
        local line = read()
        if not line then break end
        if line=="exit" then return
        elseif line=="help" then help()
        elseif line=="show hosts" then for h,s in pairs(hosts) do print(h.." -> "..s) end
        elseif line=="show nat" then for c,i in pairs(natTable) do print(c.." -> "..i.originalDst) end
        elseif line=="show channels" then for s,ch in pairs(knownChannels) do print(s.." -> "..tostring(ch)) end
        elseif line=="BNP" then print("Tower BNP: "..towerBNP)
        else print("Unknown command.") end
    end
end

-- AUTOSTART
local function ensureStartup()
    if not fs.exists("startup") then
        local f = fs.open("startup","w") f.writeLine("shell.run('cell_tower.lua')") f.close()
		print("Ensured startup")
	else
		print("Startup ensured already")
    end
end
ensureStartup()

print("Cell Tower v"..VERSION.." active at "..towerBNP)
parallel.waitForAny(listener, periodicHello, cli, natCleanup, seenCleanup, channelCleanup)
