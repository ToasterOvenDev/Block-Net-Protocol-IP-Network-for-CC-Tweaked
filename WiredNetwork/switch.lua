-- switch.lua Version 2.0
-- Optimized Switch with S_H Discovery
-- Minimal forwarding device that doesn't process many packets (AKA only S_H)

-- SELF-LAUNCH IN MULTISHELL (Forge-safe)
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

local version = "2.0"
local PRIVATE_CHANNEL = os.getComputerID()
local ROUTE_FILE = "routing_table.txt"
local interfaces = {}
local routing_table = {}
local last_hello = {}

-- Utilities
local seq = 0
local function makeUID()
    seq = seq + 1
    return tostring(seq) .. "-" .. tostring(os.getComputerID())
end
local function log(msg)
    print("[SW:" .. PRIVATE_CHANNEL.. "] " .. msg)
end

local function saveRoutingTable()
    local f = fs.open(ROUTE_FILE, "w")
    if f then
        f.write(textutils.serialize(routing_table))
        f.close()
    end
end

local function loadRoutingTable()
    if fs.exists(ROUTE_FILE) then
        local f = fs.open(ROUTE_FILE, "r")
        local ok, data = pcall(textutils.unserialize, f.readAll())
		if ok and type(data) == "table" then
    		routing_table = data
		else
    		routing_table = {}
    		log("Routing table invalid, resetting.")
		end
        f.close()
        log("Loaded routing table.")
    else
        log("Routing table not found, starting fresh.")
    end
end

-- Modem Management 
local function openInterfaces()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            local m = peripheral.wrap(side)
            if m then
                m.open(1)               -- broadcast
                m.open(PRIVATE_CHANNEL)  -- private channel
                interfaces[side] = m
                log("Active interface: " .. side)
            end
        end
    end
end

-- Packet Forwarding 
local function forwardPacket(side, packet)
    local src = packet.src
    local dst = packet.dst
    
    -- Broadcast handling
    if dst == "0" then
        for s, m in pairs(interfaces) do
            if s ~= side then
                m.transmit(1, PRIVATE_CHANNEL, packet)
            end
        end
        log("Broadcast packet from " .. tostring(src))
        return
    end

    -- Normal forwarding
    local entry = routing_table[dst]
    if entry and interfaces[entry.side] then
        interfaces[entry.side].transmit(entry.channel, PRIVATE_CHANNEL, packet)
    else
        -- Default route fallback
        local def = routing_table["default"]
        if def and def.side and def.channel and interfaces[def.side] then
            interfaces[def.side].transmit(def.channel, PRIVATE_CHANNEL, packet)
            log("Forwarded to default route (" .. def.side .. ") for " .. tostring(dst))
        else
            log("No valid route, dropping packet.")
        end
    end
end

-- Switch Hello (S_H)
local function sendSwitchHello(side, target_channel, include_routes)
    local payload = {
        type = "S_H",
        switch = true,
        private_channel = PRIVATE_CHANNEL
    }
    if include_routes then
        local ip_list = {}
        for BNP, _ in pairs(routing_table) do
            if BNP ~= "default" then table.insert(ip_list, BNP) end
        end
        payload.routes = ip_list  -- only send BNPs
    end
	local packet = {
        uid = makeUID(),
        src = tostring(PRIVATE_CHANNEL),
        dst = "0",
        ttl = 8,
        payload = payload
    }
    if side and target_channel then
        if interfaces[side] then
        	interfaces[side].transmit(target_channel, PRIVATE_CHANNEL, packet)
        	log("Sent S_H to switch on side " .. side)
        else
            term.setTextColor(colors.yellow)
            log("Warning: Modem not on side: " .. tostring(side))
            term.setTextColor(colors.white)
        end
    else
        for s, m in pairs(interfaces) do
            m.transmit(1, PRIVATE_CHANNEL, packet)
        end
        log("Broadcast S_H on all interfaces")
    end
end

local function handleSwitchHello(side, packet)
    local payload = packet.payload
    if not packet.src or not payload.private_channel then log("S_H malformed dropping...") return end
	if os.clock() - (last_hello[packet.src] or 0) < 2 then log("seen before dropping...") return end
	last_hello[packet.src] = os.clock()
    if payload.switch then
        -- Switch detected
        routing_table[packet.src] = { side = side, channel = payload.private_channel }
        log("Discovered switch " .. packet.src .. " on side " .. side)

        -- If remote switch included routes, add BNPs to routing_table
        if payload.routes then
            for _, BNP in ipairs(payload.routes) do
                if not routing_table[BNP] and BNP:match("^%d+%.%d+%.%d+%.%d+") then
                    routing_table[BNP] = { side = side, channel = payload.private_channel }
                end
            end
            log("Updated routes from switch " .. packet.src)
        end

        saveRoutingTable()
        -- Respond with own routing table (only BNPs)
        sendSwitchHello(side, payload.private_channel, true)
    else
        -- Host response: learn BNP
        if packet.src then
            routing_table[packet.src] = { side = side, channel = payload.private_channel }
            log("Learned host " .. packet.src .. " on side " .. side)
            saveRoutingTable()
        end
    end
end

-- === Commands ===
local function showRoutingTable()
    log("Routing Table:")
    for BNP, data in pairs(routing_table) do
        if type(data) == "table" then
            print(("  %s -> side=%s ch=%s"):format(BNP, tostring(data.side), tostring(data.channel)))
        else
            print(("  %s -> [INVALID ENTRY: %s]"):format(BNP, tostring(data)))
        end
    end
end

local function clearRoutingTable()
    routing_table = {}
	last_hello = {}
    saveRoutingTable()
    log("Routing table cleared.")
end

local function CLI()
    while true do
        io.write("(Switch)> ")
        local line = io.read()
        if not line then break end

        local args = {}
        for word in line:gmatch("%S+") do table.insert(args, word) end
        local cmd = args[1]
        local arg2 = args[2]
        if cmd == "discover" then
            sendSwitchHello()
        elseif cmd == "show" then
            showRoutingTable()
        elseif cmd == "clear" then
            clearRoutingTable()
        elseif cmd == "default" and arg2 == "route" and args[3] and args[4] then
            local side = args[3]
            local channel = tonumber(args[4])
            if side and interfaces[side] then
                routing_table["default"] = { side = side, channel = channel or 1 }
				saveRoutingTable()
				log("Default route set to " .. side .. " with channel: " .. channel)
            else
                print("Invalid side: " .. tostring(side))
            end
        else
            log("Unknown command: " .. cmd)
        end
    end
end

local function clearLastSeen()
	last_hello = {}
end

-- === Main Loop ===
local function Listener()
        while true do
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if type(message) == "table" then
                if message.payload.type == "S_H" then
                    handleSwitchHello(side, message)
                elseif message.dst and message.src then
                    forwardPacket(side, message)
                end
            end
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
    if not startupContent:match("shell%.run%(\'switch.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('switch.lua')")
        f.close()
    end
end

ensureStartup()

-- === Startup ===
log("Initializing switch version " .. version)
clearLastSeen()
openInterfaces()
loadRoutingTable()
sendSwitchHello()
log("Switch ready. Type 'discover' to rescan and 'default route <side> <channel>' to set default route. Routing table commands 'show' table and 'clear' table ")
parallel.waitForAny(Listener,CLI)
