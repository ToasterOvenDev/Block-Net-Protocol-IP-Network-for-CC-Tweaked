-- router.lua Version 1.94
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
local DEBUG = false
local function debugPrint(msg)
    if DEBUG then print("[DEBUG] " .. msg) end
end


-- MONITOR SETUP + INFO LOGGING
local mon = peripheral.find("monitor")

local function logInfo(msg)
    if mon then
        local x, y = mon.getCursorPos()
        local w, h = mon.getSize()
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
local DEFAULT_TTL = 8
local HELLO_INTERVAL = 60
local CLI_PASSWORD = "Admin"
local ROUTING_FILE = "routing_table.txt"
local BNP_FILE = "BNP.txt"
local PRIVATE_CHANNEL = os.getComputerID()
local knownChannels = {}
local routerNet = "10.10.10"

--RDP Configs

local RDP=false -- If Router Discovery Protocol is enabled
local RDPSides = {} -- "left","right","top","bottom","front","back"
local RDPNeighbors = {} -- Table of both last time a neighbor was seen and the subnets they've given

-- NAT Configs

local NAT = false -- If NAT is enabled
local natTable = {} -- Table holding the nat translations made
local natInsideSides = {} -- "left","right","top","bottom","front","back"
local natOutsideSides = {} -- "left","right","top","bottom","front","back"
local NATseq = 0

-- DLR Configs

local denySrc = false
local denyDst = false
local whLst = false
local blkLst = false
local denyList = {}

-- STATE
local interfaces = {}
local hosts = {}         -- host BNP -> side (learned via HELLO_REPLY)
local lastSeen = {}
local seen = {}
local routingTable = {}
local defaultRoute = nil
local routerBNP
local terminated = false

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
end

