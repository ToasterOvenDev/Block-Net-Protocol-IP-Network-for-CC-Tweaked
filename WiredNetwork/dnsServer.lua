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
debugPrint("[BOOT] Started logging",true)
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
	debugPrint("[DIFF] Making a Diff", true)
	debugPrint("[DIFF] Old Hosts: "..textutils.serialize(oldHosts),true)
	debugPrint("[DIFF] New Hosts: "..textutils.serialize(newHosts),true)
    local diff = { added = {}, removed = {}, updated = {} }
    -- removed
	debugPrint("[DIFF] Removed diff being made", true)
    for k in pairs(oldHosts) do
        if not newHosts[k] then table.insert(diff.removed, k) debugPrint("[DIFF] "..k.." was removed",true) end
    end
    -- added/updated
	debugPrint("[DIFF] Added and Updated diff being made", true)
    for k, v in pairs(newHosts) do
        if not oldHosts[k] then
            diff.added[k] = v
			debugPrint("[DIFF] "..k.." was added",true)
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
            if changed then diff.updated[k] = v debugPrint("[DIFF] "..k.." was updated",true) end
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
    debugPrint("[HELLO] Replied to HELLO_REQUEST from "..requester,true)
end

local function replySwitch(side, packet)
    local payload = packet.payload
    -- Only respond if this is a switch hello from a switch
    if not payload.switch then return end
    -- Make sure the client has an BNP
    if not serverBNP then
        debugPrint("[SWITCH] Received S_H from switch but server BNP is not set, ignoring.")
        return
    end
    -- Respond to switch with our BNP and private channel
    local response = {
        type = "S_H",
        switch = false,          -- server, not a switch
        src_ip = serverBNP,
        private_channel = PRIVATE_CHANNEL
    }
	routerChannel = payload.private_channel --Will ALWAYS override the router channel to account for network expansion
    -- Send back to the switch using the port we received from
    sendDirect(packet.src, response)
    debugPrint("[SWITCH] Responded to S_H from switch " .. tostring(packet.src) .. " with BNP " .. serverBNP)
end
-- Function to broadcast to children to replace their current hosts list
local function broadcastFullHosts(masterMap)
	masterMap = masterMap or false
    local payload
	-- send full table in UPDATE_HOSTS
	if masterMap and master then -- For the use case that a Master DNS has to send a non-requested DNS Map
		payload = { type = "DNS_MAP", mapping = hosts }
	else
		payload = { type = "UPDATE_HOSTS", hosts = hosts }
	end
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
	if not diff then debugPrint("[DIFF] Diff packet malformed dropping",true) return end -- drop the packet if diff is nil
	if not master then
		debugPrint("[DIFF] I am not a master checking if it comes from my master", true)
		if packet.src ~= masterDNS.BNP then debugPrint("[DIFF] Diff not from Master dropping",true) return end --Drop the packet if you are not the master or if it doesn't come from your master DNS
	end
    debugPrint("[DIFF] Diff received attempting to handle")

    for _, name in ipairs(diff.removed or {}) do
		if not master then
			hosts[name] = nil
		else
            debugPrint("[DIFF] Checking removal diff")
            if hostsMetaData[name] then -- Make sure that the Meta Data exists first
			    if hostsMetaData[name].orginalsrc == packet.src then
			    	hosts[name] = nil
                    debugPrint("[DIFF] Removing "..name)
			    end
            end
		end
	end
    for name, info in pairs(diff.added or {}) do
		if not master then
			hosts[name] = info
		else
            debugPrint("[DIFF] Checking addition diff")
			if not hosts[name] then -- Make sure you don't already have a mapping
				hosts[name] = info
				hostsMetaData[name] = { orginalsrc = packet.src, timeArrived = os.epoch() }
                debugPrint("[DIFF] Added "..name)
			end
		end
	end
    for name, info in pairs(diff.updated or {}) do
		if not master then
			hosts[name] = info
		else
            debugPrint("[DIFF] Checking update diff")
            if hostsMetaData[name] then
			    if hostsMetaData[name].orginalsrc == packet.src then
				    hosts[name] = info
                    debugPrint("[DIFF] Updating "..name)
			    end
            end
		end
	end
    saveMaster()
    debugPrint("[DIFF] Master diff applied.")
end

