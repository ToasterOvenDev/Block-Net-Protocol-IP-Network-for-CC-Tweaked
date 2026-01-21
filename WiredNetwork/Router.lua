-- router.lua Version 2.23
-- Secure router with persistent routing, password CLI, clean autostart, safe termination, multi-channel support, switch discovery support


-- SELF-LAUNCH IN MULTISHELL (Forge-safe)
if type(multishell) == "table" and type(multishell.getCurrent) == "function" then
    local currentProgram = shell.getRunningProgram()
    if multishell.getCurrent() == 1 then
        multishell.launch(shell, currentProgram)
        return
    end
end

-- ==========================
-- DEBUG MODE
-- ==========================
local debugFile = "router.log"
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


-- MONITOR SETUP + INFO LOGGING
local mon = peripheral.find("monitor")

local function logInfo(msg)
    if mon then
        local _, y = mon.getCursorPos()
        local _, h = mon.getSize()
        if y >= h then
            mon.scroll(1)
            y = h - 1
        end
        mon.setCursorPos(1, y + 1)
        mon.write(msg)
    else
        print(msg)
    end
end

-- CONFIGURATION

local sides = {"left","right","top","bottom","front","back"}
local DEFAULT_TTL = 64
local HELLO_INTERVAL = 60
local CLI_PASSWORD = "Admin"
local ROUTING_FILE = "routing_table.txt"
local BNP_FILE = "BNP.txt"
local PRIVATE_CHANNEL = os.getComputerID()
local knownChannels = {}
local routerNet = "10.10.10"

--RDP Configs

local RDP = false -- If Route Discovery Protocol is enabled (Not full RDP)
local RDPfull = { ["left"] = false,["right"] = false,["top"] = false,["bottom"] = false,["front"] = false,["back"] = false } -- If full Route Discovery Protocol is enabled on a side (Responding to RDP_REQUEST packets)
local RDPSides = {} -- "left","right","top","bottom","front","back"
local RDPNeighbors = {} -- Table of both last time a neighbor was seen and the subnets they've given

-- NAT Configs

local NAT = false -- If NAT is enabled
local natTable = {} -- Table holding the nat translations made
local natInsideSides = {} -- "left","right","top","bottom","front","back"
local natOutsideSides = {} -- "left","right","top","bottom","front","back"
local NATseq = 0

-- DLR Configs

local denySrc = false --  Deny by source
local denyDst = false -- Deny by destination
local whLst = false -- Only allow the addresses in denyList
local blkLst = false -- Only deny the addresses in denyList
local denyList = {} -- What addresses to deny

-- STATE

local interfaces = {} -- side -> wrapped modem
local hosts = {}         -- host BNP -> side (learned via HELLO_REPLY)
local lastSeen = {} -- Last time a host responded to a HELLO_REQUEST
local seen = {} -- UID's seen
local routingTable = {} -- Subnet -> side
local trafficRoutingTable = {} -- Traffic type -> side
local defaultRoute = nil -- Unknown routes side
local routerBNP -- Router's BNP
local terminated = false -- Running?

-- UTILITIES
local seq = 0
local function makeUID()
	seq = seq+1
    return tostring(seq).."-"..tostring(os.getComputerID())
end

local function splitBNP(BNP)
    if not BNP then return nil,nil,nil end
    local a,b,c = BNP:match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(a), tonumber(b), tonumber(c)
end

local function matchSubnet(BNP, subnet)
    local a1,b1,c1 = splitBNP(BNP)
    local a2,b2,c2 = splitBNP(subnet)
    if not a1 or not a2 then return false end
    return a1==a2 and b1==b2 and c1==c2
end

local function saveRoutingTable()
    local f = fs.open(ROUTING_FILE,"w")
    for subnet, side in pairs(routingTable) do
        f.writeLine(subnet.." "..side)
    end
    if defaultRoute then f.writeLine("default "..defaultRoute) end
    f.close()
	local f = fs.open("trafficRouting.txt","w")
	f.write(textutils.serialize(trafficRoutingTable))
	f.close()
end

local function loadRoutingTable()
    routingTable = {}
    defaultRoute = defaultRoute
    if fs.exists(ROUTING_FILE) then
        local f = fs.open(ROUTING_FILE,"r")
        while true do
            local line = f.readLine()
            if not line then break end
            if line:match("^default") then
                defaultRoute = line:match("^default%s+(%S+)")
            else
                local subnet, side = line:match("^(%S+)%s+(%S+)$")
                if subnet and side then routingTable[subnet] = side end
            end
        end
        f.close()
    end
	if fs.exists("trafficRouting.txt") then
		local f = fs.open("trafficRouting.txt","r")
		local table = f.readAll()
		f.close()
		if table == "" then
			trafficRoutingTable = {}
		else
			trafficRoutingTable = textutils.unserialize(table)
		end
	end
end

