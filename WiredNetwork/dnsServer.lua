-- dnsServer.lua Version 2.0 (previously known as hostServer)
-- Central host registry server that distributes hosts.txt via diff updates
-- Sends full update on boot and diffs every change
-- Can connect to a 'Master DNS Server' who will contain an entire networks host mappings 
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
    if DEBUG and fileOnly then
        local f = fs.open(debugFile,"a")
        f.writeLine("[DEBUG "..time.."] " .. msg)
        f.close()
    elseif DEBUG then
        local f = fs.open(debugFile,"a")
        f.writeLine("[DEBUG "..time.."] " .. msg)
        f.close()
        print("[DEBUG] " .. msg)
    end
end
debugPrint("[BOOT] Debugging started",true)
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
local serverConfFile = "configsDNS.txt"
local serverConfigs = {serverBNP = nil, masterDNS = {}, master = false}
local BROADCAST_INTERVAL = 600 -- 10 minutes in seconds
local serverBNP
local routerChannel = 1
local master = false -- If this DNS server is a Master DNS Server
local masterStart = 0
local hostsMetaData = {}
local masterDNS = { BNP = nil, time = 0 }
local hosts = {}

-- load or create configuration file
if not fs.exists(serverConfFile) then
    local f = fs.open(serverConfFile,"w")
    f.writeLine("")
    f.close()
    serverBNP = nil
else
    local f = fs.open(serverConfFile,"r")
    local configs= textutils.unserialize(f.readAll())
    f.close()
    if configs == "" then
		serverBNP = nil
		masterDNS = { BNP = nil, time = 0 }
		master = false
        masterStart = 0
	else
		serverBNP = configs.serverBNP or nil
		masterDNS = configs.masterDNS or { BNP = nil, time = 0 }
		master = configs.master or false
        masterStart = configs.masterStart or 0
	end
end

local function saveConfigs()
	serverConfigs = { serverBNP = serverBNP, masterDNS = masterDNS, master = master, masterStart = masterStart }
	local f = fs.open(serverConfFile,"w")
	f.write(textutils.serialize(serverConfigs))
	f.close()
end

-- ==========================
-- MASTER HOST TABLE
-- structure:
-- hosts = {
--   ["name"] = { BNP = "10.10.10.2", flags = {"router","game"} },
--   ...
-- }
-- ==========================

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
    for k in pairs(oldHosts) do
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
	if not serverBNP then print("No BNP, cannot communicate with network") return end
    local packet = { uid = makeUID(), src = serverBNP, dst = "0", ttl = 64, payload = payload }
    modem.transmit(1,1,packet)
end

local function sendDirect(dst, payload)
    local packet = { uid = makeUID(), src = serverBNP or "0", dst = dst, ttl = 64, payload = payload }
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
        switch = false,          -- server, not a switch
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
    print("Broadcasted full hosts to network.")
end

