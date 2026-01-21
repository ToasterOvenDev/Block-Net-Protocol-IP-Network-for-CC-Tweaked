local basalt = require("basalt")
local ATM = require("ATM")

local main = basalt.getMainFrame():setBackground(colors.green)
main:addFrame():setBackground(colors.black):setSize(10,19)
main:addFrame():setBackground(colors.black):setSize(10,19):setPosition(42,1)

local userInput = main:addInput()
	:centerHorizontal("parent")
	:setY(8)
	:setSize(25, 1)
	:setForeground(colors.white)
	:setBackground(colors.lightBlue)
	:setPlaceholder(" Enter Username here...")
	:setPlaceholderColor(colors.blue)
local passInput = main:addInput()
	:centerHorizontal("parent")
	:setY(10)
	:setSize(25, 1)
	:setForeground(colors.white)
	:setBackground(colors.lightBlue)
	:setPlaceholder(" Enter Password here...")
	:setPlaceholderColor(colors.blue)
local errorLabel = main:addLabel()
	:setVisible(false)
	:setText("Error")
	:setForeground(colors.red)
	:centerHorizontal("parent")
	:setY(14)
local button = main:addButton() -- Changed
        :setPosition(14,12)
        :setSize(6, 1)
        :setText("Login")
        :setForeground(colors.white)
        :setBackground(colors.green)
        :onClick(
            function()
				local username = userInput:getText()
				local password = passInput:getText()
				if username == "" or password == "" then
					errorLabel:setVisible(true):setText("Missing Username or Password"):centerHorizontal("parent")
				else
					errorLabel:setVisible(true):setText("Login attempt accepted"):setForeground(colors.lime):centerHorizontal("parent")
					ATM.sendPacket({ type="LOGIN_ATTEMPT", user = username, pass = password })
					local response
					for i=1,5 do
						local _, _, _, _, msg = os.pullEvent("modem_message")
						local payload = msg.payload
						if payload.type == "LOGIN_RESP" then
							response = payload
							break
						end
					end
					if response and response.confirm == "Allow" then
						--move on to ATM with account info
					elseif response and response.confirm == "Deny" then
						errorLabel:setVisible(true):setText("Passowrd Incorrect"):centerHorizontal("parent")
					elseif response and response.confirm == "Void" then
						errorLabel:setVisible(true):setText("No account with username "..username):centerHorizontal("parent")
					else
						errorLabel:setVisible(true):setText("No connection to Bank Server"):centerHorizontal("parent")
					end
				end
            end)
main:addBigFont()
	:setText("ATM")
	:setPosition(22,3)
	:setBackground(colors.green)

local function setupCLI()
	local settingup = true
	while settingup do
		write("Enter Bank Server BNP: ")
		local userin = read()
		ATM.bankBNP = userin
		print("Pick a inventory to be the input ")
		for _,inv in pairs(ATM.chests) do
			print("- "..inv)
		end
		userin = read()
		for i,inv in pairs(ATM.chests) do
			if userin == inv then
				print("Picked "..inv.." as input inventory")
				ATM.bank = i
			end
		end
		print("Current settings are: \nBank BNP: "..ATM.bankBNP.."\nInput Inventory: "..ATM.chests[ATM.bank])
		print("\nDo you want to continue with these settings? (y/n)")
		userin = read()
		if userin == "y" then
			print("Settings saved, please restart device")
			settingup = false
		else
			print("resetting process")
			ATM.bankBNP = nil
			ATM.bank = 1
		end
	end
end

if ATM.setupNeeded then
	setupCLI()
	ATM.setupNeeded = false
	ATM.saveConfigs()
end

basalt.schedule(ATM.listener)
basalt.run()