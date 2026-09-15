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
local packager
local function findModems()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side, "modem") then
            table.insert(modems, side)
        end
		if peripheral.hasType(side, "Create_StockTicker") then
			stockTicker = peripheral.wrap(side)
			debugPrint("[VAULT] Found StockTicker",true)
		end
		if peripheral.hasType(side, "Create_Packager") then
			packager = peripheral.wrap(side)
			debugPrint("[VAULT] Found Packager")
		end
    end
	if not stockTicker then
		debugPrint("[VAULT] If StockTicker not connected full bank functionality is not possible")
	end
	if not packager then
		debugPrint("[VAULT] If Packager not connected full bank functionality is not possible")
	end
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
local serverConfigs = { usernames = {}, cardsRegistered = 0, publicSide = "back", deposits = {} }
local configFile = "bankServer.config"
local values = { -- [[ replace this table with your own currency system (this is the lightman's currency system, link to mod in Readme)
    		["coin_copper"] = 0.01,
    		["coinpile_copper"] = 0.09,
    		["coinblock_copper"] = 0.36,
    		["coin_iron"] = 0.10,
    		["coinpile_iron"] = 0.90,
			["coinblock_iron"] = 3.60,
			["coin_gold"] = 1.00,
    		["coinpile_gold"] = 9.00,
    		["coinblock_gold"] = 36.00,
    		["coin_emerald"] = 10.00,
    		["coinpile_emerald"] = 90.00,
    		["coinblock_emerald"] = 360.00,
    		["coin_diamond"] = 100.00,
    		["coinpile_diamond"] = 900.00,
    		["coinblock_diamond"] = 3600.00,
    		["coin_netherite"] = 1000.00,
    		["coinpile_netherite"] = 9000.00,
    		["coinblock_netherite"] = 36000.00
		}
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
	if config == "" or config == nil then
		serverConfigs = {
			usernames = {},
			cardsRegistered = 0,
			publicSide = "back",
			deposits = {}
		}
	else
		serverConfigs.usernames = config.usernames
		serverConfigs.cardsRegistered = config.cardsRegistered
		serverConfigs.publicSide = config.publicSide
		serverConfigs.deposits = config.deposits
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

local function withdrawl(total, address)
	-- Reverse of add up returns a table that can be used as a filter for create Stock Ticker
	debugPrint("[WITHDRAWL] Trying to withdrawl "..total)
	local coins = {
		{name = "coinblock_netherite", amount = 0},
		{name = "coinpile_netherite", amount = 0},
		{name = "coin_netherite", amount = 0},
		{name = "coinblock_diamond", amount = 0},
		{name = "coinpile_diamond", amount = 0},
		{name = "coin_diamond", amount = 0},
		{name = "coinblock_emerald", amount = 0},
		{name = "coinpile_emerald", amount = 0},
		{name = "coin_emerald", amount = 0},
		{name = "coinblock_gold", amount = 0},
		{name = "coinpile_gold", amount = 0},
		{name = "coin_gold", amount = 0},
		{name = "coinblock_iron", amount = 0},
		{name = "coinpile_iron", amount = 0},
		{name = "coin_iorn", amount = 0},
		{name = "coinblock_copper", amount = 0},
		{name = "coinpile_copper", amount = 0},
		{name = "coin_copper", amount = 0}
	}
	for _,coin in ipairs(coins) do
		while(total>=values[coin.name]) do
			total = total - values[coin.name]
			coin.amount = coin.amount + 1
			debugPrint("Adding one "..coin.name.." To package")
		end
	end
	-- At this point the coins table will have what needs to be sent to the withdrawler
	for _,coin in ipairs(coins) do
		if coin.amount > 0 then
			stockTicker.requestFiltered(address,{ name = "lightmanscurrency:"..coin.name, _requestCount = coin.amount })
			debugPrint("Requesting package of "..coin.name)
		end
	end

end

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
	debugPrint("Sending payload: "..textutils.serialize(payload))
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
		local userCard
		if payload.user then
			username = serverConfigs.usernames[payload.user]
			debugPrint("Direct Username and Pass provided, no need to translate card number and pin")
		elseif payload.card then
			debugPrint("Finding card num and matching to provided card")
			for user, info in pairs(serverConfigs.usernames) do
				if info.cards then
					debugPrint("Checking cards for "..user)
					for _,cardData in pairs(info.cards) do
						if cardData.cardNum == payload.cardNum then
							debugPrint("Found Card: "..textutils.serialize(cardData))
							username = serverConfigs.usernames[user]
							payload.user = user
							userCard = cardData
							break
						end
					end
					if username then
						debugPrint("Found card")
						break
					end
				end
			end
			if payload.card == userCard.cardNBT and userCard.pin == payload.pin then
				debugPrint("Card NBT and Pin are correct, translating password")
				payload.pass = username.pass
			else
				debugPrint("Card NBT and Pin are not Correct, exiting")
				sendBankNetwork(packet.src,{type = "LOGIN_RESP", confirm = "Deny"}) --Say login failed
				return
			end
		end
		debugPrint("Payload type is "..payload.type)
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
					response = { type = "LOGIN_RESP", confirm = "Allow", accountInfo = username, name = payload.user } -- We send payload.user so that when you login with a card the Username can be displayed
					debugPrint("Response: "..textutils.serialize(response))
					sendBankNetwork(packet.src,response) --Say login succeeds
					debugPrint("Login attempt succeeded"..packet.src)
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
			elseif payload.type == "BALANCE_UPDATE" then
				if payload.pass ~= username.pass then debugPrint("[BALANCE_UPDATE] Failed password check") return end
				debugPrint("Got an Balance Update packet")
				local amount
				local transaction
				if payload.deposit then
					local originAddress = "ATM "..packet.src
					if payload.bankTeller then
						originAddress = "BT "..packet.src
					end
					debugPrint("[DEPOSIT] Inserting deposit into background deposits")
					local depositTable = { user = payload.user, amount = payload.deposit, address = originAddress, src = packet.src, amountDelivered = 0, public=false }
					table.insert(serverConfigs.deposits,depositTable)
				elseif payload.withdrawl then
					if username.balance >= payload.withdrawl then
						debugPrint("Withdrawl accepted for "..tostring(payload.withdrawl).." User: "..payload.user)
						amount = payload.withdrawl * -1
						username.balance = username.balance + amount
						transaction = "Withdrawl for "..tostring(amount)

						local returnAddress = "ATM "..packet.src
						if payload.bankTeller then
							returnAddress = "BT "..packet.src
						end
						withdrawl(payload.withdrawl,returnAddress)
					else
						debugPrint("Withdrawl denied for "..tostring(payload.deposit).." User: "..payload.user)
						sendBankNetwork(packet.src,{ type="ERROR", message="Not enough in balance for withdrawl, Balance: "..username.balance.." Withdrawl amount: "..payload.withdrawl } )
						return
					end
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					saveConfigs()
					sendBankNetwork(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
				else
					debugPrint("Invalid Balance Update "..textutils.serialize(payload))
				end
			elseif payload.type == "WITHDRAWL" then -- Packet type for specific withdrawl (User defines the coins sent to them)
				if payload.pass ~= username.pass then debugPrint("[BALANCE_UPDATE] Failed password check") return end
				local transaction
				local total = 0
				debugPrint("[WITHDRAWL] Trying to find total from specific withdrawl request")
				for _,coin in pairs(payload.request) do -- {name="coin_copper,amount=5}
					local value = values[coin.name]
					total = value*coin.amount
				end
				debugPrint("[WITHDRAWL] Found total: "..tostring(total))
				if username.balance >= total then
					debugPrint("[WITHDRAWL] Refromatting request to appropriate form for Stock Ticker and requesting")
					for _,coin in pairs(payload.request) do
						stockTicker.requestFiltered(payload.address,{name="lightmanscurrency:"..coin.name,_requestCount=coin.amount})
					end
					transaction = "Withdrawl for "..tostring(total)
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					saveConfigs()
					sendBankNetwork(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
				else
					sendBankNetwork(packet.src,{type="ERROR", message="Not enough for withdrawl, Balance: "..username.balance.." Withdrawl amount: "..total})
				end
			elseif payload.type == "WIRE_TRANSFER" then
				if payload.pass ~= username.pass then return end
				local srcAcct = username.balance
				local dstAcct = serverConfigs.usernames[payload.wireDst]
				local transaction
				if not dstAcct then sendBankNetwork(packet.src,{ type="ERROR", message="Destination account does not exist" } ) return end
				if srcAcct >= payload.amount then
					username.balance = username.balance - payload.amount
					dstAcct.balance = dstAcct.balance + payload.amount
					debugPrint("Source User: "..payload.user.." Destination User: "..payload.wireDst.." Amount: "..tostring(payload.amount))
					transaction = payload.wireDst.." wire transfer of $"..tostring(payload.amount *-1)
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					transaction = "wire transfer from"..payload.user.." of $"..tostring(payload.amount)
					if #dstAcct.transactions > 25 then
						table.remove(dstAcct.transactions,#username.transactions)
					end
					table.insert(dstAcct.transactions,1, transaction)
					saveConfigs()
					sendBankNetwork(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
				else
					sendBankNetwork(packet.src,{ type="ERROR", message="Not enough balance" } )
					debugPrint("Failed to wire from "..payload.user.."to "..payload.wireDst)
					return
				end
			elseif payload.type == "REGISTER_PIN" then
				if payload.pass ~= username.pass then debugPrint("[CARD] Password not correct!") return end
				-- This will register a "card" number and a pin for that number (I may come up with a way to read a physical card later)
				debugPrint("Either registering or changing a card!")
				if payload.register then
					debugPrint("Trying to register a card")
					local randInt = math.random(1,8799)
					debugPrint("Random Int is: "..tostring(randInt))
					local cardNum = tostring(1200+randInt)..tostring(serverConfigs.cardsRegistered)
					serverConfigs.cardsRegistered = serverConfigs.cardsRegistered + 1
					if not serverConfigs.usernames[payload.user].cards then
						serverConfigs.usernames[payload.user].cards = {}
					end
					table.insert(serverConfigs.usernames[payload.user].cards, { cardNum = cardNum, pin = payload.pinNum })
					sendBankNetwork(packet.src, {type="PIN_RESP", cardNum = cardNum, cards = serverConfigs.usernames[payload.user].cards} )
					debugPrint("Card registered for "..payload.user)
				elseif payload.change then
					debugPrint("Trying to change a pin")
					local cIndex
					for i,cData in pairs(username.cards) do
						debugPrint("Looking for "..tostring(payload.cardNum))
						if cData.cardNum == payload.cardNum then
							debugPrint("Found "..tostring(cData.cardNum).." the index is: "..tostring(i))
							cIndex = i
						end
					end
					debugPrint("Found Card changing the pin at Index: "..tostring(cIndex))
					serverConfigs.usernames[payload.user].cards[cIndex].pin = payload.pinNum
					sendBankNetwork(packet.src, {type="PIN_RESP", changed = true, newPin = serverConfigs.usernames[payload.user].cards[cIndex].pin, cards = serverConfigs.usernames[payload.user].cards} )
					debugPrint("Card changed for "..payload.user)
				elseif payload.disable then
					debugPrint("Finding card to disable")
					debugPrint("Looking for "..tostring(payload.cardNum).."to disable")
					for i,cData in pairs(username.cards) do
						if cData.cardNum == payload.cardNum then
							serverConfigs.usernames[payload.user].cards[i] = nil
							sendBankNetwork(packet.src, {type="PIN_RESP", cardNum = cData.cardNum, cards = serverConfigs.usernames[payload.user].cards, removed = true} )
						end
					end
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
        debugPrint("Valid packet, processing, true")
        local payload = packet.payload
		local username
		local userCard
		if payload.user then
			username = serverConfigs.usernames[payload.user]
			debugPrint("Direct Username and Pass provided, no need to translate card number and pin")
		elseif payload.card then
			debugPrint("Finding card num and matching to provided card")
			for user, info in pairs(serverConfigs.usernames) do
				if info.cards then
					for card,cardData in pairs(info.cards) do
						if cardData.cardNum == payload.cardNum then
							username = serverConfigs.usernames[user]
							payload.user = user
							userCard = cardData
							break
						end
					end
					if username then
						debugPrint("Found card")
						break
					end
				end
			end
			if payload.card == userCard.cardNBT and userCard.pin == payload.pin then
				debugPrint("Card number and Pin are correct, translating password")
				payload.pass = username.pass
			else
				sendPacket(packet.src,{type = "LOGIN_RESP", confirm = "Deny"}) --Say login failed
			end
		end
		debugPrint("Payload type is "..payload.type)
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
                    debugPrint("Login attempt failed, user not found")
					return
				elseif payload.pass == username.pass then
					response = { type = "LOGIN_RESP", confirm = "Allow", accountInfo = username, name = payload.user } -- We send payload.user so that when you login with a card the Username can be displayed
					sendPacket(packet.src,response) --Say login succeeds
                    debugPrint("Login attempt succeeded")
					return
				else
					response = { type = "LOGIN_RESP", confirm = "Deny" }
					sendPacket(packet.src,response) --Say login failed
                    debugPrint("Login attempt failed, password incorrect")
					return
				end
			elseif payload.type == "ACCT_CREATE_REQ" then
				if not username then
					serverConfigs.usernames[payload.user] = { pass = payload.pass, balance = accntFee, transactions = {"Created Account -50"} }
					sendPacket(packet.src, { type="ACCT_CREATED", accountInfo = serverConfigs.usernames[payload.user] } )
					debugPrint("Account created username: "..payload.user)
					saveConfigs()
				else
					sendPacket(packet.src, { type="ERROR", message="Username already taken, try a different username" } )
                    debugPrint("Account request denied username: "..payload.user)
				end
			-- After Login packets
			elseif payload.type == "BALANCE_REQUEST" then
				if payload.pass ~= username.pass then return end
				local response = { type="BALANCE_RESP", balance = username.balance }
				response.balance = xor(response.balance,packet.uid:match("%-(%d+)$")) -- Use src computerID as encryption key
				sendPacket(packet.src,response) -- Send data encrypted
				return
			elseif payload.type == "BALANCE_UPDATE" then
				if payload.pass ~= username.pass then debugPrint("[BALANCE_UPDATE] Failed password check") return end
				local amount
                local transaction
				if payload.deposit then
					debugPrint("[DEPOSIT] Inserting deposit into background deposits")
					local depositTable = { user = payload.user, amount = payload.deposit, address = packet.src, src = packet.src, amountDelivered = 0, public=true }
                    table.insert(serverConfigs.deposits,depositTable)
				elseif payload.withdrawl then
					if username.balance >= payload.withdrawl then
						debugPrint("Withdrawl accepted for "..tostring(payload.withdrawl).." User: "..payload.user)
						amount = payload.withdrawl * -1
						username.balance = username.balance + amount
						transaction = "Withdrawl for "..tostring(amount)

						local returnAddress = packet.src
						withdrawl(payload.withdrawl,returnAddress)
					else
						debugPrint("Withdrawl denied for "..tostring(payload.deposit).." User: "..payload.user)
						sendPacket(packet.src,{ type="ERROR", message="Not enough in balance for withdrawl, Balance: ".." Withdrawl amount: "..payload.withdrawl } )
						return
					end
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					saveConfigs()
					sendPacket(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
                else
                    debugPrint("Invalid Balance Update "..textutils.serialize(payload))
				end
			elseif payload.type == "WITHDRAWL" then -- Packet type for specific withdrawl (User defines the coins sent to them)
				if payload.pass ~= username.pass then debugPrint("[BALANCE_UPDATE] Failed password check") return end
				local transaction
				local total = 0
				debugPrint("[WITHDRAWL] Trying to find total from specific withdrawl request")
				for _,coin in pairs(payload.request) do -- {name="coin_copper,amount=5}
					debugPrint("[WITHDRAWL] looking up value")
					local value = values[coin.name]
					debugPrint("[WITHDRAWL] adding to total")
					total = value*coin.amount
				end
				debugPrint("[WITHDRAWL] Found total: "..tostring(total))
				if username.balance >= total then
					debugPrint("[WITHDRAWL] Refromatting request to appropriate form for Stock Ticker and requesting")
					for _,coin in pairs(payload.request) do
						stockTicker.requestFiltered(payload.address,{name="lightmanscurrency:"..coin.name,_requestCount=coin.amount})
					end
					debugPrint("[WITHDRAWL] Adding to transaction list")
					transaction = "Withdrawl for "..tostring(total)
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					saveConfigs()
					sendPacket(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
				else
					sendPacket(packet.src,{type="ERROR", message="Not enough for withdrawl, Balance: "..username.balance.." Withdrawl amount: "..total})
				end
			elseif payload.type == "WIRE_TRANSFER" then
				if payload.pass ~= username.pass then return end
				local srcAcct = username.balance
				local dstAcct = serverConfigs.usernames[payload.wireDst]
				local transaction
				if not dstAcct then sendPacket(packet.src,{ type="ERROR", message="Destination account does not exist" } ) return end
				if srcAcct >= payload.amount then
					username.balance = username.balance - payload.amount
					dstAcct.balance = dstAcct.balance + payload.amount
					debugPrint("Source User: "..payload.user.." Destination User: "..payload.wireDst.." Amount: "..tostring(payload.amount))
					transaction = payload.wireDst.." wire transfer of $"..tostring(payload.amount *-1)
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					transaction = "wire transfer from"..payload.user.." of $"..tostring(payload.amount)
					if #dstAcct.transactions > 25 then
						table.remove(dstAcct.transactions,#username.transactions)
					end
					table.insert(dstAcct.transactions,1, transaction)
					saveConfigs()
					sendPacket(packet.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
				else
					sendPacket(packet.src,{ type="ERROR", message="Not enough balance" } )
					debugPrint("Failed to wire from "..payload.user.."to "..payload.wireDst)
					return
				end
			elseif payload.type == "REGISTER_PIN" then
				if payload.pass ~= username.pass then debugPrint("[CARD] Password not correct!") return end
				-- This will register a "card" number and a pin for that number (I may come up with a way to read a physical card later)
				debugPrint("Either registering or changing a card!")
				if payload.register then
					debugPrint("Trying to register a card")
					local randInt = math.random(1,8799)
					debugPrint("Random Int is: "..tostring(randInt))
					local cardNum = tostring(1200+serverConfigs.cardsRegistered+randInt)
					serverConfigs.cardsRegistered = serverConfigs.cardsRegistered + 1
					table.insert(serverConfigs.usernames[payload.user].cards, { cardNum = cardNum, pin = payload.pinNum })
					sendPacket(packet.src, {type="PIN_RESP", cardNum = cardNum, cards = serverConfigs.usernames[payload.user].cards} )
					debugPrint("Card registered for "..payload.user)
				elseif payload.change then
					debugPrint("Trying to change a pin")
					local cIndex
					for i,cData in pairs(username.cards) do
						debugPrint("Looking for "..tostring(payload.cardNum))
						if cData.cardNum == payload.cardNum then
							debugPrint("Found "..tostring(cData.cardNum).." the index is: "..tostring(i))
							cIndex = i
						end
					end
					debugPrint("Found Card changing the pin at Index: "..tostring(cIndex))
					serverConfigs.usernames[payload.user].cards[cIndex].pin = payload.pinNum
					sendPacket(packet.src, {type="PIN_RESP", changed = true, newPin = serverConfigs.usernames[payload.user].cards[cIndex].pin, cards = serverConfigs.usernames[payload.user].cards} )
					debugPrint("Card changed for "..payload.user)
				end
				saveConfigs()
            else
                debugPrint(("Message from %s: %s"):format(packet.src, textutils.serialize(payload)))
				return
            end
        end
    else
        debugPrint("Invalid packet")
    end
end

local function listener()
    while true do
        local _, side, _, _, msg = os.pullEvent("modem_message")
		if side == bankInterface then
        	debugPrint("Packet from bank interface")
			receiveLoopBank(msg,side)
		elseif side == publicInterface then
			debugPrint("Packet from public interface")
			receiveLoopPublic(msg,side)
		end
    end
end

local function checkForCard(pkg,address) -- Handles if someone sent a card to the bank, also returns false if a card is not found
	debugPrint("Checking package for card")
	local card = pkg.getItemDetail(1)
	if card.name ~= "minecraft:written_book" then
		debugPrint("Package first slot is not a written book therefore no card")
		return false
	end
	local itemName = card["displayName"]
	debugPrint("Finding card in database, CardNum: "..itemName)
	for user,data in pairs(serverConfigs.usernames) do
		if data.cards then
			debugPrint("Cards Table found for user: "..user)
			debugPrint("Cards table: "..textutils.serialize(data.cards))
			for _,cardData in pairs(data.cards) do
				debugPrint("Card: "..textutils.serialize(cardData))
				if cardData.cardNum == itemName and not cardData.cardNBT then
					debugPrint(textutils.serialize(card))
					cardData.cardNBT = card.nbt
					saveConfigs()
					debugPrint("Card was found, saving NBT data and queuing return")
					os.queueEvent("return_card",card.nbt,address)
					return true
				elseif cardData.cardNum == itemName and cardData.cardNBT then
					debugPrint("Card already has stored NBT data, queuing return")
					os.queueEvent("return_card",card.nbt,address)
				end
			end
		end
	end
	debugPrint("Card was not found returning false")
	return false
end

local function depositConfirmLoop()
	local function addUp(list)
		local content = {}
    	for _, item in pairs(list) do
        	local iname = item.name:match(":(.+)")
        	if content[iname] then
            	content[iname] = content[iname]+item.count
        	else
            	content[iname] = item.count -- { ["coin_copper"] = 64 }
       		end
    	end
		local total = 0
		for item, amount in pairs(content) do
			total = total + (amount*values[item])
		end
		return total
	end
	while true do
		local _,_,pkg = os.pullEvent("package_received")
		local address = pkg.getAddress():match("^Bank%s+(.+)$")
		if not checkForCard(pkg,address) then
			local dep
			local depIndex
			debugPrint("[DEPOSIT] Trying to match package to a deposit in deposits table, Address: "..address)
			for i, deposit in ipairs(serverConfigs.deposits) do
				if deposit.address == address then
					dep = deposit
					depIndex = i
				end
			end
			if dep then
				local username = serverConfigs.usernames[dep.user]
				debugPrint("[DEPOSIT] Found a match checking value and adding to amount delivered")
				local packageValue = addUp(pkg.list())
				serverConfigs.deposits[depIndex].amountDelivered = dep.amountDelivered + packageValue
				if serverConfigs.deposits[depIndex].amountDelivered >= dep.amount then -- If somehow more is delivered than expected don't deny the user the deposit
					debugPrint("[DEPOSIT] Deposit accepted for "..tostring(dep.amountDelivered).." User: "..dep.user)
					serverConfigs.usernames[dep.user].balance = serverConfigs.usernames[dep.user].balance + dep.amountDelivered -- Once again safeguard in case more is delivered than expected
					local transaction = "Deposit of "..tostring(dep.amountDelivered)
					if #username.transactions > 25 then
						table.remove(username.transactions,#username.transactions)
					end
					table.insert(username.transactions,1,transaction)
					saveConfigs()
					if dep.public then
						sendPacket(dep.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
					else
						sendBankNetwork(dep.src,{type = "BALANCE_UPDATE_ACCT_RESP", accountInfo = username})
					end
					debugPrint("[DEPOSIT] Deposit confirmed and update sent to user")
				end
			end
		end
	end
end

local function cardReturn()
	while true do
		local _,nbt,address = os.pullEvent("return_card")
		debugPrint("Card return active, waiting 20 seconds to assure card is in vault")
		os.sleep(20)
		debugPrint("Card return attempting to request from Stock Ticker")
		stockTicker.requestFiltered(address,{nbt=nbt,_requestCount=1})
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

parallel.waitForAny(listener, cliLoop, depositConfirmLoop, cardReturn)