if not fs.exists("services.txt") then
    local f = fs.open("services.txt","w")
    f.write("")
    f.close()
end

-- Save services
local function saveRouterServices()
    local services = {
        RDP = RDP,
        RDPfull = RDPfull,
        RDPSides = RDPSides,
        RDPNeighbors = RDPNeighbors,
        NAT = NAT,
        natTable = natTable,
        natInsideSides = natInsideSides,
        natOutsideSides = natOutsideSides,
        denySrc = denySrc,
        denyDst = denyDst,
        whLst = whLst,
        blkLst = blkLst,
        denyList = denyList,
        CLI_PASSWORD = CLI_PASSWORD
    }

    local f = fs.open("services.txt","w")
    f.write(textutils.serialize(services))
    f.close()
end
-- Load services
local function loadRouterServices()
    local f = fs.open("services.txt","r")
    local services = textutils.unserialize(f.readAll())
    f.close()
    if services == "" or services == nil then -- I don't know why this file in particular needed the check for nil instead of empty, but that's why it's different
        RDP = false
        RDPfull = { ["left"] = false,["right"] = false,["top"] = false,["bottom"] = false,["front"] = false,["back"] = false }
        RDPSides = {}
        RDPNeighbors = {}
        NAT = false
        natTable = {}
        natInsideSides = {}
        natOutsideSides = {}
        denySrc = false
        denyDst = false
        whLst = false
        blkLst = false
        denyList = {}
        CLI_PASSWORD = "Admin"
    else
        RDP = services.RDP
        RDPfull = services.RDPfull
        RDPSides = services.RDPSides
        RDPNeighbors = services.RDPNeighbors
        NAT = services.NAT
        natTable = services.natTable
        natInsideSides = services.natInsideSides
        natOutsideSides = services.natOutsideSides
        denySrc = services.denySrc
        denyDst = services.denyDst
        whLst = services.whLst
        blkLst = services.blkLst
        denyList = services.denyList
        CLI_PASSWORD = services.CLI_PASSWORD
    end

end
loadRouterServices()
-- LOAD OR CREATE BNP
if not fs.exists(BNP_FILE) then
    routerBNP = "10.10.10."..os.getComputerID()
    local f = fs.open(BNP_FILE,"w")
    f.writeLine(routerBNP)
    f.close()
    logInfo("Created "..BNP_FILE.." with default BNP: "..routerBNP)
else
    local f = fs.open(BNP_FILE,"r")
    routerBNP = f.readLine()
    f.close()
    logInfo("Loaded router BNP from "..BNP_FILE..": "..routerBNP)
end

local function updateBNPFile()
    local f = fs.open(BNP_FILE,"w")
    f.writeLine(routerBNP)
    f.close()
end

-- SETUP INTERFACES
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        interfaces[side] = m
        pcall(function()
            m.open(1)                -- broadcast/discovery
            m.open(PRIVATE_CHANNEL)  -- unicast
        end)
        logInfo("Opened modem on side "..side.." (channels 1 + "..PRIVATE_CHANNEL..")")
    end
end

if next(interfaces) == nil then error("No modems found!") end

loadRoutingTable()

-- PACKET UTILS

local function broadcastOnAllExcept(incomingSide, packet)
    for side, m in pairs(interfaces) do
        if side ~= incomingSide then
            m.transmit(1,1,packet)
        end
    end
end

local function switchReply(side, packet)
    local payload = packet.payload
     -- Only respond if this is a switch hello from a switch
    if not payload.switch then return end
     -- Respond to switch with our BNP and private channel
    local response = {
        type = "S_H",
        switch = false, -- router, not a switch
        private_channel = PRIVATE_CHANNEL
    }
    local pckt = {
   		uid = makeUID(),
        src = routerBNP,
        dst = packet.src,
        ttl = 8,
        payload = response
    }
    -- Send back to the switch using the port we received from
    interfaces[side].transmit(payload.private_channel or 1, PRIVATE_CHANNEL, pckt)
    debugPrint("[S_H] Responded to S_H from switch " .. tostring(packet.src) .. " with BNP " .. routerBNP,true)
end

-- FORWARDING & PACKET HANDLING
local function learnHostRoute(srcBNP, incomingSide)
    if not srcBNP then return end
    if hosts[srcBNP] ~= incomingSide then
    	hosts[srcBNP] = incomingSide
        lastSeen[srcBNP] = os.clock()
        local subnet = srcBNP:match("^(%d+%.%d+%.%d+)")
        if subnet and subnet ~= routerNet then
            routingTable[subnet] = incomingSide
        end
        saveRoutingTable()
        if subnet ~= routerNet then
            logInfo("Learned host "..srcBNP.." via "..incomingSide.." (added route "..(subnet or "nil").." -> "..incomingSide..")")
        else
            logInfo("Learned router "..srcBNP.." via "..incomingSide)
        end
    else
        lastSeen[srcBNP] = os.clock()
    end