-- Save services
local function saveRouterServices()
    local services = {
        RDP=RDP,
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
        denyList = denyList
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

    RDP = services.RDP
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
    debugPrint("Responded to S_H from switch " .. tostring(packet.src) .. " with BNP " .. routerBNP)
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
        logInfo("Learned host "..srcBNP.." via "..incomingSide.." (added route "..(subnet or "nil").." -> "..incomingSide..")")
    else
        lastSeen[srcBNP] = os.clock()
    end
end

local function forwardPacket(packet, incomingSide)
    if not packet or type(packet) ~= "table" or not packet.uid then return end
    if seen[packet.uid] then return end
    seen[packet.uid] = true
    packet.ttl = (packet.ttl or DEFAULT_TTL) - 1
    if packet.ttl <= 0 then return end

    local dstSide
    local dstCh = 1
    if hosts[packet.dst] then
    	dstSide = hosts[packet.dst]
        dstCh = knownChannels[dstSide] or 1
    end
    local payload = packet.payload

    -- If packet has table payload, process known types first (so router learns any necessary info)
    if type(payload) == "table" then
        if payload.type == "HELLO_REPLY" then
        -- Learn route + store sender's private channel
        learnHostRoute(packet.src, incomingSide)
        if payload.private_channel and not knownChannels[incomingSide] then
                knownChannels[incomingSide] = payload.private_channel
                debugPrint("Learned private channel "..payload.private_channel.." for "..packet.src)
        end
        return
        elseif payload.type == "S_H" then --Switch hello packet for switch discovery
			switchReply(incomingSide,packet)
            knownChannels[incomingSide] = payload.private_channel --Switch Channel WILL override any previous entries
            debugPrint("Learned private channel "..payload.private_channel.." for switch "..payload.private_channel)
            debugPrint("Switch takes priority overriding previous channel for side: "..incomingSide)
            return
		elseif payload.type == "HELLO_REQUEST" then
        	-- Learn the private_channel from the sender (if this came from another router)
        	if payload.private_channel and not knownChannels[incomingSide] then
                knownChannels[incomingSide] = payload.private_channel
                debugPrint("Discovered router "..packet.src.." on channel "..payload.private_channel)
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
        	debugPrint("Replied to HELLO_REQUEST from "..packet.src.." on ch "..dstCh)
        	return
        elseif payload.type == "RDP_REQUEST" and RDP then
			-- First make sure it comes from a RDP enabled side
			local RDPside = false
			for _,side in pairs(RDPSides) do
				if incomingSide == side then
					RDPside = true
				end
			end
			if RDPside then
				local replyPayload = {
         	       type = "RDP_HELLO",
         	       routes = routingTable
        		}
        		local reply = {
         	       uid = makeUID(),
            	    src = routerBNP,
                	dst = packet.src,
               		ttl = DEFAULT_TTL,
                	payload = replyPayload
        		}
				interfaces[incomingSide].transmit(dstCh, PRIVATE_CHANNEL, reply)
        		debugPrint("Replied to RDP_REQUEST from "..packet.src.." on ch "..dstCh)
			end
			return
		elseif payload.type == "RDP_HELLO" and RDP then
			local RDPside = false
			for _,side in pairs(RDPSides) do
				if incomingSide == side then
					RDPside = true
				end
			end
			if RDPside then
				for subnet in pairs(payload.routes) do
					routingTable[subnet] = incomingSide
					table.insert(RDPNeighbors[packet.src].routes,subnet)
					RDPNeighbors[packet.src].lastSeen = os.clock()
				end
                saveRouterServices()
                saveRoutingTable()
			end
			return
    	elseif payload.type == "PING" then
        	if packet.dst == routerBNP then
           		local reply = { uid = makeUID(), src = routerBNP, dst = packet.src, ttl = DEFAULT_TTL, payload = { type = "PING_REPLY",				  message = "pong" } }
            	interfaces[incomingSide].transmit(dstCh,PRIVATE_CHANNEL,reply)
            	logInfo("Replied to PING from "..packet.src)
     		else
             	--contiue with forwarding logic
     		end
		end
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
	end

    if NAT then -- If nat is enabled do NAT translation processes
		local packetin, packetout = InorOut() -- If the packet is coming from a in or out port
		if packetout then -- Handles if packets are coming from the outside
			local portNum = packet.dst:match(":(%d+)$")
			for port,trueBNP in pairs(natTable) do
				if portNum == port then
					packet.dst = trueBNP
                    natTable[port] = nil
                    saveRouterServices()
					break
				end
			end
		elseif packetin then -- Handles if the packets are coming from the inside
			local port = tostring(NATseq)
        	natTable[port] = packet.src
        	packet.src = routerBNP..":"..port
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
	while not terminated do
		local packet = { -- Build the RDP check
			uid = makeUID(),
			src = routerBNP,
    		dst = "0",
    		ttl = DEFAULT_TTL,
    		payload = {
    			type = "RDP_REQUEST"
    		}
		}

		for _, modem in pairs(interfaces) do modem.transmit(1,1,packet) end -- Send the RDP check

		local now = os.clock()
        for neighbor, table in pairs(RDPNeighbors) do -- Cleanup for neighbors that haven't been seen for more than 20 minutes
            if now - table.lastSeen >= (600*2) then -- if it hasn't been seen for 20 minutes or more then clean out it's routing info
                for i,subnet in pairs(RDPNeighbors[neighbor].routes) do
					routingTable[subnet] = nil
				end
				RDPNeighbors[neighbor] = nil
            end
        end
        saveRouterServices()
		os.sleep(600) -- Every 10 minutes (600 seconds)
	end
end


local function cleanupSeenUIDs()
    while not terminated do
        seen = {}  -- simply clear the table
        debugPrint("Cleared seen UID cache")
        os.sleep(300) -- every 5 minutes (300 seconds)
    end
end

-- CLI
local function DLRCLI()
    local function printHelp()
    print([[DLR Commands:
        help
        whitelist
        blacklist
        deny [src,dst,disable]
        add [subnet or BNP]
		remove [subnet or BNP,all]
		exit

        to deny a subnet you must enter the
        network plus a wildcard bit (0)
        Ex: 192.168.1.0
        This denies the 192.168.1 subnet
        ]])
    end

    while true do
        io.write("(DLR)> ")
        local line = read()
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
		end
    end
end

local function RDPCLI()
	local function printHelp()
    print([[RDP Commands:
        help
		enable
		disable
		side [left,right,etc] [enable,disable]
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
        local line = read()
        if not line then break end
        local cmd,arg1,arg2 = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
        if cmd=="help" then printHelp()
        elseif cmd=="enable" then RDP = true print("Please restart device for changes to take effect") saveRouterServices()
		elseif cmd=="disable" then RDP = false print("Please restart device for changes to take effect") saveRouterServices()
		elseif cmd=="side" then
			if arg2 == "enable" then
				local ok
				for _,side in pairs(interfaces) do -- Add the interface as a RDP enabled side
					if side == arg1 then
						table.insert(RDPSides,arg1)
                        ok = true
                        print("Enabled RDP on side"..side)
                        saveRouterServices()
                        break
					end
				end
				if not ok then -- If the side isn't an interface then error
					print("Side not found, try again!")
				end
			elseif arg2 == "disable" then
                local ok
				for i,side in pairs(RDPSides) do
					if side == arg1 then
						table.remove(RDPSides,i)
                        ok = true
                        print("Disabled RDP on side"..side)
                        saveRouterServices()
                        break
					end
				end
                if not ok then -- If the side isn't a RDP enabled side then error
                    print("Side isn't enabled, try again!")
                end
			end
		elseif cmd=="exit" then
            print("Returning to Router mode")
			return
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
		exit

        For NAT to function set ALL sides
        listed with the'sides' command in 
        (Router)> mode to either in or out
        ]])
    end

    while true do
        io.write("(NAT)> ")
        local line = read()
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
				for _,side in pairs(interfaces) do -- Add the side to the inside ports group
					if side == arg1 then
						table.insert(natInsideSides,arg1)
                        print("Added side"..side.." to inside group")
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
				for _,side in pairs(interfaces) do -- Add the side to the outside ports group
					if side == arg1 then
						table.insert(natOutsideSides,arg1)
                        print("Added side"..side.." to outside group")
                        ok = true
                        saveRouterServices()
                        break
					end
				end
				if not ok then -- If the side isn't an interface then error
					print("Side not found, try again")
				end
			else
				print("Usage: side [side] [in/out] example: side left in")
			end
		elseif cmd=="exit" then
            print("Returning to Router mode")
			return
    	end
	end
end

local function cli()
    local function printHelp()
    print([[Router Commands:
        show routes
        show hosts
        show channels
        BNP set <BNP>
        add route <subnet> <side>
        del route <subnet>
        set defaultroute <side>
        sides
        NAT
        RDP
        DLR
        exit
        terminate
        help
    ]])
    end
    while not terminated do
        os.sleep(0.25)
        print("Router Version 2.22 Loading")
        os.sleep(1)
        io.write("Enter router CLI password: ")
        local input = read("*")
        if input ~= CLI_PASSWORD then
            print("Incorrect password.")
            os.sleep(1)
        else
            print("Access granted. Router CLI started.")
            while true do
                io.write("(Router)> ")
                local line = read()
                if not line then break end
                local cmd,arg1,arg2,arg3 = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
            if cmd=="help" then printHelp()
            elseif cmd=="exit" then term.clear() term.setCursorPos(1,1) cli()
            elseif cmd=="terminate" then
                print("Enter password to confirm termination:")
                local check = read("*")
                if check == CLI_PASSWORD then
                    logInfo("Router shutting down...")
                    terminated = true
                    return
                else
                    print("Incorrect password. Abort termination.")
                end
            elseif cmd=="show" then
                if arg1=="routes" then for s,t in pairs(routingTable) do print(s.." -> "..t) end
                elseif arg1=="hosts" then for h,s in pairs(hosts) do print(h.." -> "..s) end
                elseif arg1=="channels" then for BNP,ch in pairs(knownChannels) do print(BNP.." -> "..ch) end
                else print("Usage: show routes | show host | show channels") end
            elseif cmd=="BNP" and arg1=="set" and arg2~="" then
                routerBNP = arg2
                updateBNPFile()
                logInfo("Router BNP updated to "..routerBNP)
            elseif cmd=="add" and arg1=="route" and arg2~="" and arg3~="" then
                if not interfaces[arg3] then print("Invalid side: "..arg3)
                else routingTable[arg2] = arg3; logInfo("Added route "..arg2.." -> "..arg3); saveRoutingTable() end
            elseif cmd=="del" and arg1=="route" and arg2~="" then
                routingTable[arg2] = nil; logInfo("Deleted route for "..arg2); saveRoutingTable()
            elseif cmd=="set" and arg1=="defaultroute" and arg2~="" then
                if interfaces[arg2] then defaultRoute = arg2; logInfo("Default route set to "..arg2); saveRoutingTable()
                else print("Invalid side: "..arg2) end
            elseif cmd=="sides" then for s,_ in pairs(interfaces) do print("  "..s) end
            elseif cmd=="NAT" then NATCLI()
            elseif cmd=="RDP" then RDPCLI()
            elseif cmd=="DLR" then DLRCLI()
            else print("Unknown command.") end
            end
        end
    end
end

-- DLR functions
-- Subnet matching for DLR .0 means it's a subnet and should deny anything that matches before the 0
local function subnetMatch(ip, subnet)
    -- Split into number groups
    -- First check if they are an exact match
    if ip == subnet then return true end
    local function splitGroups(str)
        local t = {}
        for part in string.gmatch(str, "[^.]+") do
            table.insert(t, tonumber(part))
        end
        return t
    end
    local ipParts = splitGroups(ip)
    local netParts = splitGroups(subnet)
    -- Determine number of groups to match before first 0
    local matchCount = 0
    for i = 1, #netParts do
        if netParts[i] == 0 then break end
        matchCount = matchCount + 1
    end
    -- If there is no 0 and not exact, it's not a match
    if matchCount == #netParts then
        return false
    end
    -- Compare only required groups
    for i = 1, matchCount do
        if ipParts[i] ~= netParts[i] then
            return false
        end
    end
    return true
end

local function dLR(msg, side)
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