-- send diff to network
local function broadcastDiff(diff)
    if (diff and ((diff.added and next(diff.added)) or (diff.removed and #diff.removed>0) or (diff.updated and next(diff.updated)))) then
        local payload = { type = "HOSTS_DIFF", diff = diff, master = master }
        broadcastAll(payload)
        print("Broadcasted hosts diff to network.")
		if masterDNS.BNP then
			payload.type = "HOST_DIFF_TO_MASTER" -- Extra type name to get around traffic routing
			sendDirect(masterDNS.BNP,payload)
		end
    end
end

-- respond to requesters of full hosts
local function handleRequestHosts(src)
    sendDirect(src, { type = "UPDATE_HOSTS", hosts = hosts })
    print("Sent full hosts to "..src)
end

local function handleHostsDiff(packet)
	local payload = packet.payload
    local diff = payload.diff
	if not master or packet.src ~= masterDNS.BNP or not diff then return end
    debugPrint("Diff received attempting to handle")

    for _, name in ipairs(diff.removed or {}) do
		if not master then
			hosts[name] = nil
		else
            debugPrint("Checking removal diff")
            if hostsMetaData[name] then -- Make sure that the Meta Data exists first
			    if hostsMetaData[name].orginalsrc == packet.src then
			    	hosts[name] = nil
                    debugPrint("Removing "..name)
			    end
            end
		end
	end
    for name, info in pairs(diff.added or {}) do
		if not master then
			hosts[name] = info
		else
            debugPrint("Checking addition diff")
			if not hosts[name] then -- Make sure you don't already have a mapping
				hosts[name] = info
				hostsMetaData[name] = { orginalsrc = packet.src, timeArrived = os.epoch() }
                debugPrint("Added "..name)
			end
		end
	end
    for name, info in pairs(diff.updated or {}) do
		if not master then
			hosts[name] = info
		else
            debugPrint("Checking update diff")
            if hostsMetaData[name] then
			    if hostsMetaData[name].orginalsrc == packet.src then
				    hosts[name] = info
                    debugPrint("Updating "..name) -- Perculator :3
			    end
            end
		end
	end
    saveMaster()
    debugPrint("Master diff applied.")
end

-- PACKET RECEIVE LOOP (Massa) :P
local function receiveLoop()
	while true do
		local _, _, _, _, message = os.pullEvent("modem_message")
		if type(message) == "table" then
			debugPrint(textutils.serialize(message), true)
			local payload = message.payload
			if type(payload) ~= "table" and serverBNP then
				print("Invalid payload from " .. message.src)
			else
				if payload.type == "DISCOVER_DNS_SERVER" then
					-- reply to discovery: DNS_SERVER_HERE
					local server_bnp = serverBNP
					if server_bnp then
						sendDirect(message.src,
							{ type = "DNS_SERVER_HERE", server_bnp = server_bnp, private_channel = PRIVATE_CHANNEL })
						print("Replied DNS_SERVER_HERE to " .. message.src)
					end
				elseif payload.type == "REQUEST_HOSTS" then
					-- direct request for full data
					if hosts then
						handleRequestHosts(message.src)
					end
				elseif payload.type == "HELLO_REQUEST" then
					if routerChannel == 1 or routerChannel == nil then --Makes sure that a switch isn't in between router and device
						if payload.private_channel and type(payload.private_channel) == "number" then
							routerChannel = payload.private_channel
							debugPrint("Learned router channel: " .. routerChannel)
						end
					end
					replyHello(message.src)
				elseif payload.type == "S_H" then --Switch hello packet for switch discovery
					replySwitch(modemSide, message)
                elseif payload.type == "PING" then
                    sendDirect(message.src, { type = "PING_REPLY", message = "DNS Server Here" })
				elseif payload.type == "MASTER_DNS_REQ" and master then
					sendDirect(message.src, { type = "MASTER_DNS_MAP", mappings = hosts, time = masterStart })
					debugPrint("Replied to Child DNS Request")
				elseif payload.type == "MASTER_DNS_MAP" then
                    debugPrint("Master Mappings recieved")
					if not master then
                        debugPrint("Handling as non-master DNS")
                        debugPrint("masterDNS = "..textutils.serialize(masterDNS))
                        debugPrint("payload.time = "..tostring(payload.time))
                        if masterDNS.time < payload.time or not masterDNS.BNP then -- Update your Master DNS if you don't have one or if the new one is older
                            print("New Master Found, updating host mappings according to new Master")
                            masterDNS = { BNP = message.src, time = payload.time }
							saveConfigs()
						end
                        if payload.mappings and message.src == masterDNS.BNP then
                            debugPrint("Got an update from Master DNS, applying update to hosts registry")
                            hosts = payload.mappings
                            saveMaster()
                        end
					else
                        debugPrint("Handling as master DNS")
						if payload.time > masterStart then
							master = false
							masterStart = 0
							masterDNS = { BNP = message.src, time = payload.time }
							print("No longer Master DNS, an older Master found")
							saveConfigs()
						end
					end -- Crash when child sends diff update
				elseif payload.type == "HOSTS_DIFF" or payload.type == "HOST_DIFF_TO_MASTER" or payload.type == "DNS_SVR_DIFF" then
					if master or message.src == masterDNS.BNP then
						local oldHosts = {}
						if master then
							oldHosts = hosts
						end
						handleHostsDiff(payload)
						if master then
							local diff = makeDiff(oldHosts, hosts)
							local relay = { type = "DNS_SVR_DIFF", diff = diff } -- Another different type name to get around traffic routing
							broadcastAll(relay)
							debugPrint("Relayed diff from a child DNS")
						end
					end
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
  setbnp <BNP>
  master <true,false>
  findMaster
  exit
  help
  debugmode
]])
end

local function cliLoop()
    print("DNS Server ready. Type 'help' for commands.")
    while true do
        io.write("> ")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args, word) end
        local cmd = args[1]
        if cmd == "help" then printHelp()
        elseif cmd == "exit" then return
        elseif cmd == "listhosts" then
            for name, info in pairs(hosts) do
                print(name.." -> "..info.BNP.." flags: "..table.concat(info.flags or {}, ","))
            end
        elseif cmd == "addhost" then
            -- parse: addhost name BNP [flags...]
            local name, BNP, flagsStr = args[2],args[3],args[4]
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
            local name = args[2]
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
		elseif cmd == "findMaster" then
			local payload = { type = "MASTER_DNS_REQ" }
			broadcastAll(payload)
        elseif cmd == "setbnp" then
            local BNP = args[2]
            if BNP then
				serverBNP = BNP
                saveConfigs()
				print("set BNP to "..BNP)
            else
				print("Usage: setbnp <BNP>")
			end
        elseif cmd == "BNP" then
            print("Server BNP: "..tostring(serverBNP))
        elseif cmd == "master" then
            local tf = args[2]
			if masterDNS.BNP then
				print("Master already known, cannot replace them")
            elseif tf == "true" then
                master = true
                print("Master mode enabled")
                masterStart = os.epoch()
            elseif tf == "false" then
                master = false
                masterStart = 0
                print("Master mode disabled")
            else
                print("unrecognized, 'true' or 'false'.")
            end
			saveConfigs()
        elseif cmd == "debugmode" then
           	local tf = args[2]
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
    while true do
        os.sleep(BROADCAST_INTERVAL)
        if not masterDNS.BNP and not master then
			local payload = { type = "MASTER_DNS_REQ" }
			broadcastAll(payload)
		end
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
    if not startupContent:match("shell%.run%(\'dnsServer.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('dnsServer.lua')")
        f.close()
    end
end

ensureStartup()
-- On boot send full
broadcastFullHosts()

if masterDNS.BNP then
	parallel.waitForAny(receiveLoop, cliLoop)
else
	parallel.waitForAny(receiveLoop, cliLoop, periodicBroadcast)
end