end

local function forwardPacket(packet, incomingSide)
    if not packet or type(packet) ~= "table" or not packet.uid then return end
    if seen[packet.uid] then return end
    seen[packet.uid] = true
    if packet.ttl <= 0 then debugPrint("[TTL] Dropping TTL up...")return end -- If the time to live is up then drop the packet
    packet.ttl = (packet.ttl or DEFAULT_TTL) - 1

    local dstSide
    local dstCh = 1
    if hosts[packet.dst] then
    	dstSide = hosts[packet.dst]
        dstCh = knownChannels[dstSide] or 1
    end
    local payload = packet.payload

    -- If packet has table payload, process packets meant for router
    if type(payload) == "table" then
        if payload.type == "HELLO_REPLY" then
            -- Learn route + store sender's private channel
            learnHostRoute(packet.src, incomingSide)
            if payload.private_channel and not knownChannels[incomingSide] then
                knownChannels[incomingSide] = payload.private_channel
                debugPrint("[HELLO] Learned private channel "..payload.private_channel.." for "..packet.src,true)
            end
            return
        elseif payload.type == "S_H" then --Switch hello packet for switch discovery
			switchReply(incomingSide,packet)
            knownChannels[incomingSide] = payload.private_channel --Switch Channel WILL override any previous entries
            debugPrint("[S_H] Learned private channel "..payload.private_channel.." for switch "..payload.private_channel,true)
            debugPrint("[S_H] Switch takes priority overriding previous channel for side: "..incomingSide)
            return
		elseif payload.type == "HELLO_REQUEST" then
        	-- Learn the private_channel from the sender (if this came from another router)
        	if payload.private_channel and not knownChannels[incomingSide] then
                knownChannels[incomingSide] = payload.private_channel
                debugPrint("[HELLO] Discovered router "..packet.src.." on channel "..payload.private_channel,true)
        	end
        	-- Reply back including this router’s channel
        	local replyPayload = {
         	       type = "HELLO_REPLY",
         	       private_channel = PRIVATE_CHANNEL
        	}
        	local reply = {
         	       uid = makeUID(),
            	    src = routerBNP,
                	dst = packet.src,
               		ttl = DEFAULT_TTL,
                	payload = replyPayload
        	}
        	-- Transmit back using sender’s known channel if available, else broadcast
        	interfaces[incomingSide].transmit(dstCh, PRIVATE_CHANNEL, reply)
        	debugPrint("[HELLO] Replied to HELLO_REQUEST from "..packet.src.." on ch "..dstCh,true)
            return
        elseif payload.type == "RDP_REQUEST" and RDPfull[incomingSide] then
			-- First make sure it comes from a RDP enabled side
			local RDPside = false
			for _,side in pairs(RDPSides) do
				if incomingSide == side then
					RDPside = true
				end
			end
            if not RDPside then debugPrint("[RDP] Not an RDP side dropping...") return end
			if RDPside then
                debugPrint("[RDP] Sending routing table to "..packet.src)
                local routesToSend = {}
                for subnet,side in pairs(routingTable) do
                    if side ~= incomingSide then
                        routesToSend[subnet] = side
                    end
                end
				local replyPayload = {
         	       type = "RDP_HELLO",
         	       routes = routesToSend
        		}
        		local reply = {
         	       uid = makeUID(),
            	    src = routerBNP,
                	dst = packet.src,
               		ttl = DEFAULT_TTL,
                	payload = replyPayload
        		}
				interfaces[incomingSide].transmit(dstCh, PRIVATE_CHANNEL, reply)
        		debugPrint("[RDP] Replied to RDP_REQUEST from "..packet.src.." on ch "..dstCh,true)
			end
            return
		elseif payload.type == "RDP_HELLO" and RDP then
			local RDPside = false
			for _,side in pairs(RDPSides) do
				if incomingSide == side then
					RDPside = true
				end
			end
            if not RDPside then debugPrint("[RDP] Not an RDP side dropping...") end
			if RDPside and payload.routes then
				for subnet in pairs(payload.routes) do
                    if not routingTable[subnet] then
					    routingTable[subnet] = incomingSide
					    if not RDPNeighbors[packet.src] then RDPNeighbors[packet.src] = {routes = {}, lastSeen = os.clock()} end
					    table.insert(RDPNeighbors[packet.src].routes,subnet)
					    RDPNeighbors[packet.src].lastSeen = os.clock()
                        debugPrint("[RDP] Learned "..subnet.." from "..packet.src)
                    else
                        debugPrint("[RDP] Ignoring "..subnet.." from "..packet.src,true)
                    end
				end
                saveRouterServices()
                saveRoutingTable()
			end
			return
    	elseif payload.type == "PING" then
        	if packet.dst == routerBNP then
           		local reply = { uid = makeUID(), src = routerBNP, dst = packet.src, ttl = DEFAULT_TTL, payload = { type = "PING_REPLY",message = "pong" } }
            	interfaces[incomingSide].transmit(dstCh,PRIVATE_CHANNEL,reply)
            	logInfo("Replied to PING from "..packet.src)
                return
     		else
             	--contiue with forwarding logic
     		end
		end
    end

    local function routeByType(pckt, incside)
    	local pyld = pckt.payload

    	local destination = trafficRoutingTable[pyld.type]
    	if destination and interfaces[destination] and destination ~= incside then
    	    interfaces[destination].transmit(dstCh, PRIVATE_CHANNEL, packet)
    	    debugPrint("Traffic type "..pyld.type.." routed to "..destination)
    	    return true
    	end

    	debugPrint("[TRAFFIC ROUTING] No traffic route for type "..tostring(pyld.type), true)
    	return false
	end

	if routeByType(packet, incomingSide) then
    	return
	end

    local function InorOut() -- NAT helper that determines if the packet in on a NAT In port or a NAT Out port
		for _,side in pairs(natOutsideSides) do -- Actually checks if the packet is coming from outside
			if incomingSide == side then
				return false, true
			end
		end
		for _,side in pairs(natInsideSides) do -- Acutally checks if the packet is coming from inside
			if incomingSide == side then
				return true, false
			end
		end
        return false, false
	end

	if NAT then -- If nat is enabled do NAT translation processes
		local packetin, packetout = InorOut() -- If the packet is coming from a in or out port
		if packetout then -- Handles if packets are coming from the outside
			local portNum = packet.dst:match(":(%d+)$")
			debugPrint("[NAT] Attempting to translate: "..packet.dst.." port is: "..portNum,true)
			for port,trueBNP in pairs(natTable) do
				if portNum == port then
					debugPrint("[NAT] Translation successful")
					packet.dst = trueBNP
					break
				end
			end
		elseif packetin then -- Handles if the packets are coming from the inside
			local port = packet.uid:match("%-(%d+)$") -- Uses the computer ID from the UID of the packet as the port number, so the translation can act as a persistant outside address
			natTable[port] = packet.src
			packet.src = routerBNP..":"..port
			debugPrint("[NAT] NAT translation "..natTable[port].." -> "..routerBNP..":"..port,true)
			saveRouterServices()
		else
			print("Please set inside and outside ports for full NAT capablility")
		end
	end

    -- Non-payload or after payload handling: Unicast & Normal forwarding
    -- If destination is broadcast, forward to all other sides
    if packet.dst == "0" then
        broadcastOnAllExcept(incomingSide, packet)
        return
    end

    -- If packet is destined to this router, process locally
    if packet.dst == routerBNP then
        logInfo(("Packet for router: %s"):format(textutils.serialize(packet.payload)))
        return
    end

    -- If we know a direct host mapping, send there (avoid sending back to incoming side)
    local targetSide = hosts[packet.dst]
    if targetSide and interfaces[targetSide] then
        if targetSide ~= incomingSide then
            interfaces[targetSide].transmit(dstCh,PRIVATE_CHANNEL,packet)
            return
        else
            -- if target is on incoming side, nothing to do (already on that side)
            return
        end
    end

    -- Otherwise, try subnet routing
    for subnet, side in pairs(routingTable) do
        if matchSubnet(packet.dst, subnet) and interfaces[side] then
            if side ~= incomingSide then
                interfaces[side].transmit(dstCh,PRIVATE_CHANNEL,packet)
            end
            return
        end
    end

    -- Fallback: default route if available
    if defaultRoute and interfaces[defaultRoute] and defaultRoute ~= incomingSide then
        interfaces[defaultRoute].transmit(dstCh,PRIVATE_CHANNEL,packet)
        return
    end

    -- No route found
    logInfo("Dropping packet to "..tostring(packet.dst).." (no route)")
