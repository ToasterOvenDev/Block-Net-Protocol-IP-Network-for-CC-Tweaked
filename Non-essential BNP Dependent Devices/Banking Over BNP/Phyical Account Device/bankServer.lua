--This is a template for if you want to make your own server for my network
-- Features include multishell launch
-- Debug printing with a command to turn it on and off
-- Automatic locating of connected modems
-- Multi-channel BNP system
-- Reply to hello packets and switch hello packets
-- Receive loop to process recieved packets
-- Startup on boot

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

local DEBUG = true
local function debugPrint(msg,fileOnly)
    fileOnly = fileOnly or false
    local time = os.date("%H:%M:%S")
	local f = fs.open(debugFile,"a")
	f.writeLine("[DEBUG "..time.."] " .. msg)
	f.close()
    if fileOnly then
		return
    elseif DEBUG then
        print("[DEBUG] " .. msg)
    end
end
debugPrint("[BOOT] Started logging",true)

-- ==========================
-- FINDS MODEMS (can also find other peripherals, just add a new var and a new if for p's type)
-- ==========================
local PRIVATE_CHANNEL = os.getComputerID()
local modems = {}
local interfaces = {}
local stockTicker
local function findModems()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "modem") then
            table.insert(modems, side)
        end
		if peripheral.hasType(side, "Create_StockTicker") then
			stockTicker = peripheral.wrap(side)
			debugPrint("[VAULT] Found StockTicker",true)
		end
    end
	debugPrint("[VAULT] If StockTicker not connected full bank functionality is not possible",true)
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
        bi.open(1200)			  -- Banking Channel
    end)
    print("Opened public modem on side "..publicInterface.." (channels 1 + "..PRIVATE_CHANNEL)
    print("Opened bank modem on side "..bankInterface.." (channels 1200)")

    if next(interfaces) == nil then error("No modems found!") end
end

-- CONFIGURATION VARIABLES
local accntFee = -50 -- A negitive number that represents the cost of creating an account
local BNP_FILE = "BNP.txt"
local myBNP
local routerChannel = 1
local SERVERNAME = "bankServer.lua"
local serverConfigs = { usernames = {}, cardsRegistered = 0, publicSide = "back" }
local configFile = "bankServer.config"

-- ==========================
-- LOAD OR CREATE BNP
-- ==========================
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

local function saveConfigs()
	local f = fs.open(configFile,"w")
    f.writeLine(textutils.serialize(serverConfigs))
    f.close()
end

if not fs.exists(configFile) then
	local f = fs.open(configFile,"w")
	f.write("")
	f.close()
else
	local f = fs.open(configFile,"r")
	local config = textutils.unserialise(f.readAll())
	debugPrint("[CONFIG]"..textutils.serialize(config),true)
	if config == "" then
		serverConfigs = {
			usernames = {},
			cardsRegistered = 0,
			publicSide = "back",
		}
	else
		serverConfigs.usernames = config.usernames
		serverConfigs.cardsRegistered = config.cardsRegistered
		serverConfigs.publicSide = config.publicSide
	end
end

-- Load public interface
if serverConfigs.publicSide ~= publicInterface then
 	-- If the loaded public side is not the publicInterface then search the located modems for the public Side and set up interfaces
	debugPrint("Attempting to find loaded public side")
	for i, side in pairs(modems) do
		if serverConfigs.publicSide == side then
			debugPrint("Public side found setting up...")
			bankInterface = publicInterface
			publicInterface = modems[i]
			setUpInterfaces()
			break
		end
	end
else
	setUpInterfaces() -- If the loaded public side is already the publicInterface then just setup the interfaces
end

-- ==========================
-- PACKET UTILITIES
-- ==========================