local hellos = 0 -- This is so master DNS servers can update child DNS every 5 hello packets received to avoid making a dedicated parrallel loop
-- PACKET RECEIVE LOOP
local function receiveLoop()
	while true do
		local _, _, _, _, message = os.pullEvent("modem_message")
		if type(message) == "table" then
			debugPrint("[PACKET] "..textutils.serialize(message), true)
			local payload = message.payload
			if type(payload) ~= "table" and serverBNP then
				print("Invalid payload from " .. message.src)
			else
				if payload.type == "DISCOVER_DNS_SERVER" then
					-- reply to discovery: DNS_SERVER_HERE
					local server_bnp = serverBNP
					if server_bnp then
						sendDirect(message.src, { type = "DNS_SERVER_HERE", server_bnp = server_bnp, private_channel = PRIVATE_CHANNEL })
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
							debugPrint("[HELLO] Learned router channel: " .. routerChannel)
						end
					end
					replyHello(message.src)
					if master then -- We want to make sure that all DNS servers have the same mapping as the Master so were gonna update child DNS every so often
						hellos = hellos + 1
						debugPrint("[MASTER_MAP] On Hello #"..tostring(hellos),true)
						if hellos == 5 then
							hellos = 0
							broadcastFullHosts(true)
						end
					end
				elseif payload.type == "S_H" then --Switch hello packet for switch discovery
					replySwitch(modemSide, message)
                elseif payload.type == "PING" then
                    sendDirect(message.src, { type = "PING_REPLY", message = "DNS Server Here" })
				elseif payload.type == "MASTER_DNS_REQ" and master then
					sendDirect(message.src, { type = "MASTER_DNS_MAP", mappings = hosts, time = masterStart })
					debugPrint("[MASTER_REQ] Replied to Child DNS Request")
				elseif payload.type == "MASTER_DNS_MAP" then
                    debugPrint("[MASTER_MAP] Master Mappings recieved")
					if not master then
                        debugPrint("[MASTER_MAP] Handling as non-master DNS")
                        debugPrint("[MASTER_MAP] masterDNS = "..textutils.serialize(masterDNS),true)
                        debugPrint("[MASTER_MAP] payload.time = "..tostring(payload.time),true)
                        if masterDNS.time < payload.time or not masterDNS.BNP then -- Update your Master DNS if you don't have one or if the new one is older
                            print("New Master Found, updating host mappings according to new Master")
                            masterDNS = { BNP = message.src, time = payload.time }
							saveConfigs()
						end
                        if payload.mappings and message.src == masterDNS.BNP then
                            debugPrint("[MASTER_MAP] Got an update from Master DNS, applying update to hosts registry")
                            hosts = payload.mappings
                            saveMaster()
                        end
					else
                        debugPrint("[MASTER_MAP] Handling as master DNS")
						if payload.time > masterStart then
							master = false
							masterStart = 0
							masterDNS = { BNP = message.src, time = payload.time }
							print("No longer Master DNS, an older Master found")
							saveConfigs()
						end
					end
				elseif payload.type == "HOSTS_DIFF" or payload.type == "HOST_DIFF_TO_MASTER" or payload.type == "DNS_SVR_DIFF" then
					if master or message.src == masterDNS.BNP then
						local oldHosts = {}
						if master then
							for k,v in pairs(hosts) do oldHosts[k] = { BNP = v.BNP, flags = { table.unpack(v.flags or {}) } } end
						end
						handleHostsDiff(message)
						if master then
							local diff = makeDiff(oldHosts, hosts)
							local relay = { type = "DNS_SVR_DIFF", diff = diff } -- Another different type name to get around traffic routing
							broadcastAll(relay)
							debugPrint("[DIFF] Relayed diff from a child DNS")
						else
							debugPrint("[DOMAIN-REGISTER] Processed Diff from Master, relaying diff to children")
							broadcastDiff(payload.diff)
						end
					end
				elseif payload.type == "DNS_MAP" then
					if message.src == masterDNS.BNP then
						hosts = {}
						for k,v in pairs(payload.mapping) do hosts[k] = v end
						print("Replaced local Mapping with Master Mappings, relaying update to children")
						debugPrint("Replaced local Mapping with Master Mappings, relaying update to children",true)
						broadcastFullHosts()
					end
				elseif payload.type == "DOMAIN_REGISTER_REQ" then
					--Check if you have a master and forward the packet to them otherwise process it here, or if you are the master process it here
					if masterDNS.BNP then
						sendDirect(masterDNS.BNP, payload)
						debugPrint("[DOMAIN-REGISTER] Sending to Master to properly process registry request",true)
					else
						debugPrint("[DOMAIN_REGISTER] Processing Domain Registry Request",true)
						local oldHosts = {}
						for k,v in pairs(hosts) do oldHosts[k] = { BNP = v.BNP, flags = { table.unpack(v.flags or {}) } } end
						if not hosts[payload.domainName] then
							debugPrint("[DOMAIN-REGISTER] No domain registered under "..payload.domainName.." allowing domain registry")
							hosts[payload.domainName] = { BNP = payload.BNP, flags = payload.flags }
							sendDirect(payload.BNP, { type = "PING_REPLY", message = "Domain Succuessfuly registered as "..payload.domainName })
							debugPrint("[DOMAIN-REGISTER] Domain Succuessfuly registered")
						else
							debugPrint("[DOMAIN-REGISTER] Domain name "..payload.domainName.." might be taken or another issue has occurred expect another request or contact from "..payload.BNP)
							sendDirect(payload.BNP, { type = "ERROR", message = "Domain cannot be registered, try another domain name or contact DNS server owner" })
						end
						debugPrint("[DOMAIN-REGISTER] Updating children with domain information in a diff packet")
						local diff = makeDiff(oldHosts,hosts)
						broadcastDiff(diff)
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
  addhost [name] [BNP] [flags...]
  delhost [name]
  listhosts
  'broadcast' or 'broadcast m'
  BNP
  setbnp [BNP]
  master [true,false]
  findMaster
  exit
  help
  debugmode [true,false]
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
        local cmd = args[1]:lower()
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
			local mast = args[2]
			if mast == "m"  and master then
				print("Broadcasting as a Master")
				broadcastFullHosts(true)
			elseif not master and mast == "m" then
				print("Can't send to children DNS, I'm not a Master DNS")
			else
				broadcastFullHosts()
			end
		elseif cmd == "findmaster" then
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
        elseif cmd == "bnp" then
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