end

-- PERIODIC TASKS
local function periodicHelloCheck()
    while not terminated do
        local packet = {
    		uid = makeUID(),
    		src = routerBNP,
    		dst = "0",
    		ttl = DEFAULT_TTL,
    		payload = {
        		type = "HELLO_REQUEST",
        		private_channel = PRIVATE_CHANNEL
    		}
		}

        for _, modem in pairs(interfaces) do modem.transmit(1,1,packet) end

        local now = os.clock()
        for host, t in pairs(lastSeen) do
            if now - t > (HELLO_INTERVAL*2) then
                logInfo("Host timed out: "..host)
                hosts[host] = nil
                lastSeen[host] = nil
                local subnet = host:match("^(%d+%.%d+%.%d+)")
                routingTable[subnet] = nil
                saveRoutingTable()
            end
        end
        os.sleep(HELLO_INTERVAL)
    end
end

local function periodicRDPCheck()
    debugPrint("[RDP] Periodic RDP check starting...")
	while not terminated do
        os.sleep(600) -- Every 10 minutes (600 seconds)
		local packet = { -- Build the RDP check
			uid = makeUID(),
			src = routerBNP,
    		dst = "0",
    		ttl = 1,
    		payload = {
    			type = "RDP_REQUEST"
    		}
		}
        debugPrint("[RDP] RDP Packet built")
		for _, side in pairs(RDPSides) do
            if interfaces[side] then interfaces[side].transmit(1,1,packet) debugPrint("[RDP] Sending RDP Hello Check on side: "..side,true)end
        end -- Send the RDP check

		local now = os.clock()
        for neighbor, table in pairs(RDPNeighbors) do -- Cleanup for neighbors that haven't been seen for more than 20 minutes
            if now - table.lastSeen >= (600*2) then -- if it hasn't been seen for 20 minutes or more then clean out it's routing info
                for _,subnet in pairs(RDPNeighbors[neighbor].routes) do
                    if routingTable[subnet] then
                        routingTable[subnet] = nil
                    end
				end
				RDPNeighbors[neighbor] = nil
            end
        end
        saveRouterServices()
	end
