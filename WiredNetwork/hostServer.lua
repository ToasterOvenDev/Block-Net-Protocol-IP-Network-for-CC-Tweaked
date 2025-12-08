-- hostServer.lua Version 1.2
-- Central host registry server that distributes hosts.txt via diff updates
-- Sends full update on boot and diffs every change; periodic broadcast every 10 minutes
-- compatible with multi-channel system
-- compatible with switch 2.0 discovery system

-- SELF-LAUNCH IN MULTISHELL
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

 -- DEBUG MODE
local DEBUG = false
local function debugPrint(msg)
    if DEBUG then print("[DEBUG] " .. msg) end
end

-- CONFIG

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

local HOSTS_MASTER_FILE = "hosts_master.txt" -- persisted master table
local BROADCAST_INTERVAL = 600 -- 10 minutes in seconds
local serverBNPFile = "BNP.txt"
local serverBNP
local routerChannel = 1

-- load or create BNP
if not fs.exists(serverBNPFile) then
    local f = fs.open(serverBNPFile,"w")
    f.writeLine("")
    f.close()
    serverBNP = nil
else
    local f = fs.open(serverBNPFile,"r")
    serverBNP = f.readLine()
    f.close()
    if serverBNP == "" then serverBNP = nil end
end

-- ==========================
-- MASTER HOST TABLE
-- structure:
-- hosts = {
--   ["name"] = { BNP = "10.10.10.2", flags = {"router","game"} },
--   ...
-- }
-- ==========================
local hosts = {}

-- load master file
local function loadMaster()
    hosts = {}
    if fs.exists(HOSTS_MASTER_FILE) then
        local f = fs.open(HOSTS_MASTER_FILE,"r")
        local data = f.readAll()
        f.close()
        if data and data ~= "" then
            local ok, t = pcall(textutils.unserialize, data)
            if ok and type(t) == "table" then hosts = t end
        end
    end
end
loadMaster()

local function saveMaster()
    local f = fs.open(HOSTS_MASTER_FILE,"w")
    f.writeLine(textutils.serialize(hosts))
    f.close()
end

-- create diff between oldHosts and newHosts
local function makeDiff(oldHosts, newHosts)
    local diff = { added = {}, removed = {}, updated = {} }
    -- removed
    for k, v in pairs(oldHosts) do
        if not newHosts[k] then table.insert(diff.removed, k) end
    end
    -- added/updated
    for k, v in pairs(newHosts) do
        if not oldHosts[k] then
            diff.added[k] = v
        else
            -- compare BNP and flags
            local old = oldHosts[k]
            local changed = false
            if old.BNP ~= v.BNP then changed = true end
            -- flags compare
            local of = old.flags or {}
            local nf = v.flags or {}
            if #of ~= #nf then changed = true
            else
                for i=1,#of do if of[i] ~= nf[i] then changed = true; break end end
            end
            if changed then diff.updated[k] = v end
        end
    end
    return diff
end

-- NETWORK HELPERS
local seq = 0
local function makeUID()
    seq = seq + 1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

local function broadcastAll(payload)
    local packet = { uid = makeUID(), src = serverBNP or "0", dst = "0", ttl = 8, payload = payload }
    modem.transmit(1,1,packet)
end

local function sendDirect(dst, payload)
    local packet = { uid = makeUID(), src = serverBNP or "0", dst = dst, ttl = 8, payload = payload }
    modem.transmit(routerChannel, PRIVATE_CHANNEL, packet)
end

-- HANDLERS

local function replyHello(requester)
    if not serverBNP then return end
    sendDirect(requester, { type="HELLO_REPLY", private_channel = PRIVATE_CHANNEL })
    debugPrint("Replied to HELLO_REQUEST from "..requester)
end

local function replySwitch(side, packet)
    local payload = packet.payload
    -- Only respond if this is a switch hello from a switch
    if not payload.switch then return end
    -- Make sure the client has an BNP
    if not serverBNP then
        debugPrint("Received S_H from switch but server BNP is not set, ignoring.")
        return
    end
    -- Respond to switch with our BNP and private channel
    local response = {
        type = "S_H",
        switch = false,          -- client, not a switch
        src_ip = serverBNP,
        private_channel = PRIVATE_CHANNEL -- or whatever channel we learned from HELLO
    }
	routerChannel = payload.private_channel --Will ALWAYS override the router channel to account for network expansion
    -- Send back to the switch using the port we received from
    sendDirect(packet.src, response)
    debugPrint("Responded to S_H from switch " .. tostring(packet.src) .. " with BNP " .. serverBNP)
end
-- On boot broadcast full hosts
local function broadcastFullHosts()
    -- send full table in UPDATE_HOSTS
    local payload = { type = "UPDATE_HOSTS", hosts = hosts }
    broadcastAll(payload)
    print("Broadcasted full hosts to network (boot).")
end