local function xor(data, key) --Simple Encription/Decryption
    local out = {}
    for i = 1, #data do
        local db = string.byte(data, i)
        local kb = string.byte(key, (i - 1) % #key + 1)
        out[i] = string.char(bit32.bxor(db, kb))
    end
    return table.concat(out)
end

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
    local packet = { uid=makeUID(), src=myBNP, dst=dst, ttl=64, payload=payload }
    interfaces[publicInterface].transmit(routerChannel, PRIVATE_CHANNEL, packet)
end

local function sendBankNetwork(dst,payload)
	if not myBNP then
        print("Set your BNP first with 'set BNP <BNP>' before sending packets.")
        return
    end
    local packet = { uid=makeUID(), src=myBNP, dst=dst, ttl=64, payload=payload }
    interfaces[bankInterface].transmit(1200, 1200, packet)
end

local function broadcast(payload)
    local packet = { uid=makeUID(), src=myBNP or "unknown", dst="0", ttl=64, payload=payload }
    publicInterface.transmit(1,1,packet)
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
-- ==========================
-- RECEIVE LOOP
-- ==========================

local function receiveLoopBank(packet,side)
    if type(packet)=="table" and myBNP and (packet.dst==myBNP or packet.dst=="0") then
		debugPrint("Valid Packet, processing",true)
        local payload = packet.payload
		local username
		if payload.user then
			username = serverConfigs.usernames[payload.user]
			debugPrint("Direct Username and Pass provided, no need to translate card number and pin")
		elseif payload.card then
			debugPrint("Finding card num and matching to provided card")
			for user, info in pairs(serverConfigs.usernames) do
				if info.cardNum == payload.card then
					username = serverConfigs.usernames[user]
					debugPrint("Found card")
					break
				end
			end
		end
		if payload.card and username.cardNum == payload.card and username.pin == payload.pin then
			debugPrint("Card number and Pin are correct, translating password")
			payload.pass = username.pass
		end
        if type(payload)~="table" then
            debugPrint("Invalid payload from "..tostring(packet.src))
			return
        else
			if payload.type == "LOGIN_ATTEMPT" then
				debugPrint("Login attempt with username: "..payload.user.." and password: "..payload.pass)
				local response
				if not username then
					response = { type = "LOGIN_RESP", confirm = "Void" }
					sendBankNetwork(packet.src,response) --Say user not found
					debugPrint("Login attempt failed, user not found")
					return
				elseif payload.pass == username.pass then
					response = { type = "LOGIN_RESP", confirm = "Allow", accountInfo = username }
					sendBankNetwork(packet.src,response) --Say login succeeds
					debugPrint("Login attempt succeeded")
					return
				else
					response = { type = "LOGIN_RESP", confirm = "Deny" }
					sendBankNetwork(packet.src,response) --Say login failed
					debugPrint("Login attempt failed, password incorrect")
					return
				end
			elseif payload.type == "ACCT_CREATE_REQ" then
				if not username then
					serverConfigs.usernames[payload.user] = { pass = payload.pass, balance = accntFee, transactions = {"Created Account -50"} }
					sendBankNetwork(packet.src, { type="ACCT_CREATED", accountInfo = serverConfigs.usernames[payload.user] } )
					debugPrint("Account created username: "..payload.user)
					saveConfigs()
				else
					sendBankNetwork(packet.src, { type="ERROR", message="Username already taken, try a different username" } )
					debugPrint("Account request denied username: "..payload.user)
				end
			elseif payload.type == "BALANCE_REQUEST" then
				if payload.pass ~= username.pass then return end
				debugPrint("Balance request sent to "..payload.user)
				local response = { type="BALANCE_RESP", balance = username.balance }
				sendBankNetwork(packet.src,response)
			elseif payload.type == "BALANCE_UPDATE" then
				if payload.pass ~= username.pass then return end
				local amount
				local transaction
				if payload.deposit then
					debugPrint("Deposit accepted for "..tostring(payload.deposit).." User: "..payload.user)
					amount = payload.deposit
					username.balance = username.balance + amount
					transaction = "Deposit of "..tostring(amount)
					--[[ Idea to confirm a deposit is real 
						Make a listener device (possibly a function within the bankServer file) that is connected to a stockTicker that all ATMs and Bank Tellers send their deposits
						This listener will wait for the package_received event and once it does it will fire a custom event called "payment_received"
						the payment_received event will have the amount of money within the package along with the address of the package

						When a deposit packet is recieved from an ATM or BT the bankServer will save the ATM or BT's address, user, and deposit amount into a table and once the payment_received event
						is fired (or a packet if the device is seperate) they will subtract the amount in the fired event from the deposit amount saved in the table until the entire amount has been reached
						which then it will update the account info and send a confirmation to the ATM

						This system may make it possible to have a public deposit
					]]
				elseif payload.withdrawl then
					if username.balance >= payload.withdrawl and username.balance > 0 then -- we make sure the account has enough and isn't negitive
						debugPrint("Withdrawl accepted for "..tostring(payload.deposit).." User: "..payload.user)
						amount = payload.withdrawl * -1
						username.balance = username.balance + amount
						transaction = "Withdrawl for "..tostring(amount)
						--Next use a stock ticker to send a package of the amount to the ATM that sent the withdrawl
					else
						debugPrint("Withdrawl denied for "..tostring(payload.deposit).." User: "..payload.user)
						sendBankNetwork(packet.src,{ type="ERROR", message="Not enough in balance for withdrawl, Balance: ".." Withdrawl amount: "..payload.withdrawl } )
						return
					end
				end
				if #username.transactions > 25 then
					table.remove(username.transactions)
				end
				table.insert(username.transactions, 1, transaction)
				saveConfigs()
			elseif payload.type == "WIRE_TRANSFER" then
				if payload.pass ~= username.pass then return end
				local srcAcct = username.balance
				local dstAcct = serverConfigs.usernames[payload.wireDst]
				local transaction
				if not dstAcct then sendBankNetwork(packet.src,{ type="ERROR", message="Destination account does not exist" } ) return end
				if srcAcct >= payload.amount and srcAcct > 0 then -- we make sure the account has enough and isn't negitive
					srcAcct = srcAcct - payload.amount
					dstAcct.balance = dstAcct.balance + payload.amount
					debugPrint("Source User: "..payload.user.." Destination User: "..payload.wireDst.." Amount: "..payload.amount)
				else
					sendBankNetwork(packet.src,{ type="ERROR", message="Not enough balance" } )
					debugPrint("Failed to wire from "..payload.user.."to "..payload.wireDst)
					return
				end
				transaction = payload.wireDst.." "..tostring(payload.amount *-1)
				if #username.transactions > 25 then
					table.remove(username.transactions)
				end
				table.insert(username.transactions, 1, transaction)
				transaction = payload.user.." +"..payload.amount
				if #dstAcct.transactions > 25 then
					table.remove(dstAcct.transactions)
				end
				table.insert(dstAcct.transactions, 1, transaction)
				saveConfigs()
			elseif payload.type == "REGISTER_PIN" then
				if payload.pass ~= username.pass then return end
				-- This will register a "card" number and a pin for that number (I may come up with a way to read a physical card later)
				if payload.register then
					local cardNum = tostring(serverConfigs.cardsRegistered+1200)
					username.cardNum = cardNum
					username.pin = payload.pin
					sendBankNetwork(packet.src, {type="PIN_RESP", cardNum = cardNum} )
					debugPrint("Card registered for "..payload.user)
				elseif payload.change then
					username.pin = payload.pin
					sendBankNetwork(packet.src, {type="PIN_RESP", changed = true} )
					debugPrint("Card changed for "..payload.user)
				end
				saveConfigs()
            else
                debugPrint(("Unknown Packet Type from %s: %s"):format(packet.src, textutils.serialize(payload)))
				return
            end
        end
	else
		debugPrint("Invalid Packet")
    end
end

local function receiveLoopPublic(packet,side)
    if type(packet)=="table" and myBNP and (packet.dst==myBNP or packet.dst=="0") then
        local payload = packet.payload
		local username
		if payload.user then
			username = serverConfigs.usernames[payload.user]
		end
		if payload.card and username.cardNum == payload.card and username.pin == payload.pin then
			payload.pass = username.pass
		end
        if type(payload)~="table" then
            debugPrint("Invalid payload from "..tostring(packet.src))
			return
        else
            if payload.type == "HELLO_REQUEST" then
                replyHello(packet.src, payload.private_channel)
				return
            elseif payload.type == "S_H" then
                switchReply(side,packet)
                routerChannel = payload.private_channel -- Always overrides previous routerchannel to make network expansion easier
				return
            elseif payload.type == "PING" then
                debugPrint("Received PING from "..packet.src)
                sendPacket(packet.src,{ type="PING_REPLY", message="pong" })
				return
			-- End of networking packets, start of Banking packets
			elseif payload.type == "LOGIN_ATTEMPT" then
				debugPrint("Login attempt with username: "..payload.user.." and password: "..payload.pass)
				local response
				if not username then
					response = { type = "LOGIN_RESP", confirm = "Void" }
					sendPacket(packet.src,response) --Say user not found
					return
				elseif payload.pass == username.pass then
					response = { type = "LOGIN_RESP", confirm = "Allow", balance = username.bal, transactions = username.transactions }
					sendPacket(packet.src,response) --Say login succeeds
					return
				else
					response = { type = "LOGIN_RESP", confirm = "Deny" }
					sendPacket(packet.src,response) --Say login failed
					return
				end
			elseif payload.type == "ACCT_CREATE_REQ" then
				if not username then
					username = { pass = payload.password, balance = accntFee, transactions = {} }
					saveConfigs()
				else
					sendPacket(packet.src, { type="ERROR", message="Username already taken, try a different username" } )
				end
			-- After Login packets
			elseif payload.type == "BALANCE_REQUEST" then
				if payload.pass ~= username.pass then return end
				local response = { type="BALANCE_RESP", balance = username.balance }
				response = xor(response,packet.uid:match("%-(%d+)$")) -- Use src computerID as encryption key
				sendPacket(packet.src,response) -- Send data encrypted
				return
			elseif payload.type == "BALANCE_UPDATE" then
				if payload.pass ~= username.pass then return end
				local amount
				if payload.deposit then
					amount = payload.deposit
					username.balance = username.balance + payload.deposit
				elseif payload.withdrawl then
					if username.balance >= payload.withdrawl then
						amount = payload.withdrawl * -1
						username.balance = username.balance - payload.withdrawl
						--Next use a stock ticker to send a package of the amount to the ATM that sent the withdrawl
					else
						sendPacket(packet.src,{ type="ERROR", message="Not enough in balance for withdrawl" } )
						return
					end
				end
				if #username.transactions > 25 then
					table.remove(username.transactions,1)
				end
				table.insert(username.transactions,amount)
				saveConfigs()
			elseif payload.type == "WIRE_TRANSFER" then
				if payload.pass ~= username.pass then return end
				local srcAcct = username.balance
				local dstAcct = serverConfigs.usernames[payload.wireDst]
				if not dstAcct then sendPacket(packet.src,{ type="ERROR", message="Destination account does not exist" } ) return end
				if srcAcct >= payload.amount then
					srcAcct = srcAcct - payload.amount
					dstAcct.balance = dstAcct.balance + payload.amount
				else
					sendPacket(packet.src,{ type="ERROR", message="Not enough balance" } )
				end
				local amount = payload.amount *-1
				if #username.transactions > 25 then
					table.remove(username.transactions,1)
				end
				table.insert(username.transactions,amount)
				saveConfigs()
			elseif payload.type == "REGISTER_PIN" then
				if payload.pass ~= username.pass then return end
				-- This will register a "card" number and a pin for that number (I may come up with a way to read a physical card later)
				if payload.register then
					local cardNum = tostring(serverConfigs.cardsRegistered+1200)
					username.cardNum = cardNum
					username.pin = payload.pin
					sendPacket(packet.src, {type="PIN_RESP", cardNum = cardNum} )
				elseif payload.change then
					username.pin = payload.pin
					sendPacket(packet.src, {type="PIN_RESP", changed = true} )
				end
				saveConfigs()
            else
                debugPrint(("Message from %s: %s"):format(packet.src, textutils.serialize(payload)))
				return
            end
        end
    end
end

local function listener()
    while true do
        local _, side, _, _, msg = os.pullEvent("modem_message")
		if side == bankInterface then
			--[[
			Idea: make a security feature where a ATM registration process occurs
			one the bankServer has a password needed to register an ATM
			two the bank gives the ATM an encrypted key and adds that key to a registered ATM's table
			if the packet comes from the bank side the bank checks registered ATMs and discards the packet if it hasn't come from a registered ATM
			This can prevent a malisious user from faking a large balance by just gaining access to the bank network wires
        	]]
			debugPrint("Packet from bank interface")
			receiveLoopBank(msg,side)
		elseif side == publicInterface then
			debugPrint("Packet from public interface")
			receiveLoopPublic(msg,side)
		end
    end
end
-- ==========================
-- CLI LOOP
-- ==========================
local function cliLoop()
    print("Server ready. Commands: set BNP [BNP], BNP, setpublicinterface [interface], exit")
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
        elseif cmd=="BNP" then print("Current BNP: "..tostring(myBNP))
		elseif cmd == "setpublicinterface" then --> Set interfaces, public side and private side
            for i,side in ipairs(modems) do
                if side == args[2] and publicInterface ~= modems[i] then -- Change public interface
                    bankInterface = publicInterface
                    publicInterface = modems[i]
                    print("public interface set to:", publicInterface)
					interfaces[publicInterface].closeAll()
					interfaces[bankInterface].closeAll()
					setUpInterfaces()
                    break
                elseif side == args[2] and publicInterface == modems[i] then -- Already public interface
                    print("Interface is already set as public.")
                    break
                end
            end
			serverConfigs.publicSide = args[2]
			saveConfigs()
		elseif cmd=="reset-atms" then
			sendBankNetwork(0,{ type="RESET" })
        elseif cmd=="debugmode" and args[2] then
            if args[2] == "true" then
                DEBUG = true
           	elseif args[2] == "false" then
                DEBUG = false
			end
        else
            print("Commands: set BNP [BNP],  BNP, setpublicinterface [interface], exit")
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

parallel.waitForAny(listener, cliLoop)