end


local function cleanupSeenUIDs()
	while not terminated do
		seen = {}     -- simply clear the table
		debugPrint("[UID] Cleared seen UID cache")
		if RDP then
			local packet = { -- Build the RDP check
				uid = makeUID(),
				src = routerBNP,
				dst = "0",
				ttl = 1,
				payload = {
					type = "RDP_REQUEST"
				}
			}
			debugPrint("[RDP] RDP Packet built")
			for _, side in pairs(RDPSides) do
				if interfaces[side] then
					interfaces[side].transmit(1, 1, packet)
					debugPrint("[RDP] Sending RDP Hello Check on side: " .. side, true)
				end
			end -- Send the RDP check

			local now = os.clock()
			for neighbor, table in pairs(RDPNeighbors) do -- Cleanup for neighbors that haven't been seen for more than 20 minutes
				if now - table.lastSeen >= (1200) then -- if it hasn't been seen for 4 cycles delete the route as it's almost certianly untrustworthy
					for _, subnet in pairs(RDPNeighbors[neighbor].routes) do
						if routingTable[subnet] then
							routingTable[subnet] = nil
						end
					end
					RDPNeighbors[neighbor] = nil
				end
			end
			saveRouterServices()
		end
		os.sleep(300) -- every 5 minutes (300 seconds)
	end
end

-- CLIs

local function DLRCLI()
    local function printHelp()
    print([[DLR Commands:
        help
        whitelist
        blacklist
        deny [src,dst,disable]
        add [subnet or BNP]
		      remove [subnet or BNP,all]
        show [deny-list,configs]
		      exit

        To deny a subnet you must enter the
        network plus a wildcard bit (0)
        Ex: 192.168.1.0
        This denies the 192.168.1 subnet
        ]])
    end

    while true do
        io.write("(DLR)> ")
        local line = read():lower()
        if not line then break end
        local cmd,arg1 = line:match("^(%S+)%s*(%S*)$")
        if cmd=="help" then printHelp()
        elseif cmd=="whitelist" then whLst = true blkLst = false print("Enabled whitelist") saveRouterServices()
        elseif cmd=="blacklist" then blkLst = true whLst =false print("Enabled blacklist") saveRouterServices()
        elseif cmd=="deny" then
            if arg1 == "src" then
                denySrc = true
                denyDst = false
                print("Enabled deny by source")
                saveRouterServices()
            elseif arg1 == "dst" then
                denyDst = true
                denySrc = false
                print("Enabled deny by destination")
                saveRouterServices()
			elseif arg1 == "disable" then
                denyDst = false
                denySrc = false
                print("Disabled DLR")
                saveRouterServices()
            else
                print("'src' (Source BNP) or 'dst' (Destination BNP), or 'disable'?")
            end
        elseif cmd=="add" then
            if arg1 then
                table.insert(denyList,arg1)
                print("Added "..arg1.." to denylist")
                saveRouterServices()
            else
                print("Add what? ex: 192.168.1.1 or for subnets 192.168.1.0")
            end
		elseif cmd=="remove" then
			if arg1 == "all" then
				denyList = {}
                print("Cleared deny list")
                saveRouterServices()
			elseif arg1 then
                local ok
				for i,BNP in pairs(denyList) do
					if BNP == arg1 then
						table.remove(denyList,i)
                        print("Removed "..BNP)
                        ok = true
                        saveRouterServices()
                        break
					end
				end
                if not ok then
                    print("BNP or Subnet doesn't exist, try again?")
                end
			else
				print("Remove what? ex: 192.168.1.1 or for subnets 192.168.1.0")
			end
		elseif cmd=="exit" then
            print("Returning to Router mode")
			return
        elseif cmd=="show" then
            if arg1=="deny-list" then
                if denyList[1] then
                    for i,entry in pairs(denyList) do
					    print("Deny entry "..i..": "..entry)
				    end
                else
                    print("Deny List is empty")
                end
            elseif arg1=="configs" then
                if denyDst then
                    print("Denying by Destination")
                elseif denySrc then
                    print("Denying by Source")
                else
                    print("Not denying any addresses")
                end
                if whLst then
                    print("Deny list is a whitelist")
                elseif blkLst then
                    print("Deny list is a blacklist")
                else
                    print("Deny list isn't a blacklist or a whitelist")
                end
            end
        else
            print("Unrecognized command")
		end
    end