-- send diff to network
local function broadcastDiff(diff)
    if (diff and ((diff.added and next(diff.added)) or (diff.removed and #diff.removed>0) or (diff.updated and next(diff.updated)))) then
        local payload = { type = "HOSTS_DIFF", diff = diff }
        broadcastAll(payload)
        print("Broadcasted hosts diff to network.")
    end
end

-- respond to requesters of full hosts
local function handleRequestHosts(src)
    sendDirect(src, { type = "UPDATE_HOSTS", hosts = hosts })
    print("Sent full hosts to "..src)
end

-- PACKET RECEIVE LOOP
local function receiveLoop()
    while true do
        local e, side, ch, reply, message, dist = os.pullEvent("modem_message")
        if type(message) == "table" then
            local payload = message.payload
            if type(payload) ~= "table" then
                print("Invalid payload from "..tostring(message.src))
            else
                if payload.type == "DISCOVER_HOST_SERVER" then
                    -- reply to discovery: HOST_SERVER_HERE
                    local server_ip = serverBNP or (hosts and (next(hosts) and (hosts[next(hosts)].BNP) or nil) )
                    if server_ip then
                        sendDirect(message.src, { type = "HOST_SERVER_HERE", server_ip = server_ip, private_channel = PRIVATE_CHANNEL })
                        print("Replied HOST_SERVER_HERE to "..message.src)
                    end
                elseif payload.type == "REQUEST_HOSTS" then
                    -- direct request for full data
                    handleRequestHosts(message.src)
                elseif payload.type == "HELLO_REQUEST" then
                if routerChannel == 1 or routerChannel == nil then --Makes sure that a switch isn't in between ruter and device
                    if payload.private_channel and type(payload.private_channel) == "number" then
                    	routerChannel = payload.private_channel
                    	debugPrint("Learned router channel: " .. routerChannel)
                	end
                end
                replyHello(message.src)
                elseif payload.type == "S_H" then --Switch hello packet for switch discovery
					replySwitch(modemSide, message)
                else
                    -- ignore other types
                end
            end
        end
    end
end

-- ==========================
-- CLI for management
-- ==========================
local function printHelp()
    print([[HostServer Commands:
  addhost <name> <BNP> [flags...]
  delhost <name>
  listhosts
  broadcast
  BNP
  setip <BNP>
  exit
  help
  debugmode
]])
end

local function cliLoop()
    print("HostServer ready. Type 'help' for commands.")
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local cmd, rest = line:match("^(%S+)%s*(.*)$")
        if not cmd then cmd = line end
        if cmd == "help" then printHelp()
        elseif cmd == "exit" then return
        elseif cmd == "listhosts" then
            for name, info in pairs(hosts) do
                print(name.." -> "..info.BNP.." flags: "..table.concat(info.flags or {}, ","))
            end
        elseif cmd == "addhost" then
            -- parse: addhost name BNP [flags...]
            local name, BNP, flagsStr = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
            if not name or not BNP then print("Usage: addhost <name> <BNP> [flags...]")
            else
                local flags = {}
                if flagsStr and flagsStr ~= "" then
                    for f in flagsStr:gmatch("%S+") do table.insert(flags, f) end
                end
                local oldHosts = {}
                for k,v in pairs(hosts) do oldHosts[k] = { BNP = v.BNP, flags = { table.unpack(v.flags or {}) } } end
                hosts[name] = { BNP = BNP, flags = flags }
                saveMaster()
                local diff = makeDiff(oldHosts, hosts)
                broadcastDiff(diff)
                print("Added host "..name)
            end
        elseif cmd == "delhost" then
            local name = rest:match("^(%S+)$")
            if not name then print("Usage: delhost <name>")
            else
                if hosts[name] then
                    local oldHosts = {}
                    for k,v in pairs(hosts) do oldHosts[k] = { BNP = v.BNP, flags = { table.unpack(v.flags or {}) } } end
                    hosts[name] = nil
                    saveMaster()
                    local diff = makeDiff(oldHosts, hosts)
                    broadcastDiff(diff)
                    print("Deleted host "..name)
                else print("No such host: "..name) end
            end
        elseif cmd == "broadcast" then
            broadcastFullHosts()
        elseif cmd == "setip" then
            local BNP = rest:match("^(%S+)")
            if BNP then
                serverBNP = BNP
                local f = fs.open(serverBNPFile,"w")
                f.writeLine(serverBNP)
                f.close()
                print("Server BNP set to "..serverBNP)
            else print("Usage: setip <BNP>") end
        elseif cmd == "BNP" then
            print("Server BNP: "..tostring(serverBNP))
        elseif cmd == "debugmode" then
           	local tf = rest:match("^(%S+)")
            if tf == "true" then
                DEBUG = true
                print("Debug mode enabled")
            elseif tf == "false" then
                DEBUG = false
                print("Debug mode disabled")
            else
                print("unrecognized, 'true' or 'false'.")
            end
        else
            print("Unknown command. Type 'help'.")
        end
    end
end

-- ==========================
-- BROADCASTER (periodic)
-- ==========================
local function periodicBroadcast()
    -- On boot send full
    broadcastFullHosts()
    -- then loop
    while true do
        os.sleep(BROADCAST_INTERVAL)
        -- send small heartbeat broadcast asking for routers to request diffs? We'll send a light full ping
        broadcastFullHosts()
    end
end

-- ==========================
-- START SERVER
-- ==========================

-- autostart setup
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'hostServer.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('hostServer.lua')")
        f.close()
    end
end

ensureStartup()

parallel.waitForAny(receiveLoop, cliLoop, periodicBroadcast)