end

local function RDPCLI()
	local function printHelp()
    print([[RDP Commands:
        help
		      enable
		      disable
		      side [left,right,etc] [enable,disable] [full]
        show
        checkRDP
		      exit

        If a side is not set to enable
        the interface will ignore and avoid
        sending RDP packets out of it
        use 'sides' command in (Router)> mode
        to list available interfaces
        ]])
    end

    while true do
        io.write("(RDP)> ")
        local line = read():lower()
        if not line then break end
        local cmd,arg1,arg2,arg3 = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
        if cmd=="help" then printHelp()
        elseif cmd=="enable" then
            RDP = true
            print("Please restart device for changes to take effect")
            saveRouterServices()
		elseif cmd=="disable" then
            RDP = false
			RDPfull = { ["left"] = false,["right"] = false,["top"] = false,["bottom"] = false,["front"] = false,["back"] = false }
            print("Please restart device for changes to take effect")
            saveRouterServices()
		elseif cmd=="side" then
			if arg2 == "enable" then
				local ok
				for side in pairs(interfaces) do -- Add the interface as a RDP enabled side
					if side == arg1 then
						table.insert(RDPSides,arg1)
                        ok = true
                        print("Enabled RDP on side "..side)
                        break
					end
				end
				if not ok then -- If the side isn't an interface then error
					print("Side "..arg1.." not found, try again!")
				end
				if arg3 == "full" then
					RDPfull[arg1] = true
					print("Set side to Full mode, will respond to requests")
				end
				saveRouterServices()
			elseif arg2 == "disable" then
                local ok
				for i,side in pairs(RDPSides) do
					if side == arg1 then
						table.remove(RDPSides,i)
                        ok = true
                        print("Disabled RDP on side "..side)
                        break
					end
				end
                if not ok then -- If the side isn't a RDP enabled side then error
                    print("Side isn't enabled, try again!")
                end
				if RDPfull[arg1] then
					RDPfull[arg1] = false
				end
				saveRouterServices()
            else
                print("Please enter a side and either enable or disable")
			end
        elseif cmd=="show" then
            if RDP then
                print("Route Discovery is enabled")
            else
                print("Route Discovery is disabled")
            end
            if not RDPSides[1] then
                print("There are not RDP sides enabled")
            else
                for i,side in pairs(RDPSides) do
					if RDPfull[side] then
						write("Full ")
					end
					print("RDP Side "..i..": "..side)
				end
            end
        elseif cmd=="checkrdp" then
            local packet = { -- Build the RDP check
			    uid = makeUID(),
			    src = routerBNP,
    			dst = "0",
    			ttl = 1,
    			payload = {
    				type = "RDP_REQUEST"
    			}
			}
			for _, side in pairs(RDPSides) do
            	if interfaces[side] then interfaces[side].transmit(1,1,packet) debugPrint("[DLR] Sending RDP Hello Check on side: "..side) end
        	end -- Send the RDP request
			print("RDP check preformed")
		elseif cmd=="exit" then
            print("Returning to Router mode")
			return
        else
            print("Unrecognized command")
    	end
	end
end

local function NATCLI()
	local function printHelp()
    print([[NAT Commands:
        help
        enable
		      disable
		      side [left,right,etc] [in,out]
        show [status,in,out]
		      exit

        For NAT to function set ALL sides
        listed with the'sides' command in 
        (Router)> mode to either in or out
    ]])
    end

    while true do
        io.write("(NAT)> ")
        local line = read():lower()
        if not line then break end
        local cmd,arg1,arg2 = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
        if cmd=="help" then printHelp()
        elseif cmd=="enable" then NAT = true print("Enabled NAT") saveRouterServices()
		elseif cmd=="disable" then NAT = false print("Disabled NAT") saveRouterServices()
		elseif cmd=="side" then
			if arg2 == "in" then
				for i,side in pairs(natOutsideSides) do -- Make sure that a port can't be both inside and outside
					if side == arg1 then
						table.remove(natOutsideSides,i)
                        print("Removed side "..side.." from outside group")
					end
				end
				local ok
				for side in pairs(interfaces) do -- Add the side to the inside ports group
					if side == arg1 then
						table.insert(natInsideSides,arg1)
                        print("Added side "..side.." to inside group")
                        ok = true
                        saveRouterServices()
                        break
					end
				end
				if not ok then -- If the side isn't an interface then error
					print("Side not found, try again")
				end
			elseif arg2 == "out" then
				for i,side in pairs(natInsideSides) do -- Make sure that a port can't be both inside and outside
					if side == arg1 then
						table.remove(natInsideSides,i)
                        print("Removed side "..side.." from inside group")
					end
				end
				local ok
				for side in pairs(interfaces) do -- Add the side to the outside ports group
					if side == arg1 then
						table.insert(natOutsideSides,arg1)
                        print("Added side "..side.." to outside group")
                        ok = true
                        saveRouterServices()
                        break
					end
				end
				if not ok then -- If the side isn't an interface then error
					print("Side not found, try again")
                else
                    print("Usage: side [side] [in/out] example: side left in")
				end
			end
        elseif cmd=="show" then
            if arg1 == "status" then
                if NAT then
                    print("NAT is enabled")
                else
                    print("NAT is disabled")
                end
            elseif arg1 == "in" then
                for i,side in pairs(natInsideSides) do
					print("NAT in side "..i..": "..side)
				end
				if not natInsideSides[1] then
					print("No Inside Sides")
				end
            elseif arg1 == "out" then
                for i,side in pairs(natInsideSides) do
					print("NAT out side "..i..": "..side)
				end
				if not natOutsideSides[1] then
					print("No Outside Sides")
				end
			elseif arg1 == "interfaces" then
				local taken = {}
				for i,face in pairs(natInsideSides) do
					table.insert(taken,face)
				end
				for i,face in pairs(natOutsideSides) do
					table.insert(taken,face)
				end
				for side in pairs(interfaces) do
					for i, face in pairs(taken) do
						if not side == face then
							print("Untaken side: "..side)
							break
						end
					end
				end
				if not taken[1] then
					print("No sides are NAT in or out sides")
				end
            end
		elseif cmd=="exit" then
            print("Returning to Router mode")
			return
        else
            print("Unrecognized command")
    	end
	end
end

local function cli()
    local function printHelp()
        print([[Router Commands:
        show [routes,hosts,channels]
        BNP set [BNP]
        add route [subnet] [side]
        add traffic-route [type] [side]
        del route [subnet]
        del traffic-route [type]
        set default-route [side]
        sides
        [NAT, RDP, DLR]
        debug [true,false]
        change-pass [newPassword]
        exit
        terminate
        help
    ]])
    end
    local function cliLoop()
        while true do
            io.write("(Router)> ")
            local line = read():lower()
            if not line then break end
            local cmd, arg1, arg2, arg3 = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
            if cmd == "help" then
                printHelp()
            elseif cmd == "exit" then
                term.clear()
                term.setCursorPos(1, 1)
                break
            elseif cmd == "terminate" then
                print("Enter password to confirm termination:")
                local check = read("*")
                if check == CLI_PASSWORD then
                    logInfo("Router shutting down...")
                    terminated = true
                    return
                else
                    print("Incorrect password. Abort termination.")
                end
            elseif cmd == "show" then
                if arg1 == "routes" then
                    for s, i in pairs(routingTable) do
                        print(s .. " -> " .. i)
                    end
                    if defaultRoute then
                        print("defaultRoute -> " .. defaultRoute)
                    end
                elseif arg1 == "hosts" then
                    for h, s in pairs(hosts) do print(h .. " -> " .. s) end
                elseif arg1 == "channels" then
                    for BNP, ch in pairs(knownChannels) do print(BNP .. " -> " .. ch) end
                else
                    print("Usage: show routes | show host | show channels")
                end
            elseif cmd == "bnp" and arg1 == "set" and arg2 ~= "" then
                routerBNP = arg2
                updateBNPFile()
                logInfo("Router BNP updated to " .. routerBNP)
            elseif cmd == "add" and arg1 == "route" and arg2 ~= "" and arg3 ~= "" then
                if not interfaces[arg3] then
                    print("Invalid side: " .. arg3)
                else
                    routingTable[arg2] = arg3; logInfo("Added route " .. arg2 .. " -> " .. arg3); saveRoutingTable()
                end
            elseif cmd == "add" and arg1 =="traffic-route" and arg2 ~= "" and arg3 ~= "" then
                if not interfaces[arg3] then
                    print("Invalid side: " .. arg3)
                else
                    local type = arg2:upper()
                    trafficRoutingTable[type] = arg3; logInfo("Added route " .. type .. " packets -> " .. arg3); saveRoutingTable()
                end
            elseif cmd == "del" and arg1 == "route" and arg2 ~= "" then
                routingTable[arg2] = nil; logInfo("Deleted route for " .. arg2); saveRoutingTable()
            elseif cmd == "del" and arg1 == "traffic-route" and arg2 ~= "" then
                trafficRoutingTable[arg2] = nil; logInfo("Deleted route for " .. arg2); saveRoutingTable()
            elseif cmd == "set" and arg1 == "default-route" and arg2 ~= "" then
                if interfaces[arg2] then
                    defaultRoute = arg2; logInfo("Default route set to " .. arg2); saveRoutingTable()
                else
                    print("Invalid side: " .. arg2)
                end
            elseif cmd == "sides" then
                for s, _ in pairs(interfaces) do print("  " .. s) end
            elseif cmd == "nat" then
                NATCLI()
            elseif cmd == "rdp" then
                RDPCLI()
            elseif cmd == "dlr" then
                DLRCLI()
            elseif cmd == "debug" then
                if arg1 == "true" then
                    print("Debug enabled")
                    DEBUG = true
					debugPrint("[BOOT] DEBUG STARTED",true)
                elseif arg1 == "false" then
                    print("Debug disabled")
                    DEBUG = false
				else
					print("Accepted arguments 'true' or 'false'")
                end
            elseif cmd == "change-pass" then
                if arg1 then
                    print("Password changed to " .. arg1)
                    CLI_PASSWORD = arg1
                    saveRouterServices()
                end
            else
                print("Unknown command.")
            end
        end
    end
    local function passwordEntry()
        while not terminated do
            io.write("Enter router CLI password: ")
            local input = read("*")
            if input ~= CLI_PASSWORD then
                print("Incorrect password.")
                os.sleep(1)
            else
                print("Access granted. Router CLI started.")
                cliLoop()
            end
        end
    end
    os.sleep(0.25)
    print("Router Version 2.22 Loading")
    os.sleep(1)
    passwordEntry()
end

-- DLR functions
-- Subnet matching for DLR .0 means it's a subnet and should deny anything that matches before the 0
local function subnetMatch(BNP, subnet)
    debugPrint("[DLR] Matching "..BNP,true)
    -- Split into number groups
    -- First check if they are an exact match
    if BNP == subnet then debugPrint("[DLR] Perfect Match",true) return true end
    local function splitGroups(str)
        local t = {}
        for part in string.gmatch(str, "[^.]+") do -- break up str into groups seperated by the .'s (192.168.1.12 -> {192, 168, 1, 12})
            table.insert(t, tonumber(part))
        end
        return t
    end
    debugPrint("[DLR] Splitting BNP and Subnet",true)
    local BNPParts = splitGroups(BNP)
    local netParts = splitGroups(subnet)
    -- Determine number of groups to match before first 0
    local matchCount = 0
    for i in ipairs(netParts) do
        if netParts[i] == 0 then break end
        matchCount = matchCount + 1
    end
    debugPrint("[DLR] Matching first "..tostring(matchCount).." number groups",true)
    -- If there is no 0 and not exact, it's not a match
    if matchCount == #netParts then
        debugPrint("[DLR] Not a match, not exact address",true)
        return false
    end
    -- Compare only required groups
    for i = 1, matchCount do
        if BNPParts[i] ~= netParts[i] then
            debugPrint("[DLR] Not a match, not a deny list subnet",true)
            return false
        end
    end
    debugPrint("[DLR] Match",true)
    return true
end

local function dLR(msg, side)
    debugPrint("[DLR] Attempting to apply deny list...",true)
    local srcip = msg.src
    local dstip = msg.dst
    if denySrc == true then
        if whLst == true then
            for _,entr in pairs(denyList) do
                if subnetMatch(srcip,entr) then -- Sends it to subnetMatch and will forward if it's true
                    forwardPacket(msg, side)
                end
            end
            return
        elseif blkLst == true then
            for _,entr in pairs(denyList) do
                if subnetMatch(srcip,entr) then -- Sends it to subnetMatch and will deny it if it's true
                    return
                end
            end
            forwardPacket(msg, side)
        end
    elseif denyDst == true then
        if whLst == true then
            for _,entr in pairs(denyList) do
                if subnetMatch(dstip,entr) then
                    forwardPacket(msg, side)
                end
            end
            return
        elseif blkLst == true then
            for _,entr in pairs(denyList) do
                if subnetMatch(dstip,entr) then
                    return
                end
            end
            forwardPacket(msg, side)
        end
    else
        forwardPacket(msg, side)
    end
end
-- EVENT LOOP
local function listener()
    while not terminated do
        local _, side, _, _, msg = os.pullEvent("modem_message")
        if interfaces[side] and type(msg)=="table" and msg.uid then
            if denyDst or denySrc then
                dLR(msg, side)
            else
                forwardPacket(msg, side)
            end
        end
    end
end

-- AUTOSTART SETUP
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'router.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('router.lua')")
        f.close()
        logInfo("Router auto-start added to startup.")
    else
        logInfo("Router already configured to auto-start.")
    end
end

ensureStartup()

-- STARTUP
if RDP then
    parallel.waitForAny(listener, cli, periodicHelloCheck, cleanupSeenUIDs,periodicRDPCheck)
end
parallel.waitForAny(listener, cli, periodicHelloCheck, cleanupSeenUIDs)