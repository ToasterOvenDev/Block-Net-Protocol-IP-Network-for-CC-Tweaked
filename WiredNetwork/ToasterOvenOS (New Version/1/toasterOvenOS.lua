-- toasterOvenOS.lua

package.path = package.path .. ";./Dependencies/?.lua"
package.path = package.path .. ";../?.lua"

local basalt = require("basalt")
local client = require("client")
basalt.schedule(client.receiveLoop)
local password = "Password"
local username = "User"

local apps = {}
local installedApps = { { text = "Installer", path = "/installer.lua" }, }

local config = { usrn = username, psw = password, apps = apps, installed = installedApps }
local configFile = "/.Configs/TOOSConfig.txt"

-- Loads all config variables
if not fs.exists(configFile) then -- Creates if neccesary
    local f = fs.open(configFile, "w")
    f.writeLine("")
    f.close()
else -- Loads if exists
    local f = fs.open(configFile, "r")
    local Loadedconfig = f.readAll()
    config = textutils.unserialize(Loadedconfig)
    f.close()
    if config == "" then
        password = "Password"
        username = "User"
        apps = {}
        installedApps = { { text = "Installer", path = "/installer.lua" }, }
    else
        password = config.psw
        username = config.usrn
        apps = config.apps
        installedApps = config.installed
    end
end
-- Saves all the configs
local function saveConfig()
    config.psw = password
    config.usrn = username
    local f = fs.open(configFile, "w")
    f.writeLine(textutils.serialize(config))
    f.close()
end

saveConfig()

-- HERE STARTS CHANGES
local main = basalt.getMainFrame():setBackground(colors.black)

local clientFrame = main:addFrame():setBackground(colors.lightBlue):setVisible(false):setSize(51, 19) -- Changed

basalt.LOGGER.setEnabled(true)
basalt.LOGGER.setLogToFile(true)

local taskbarOpened = false
local taskbar = clientFrame:addScrollFrame():setBackground(colors.white):setPosition("{parent.width}", 1):setSize(15,
    "{parent.height}"):setScrollBarColor(colors.white):setScrollBarBackgroundColor(colors.white)
:setScrollBarBackgroundColor2(colors.white):setZ(125)
local taskbarbtn = taskbar:addButton():setPosition(1, 1):setText("<"):setSize(1, "{parent.height}"):setBackground(colors
.cyan):setZ(2)

taskbarbtn:onClick(function()
    if not taskbarOpened then
        taskbar:setX("{parent.width - 14}")
        taskbarbtn:setText(">")
        taskbarOpened = true
    else
        taskbar:setX("{parent.width}")
        taskbarbtn:setText("<")
        taskbarOpened = false
    end
end)

local usernameLabel = taskbar:addLabel():setPosition(3, 2):setText(username):setForeground(colors.blue)


local sub = { -- Desc: Subframes of clientFrame aka. Tabs on the desktop
    ["Desktop"] = clientFrame:addScrollFrame():setPosition(1, 1):setSize("{parent.width-1}", "{parent.height}")
    :setBackground(colors.lightBlue):setVisible(false),
    ["Network Shell"] = clientFrame:addFrame():setPosition(1, 1):setSize("{parent.width-1}", "{parent.height}")
    :setBackground(colors.lightBlue):setVisible(false),
    ["Shell"] = clientFrame:addFrame():setPosition(1, 1):setSize("{parent.width-1}", "{parent.height}"):setBackground(
    colors.lightBlue):setVisible(false),
    ["Settings"] = clientFrame:addFrame():setPosition(1, 1):setSize("{parent.width-1}", "{parent.height}"):setBackground(
    colors.lightBlue):setVisible(false),
}

local function buildPassFrame(landingFrame)
    passFrame = main:addFrame():setBackground(colors.cyan):setVisible(true):setSize(51, 19)
    local userLabel = passFrame:addBigFont():setText(username):setPosition(8, 3)
    local passInput = passFrame:addInput() -- Changed
        :centerHorizontal("parent")
        :centerVertical("parent")
        :setSize(25, 1)
        :setForeground(colors.white)
        :setBackground(colors.lightBlue)
        :setPlaceholder(" Enter Password here...")
        :setPlaceholderColor(colors.blue)
        :setReplaceChar("*")
    local passlabel = passFrame:addLabel() -- Can be kept as is
        :setY(14)
        :centerHorizontal("parent")
        :setForeground(colors.white)
        :setText("Error Text Here")
    local button = passFrame:addButton() -- Changed
        :setY(12)
        :centerHorizontal("parent")
        :setSize(6, 1)
        :setText("Login")
        :setForeground(colors.white)
        :setBackground(colors.green)
        :onClick(
            function()
                local text = passInput:getText()
                if text == password then
                    passlabel:setForeground(colors.green)
                    passlabel:setText("Correct! Opening ToasterOvenOS...")
                    passFrame:destroy()
                    clientFrame:setVisible(true)
                    taskbar:setVisible(true)
                    sub[landingFrame]:setVisible(true)
                else
                    passlabel:setForeground(colors.red)
                    passlabel:setText("Incorrect, try again!")
                end
            end)
end
-- Builds the Start Animation for the OS
local aniFrame = main:addFrame():setBackground(colors.black):setSize("{parent.width}", "{parent.height}")
local aniO = aniFrame:addBigFont({ text = "", x = 2, y = 4, foreground = colors.white, background = colors.black, width =
"{parent.width}", height = 3, backgroundEnabled = false }):animate()
aniO:fadeText("text", "Operating", 10) -- Animation for Operating
    :sequence()
    :start()
local aniS = aniFrame:addBigFont({ text = "", x = 16, y = 4, foreground = colors.white, background = colors.black, width =
"{parent.width}", height = 3, backgroundEnabled = false }):animate()
aniS:scrollText("text", "System", 2.5) -- Animation for System
    :sequence()
    :start()
    :onComplete(function()
        os.sleep(0.5)
        buildPassFrame("Desktop")
        aniFrame:destroy()
    end)
local aniTO = aniFrame:addBigFont({ text = "", x = 2, y = 2, foreground = colors.white, background = colors.black, width =
"{parent.width}", height = 3, backgroundEnabled = false }):animate()
aniTO:fadeText("text", "Toaster Oven", 10) -- Animation for Toaster Oven
    :sequence()
    :start()

local desktopBar = sub["Desktop"]:addFrame():setPosition(1, 1):setSize("{parent.width}", 1):setBackground(colors.blue)
desktopBar:addButton():setPosition("{parent.width-13}", 1):setText("Logout"):setSize(6, 1):setBackground(colors.blue)
    :setForeground(colors.red):onClick(
    function()
        for _, b in pairs(sub) do b:setVisible(false) end
        taskbar:setVisible(false)
        clientFrame:setVisible(false)
        buildPassFrame("Desktop")
    end)
desktopBar:addButton():setPosition("{parent.width-5}", 1):setText("Reboot"):setSize(6, 1):setBackground(colors.blue)
    :setForeground(colors.red):onClick(function() os.reboot() end)

local tabOrder = { "Desktop", "Network Shell", "Shell", "Settings" }
local taskbarBtns = {}
local buttonPos = {}

local function updateTaskBar(taskY)
    basalt.LOGGER.debug(textutils.serialize(taskY))
    basalt.LOGGER.debug(textutils.serialize(buttonPos))
    local aboveTask = {}
    -- collect keys that should move
    for key, v in pairs(buttonPos) do
        if v > taskY then
            table.insert(aboveTask, key)
        end
    end
    basalt.LOGGER.debug(textutils.serialize(aboveTask))
    -- move entries by key
    for _, key in ipairs(aboveTask) do
        buttonPos[key] = buttonPos[key] - 3
        taskbarBtns[key]:setY(buttonPos[key])
    end
end


local function findFreePos()
    local start = 4
    local spacing = 3
    -- Build lookup set of occupied positions
    local taken = {}
    for _, v in pairs(buttonPos) do
        taken[v] = true
    end
    -- Walk forward until we find one that's not taken
    local pos = start
    while taken[pos] do
        pos = pos + spacing
    end

    return pos
end

local function addTask(task, name, Pid)
    local pos = findFreePos()
    taskbarBtns[Pid] = taskbar:addButton()
        :setText(name)
        :setBackground(colors.white)
        :setForeground(colors.black)
        :setSize("{parent.width - 2}", 2)
        :setPosition(3, pos)
        :onClick(function() -- here we create a on click event which hides ALL sub frames and then shows the one which is linked to the button
            for _, b in pairs(sub) do b:setVisible(false) end
            task:setVisible(true)
        end)
    buttonPos[Pid] = pos
end

id = 0
for _, tab in ipairs(tabOrder) do -- Inital Setup of OS Tasks (Desktop,Network Shell,Shell,and Settings) y will equal 16
    addTask(sub[tab], tab, tab)
end
taskbarBtns["Settings"]:onClick(
    function() -- here we create a on click event which hides ALL sub frames and then shows the one which is linked to the button
        for _, b in pairs(sub) do b:setVisible(false) end
        buildPassFrame("Settings")
    end)

-- Opens a program in a new tab
local function openProgram(path, title)
    id = id + 1
    local Pid = tostring(id)
    title = title or "Shell App"
    sub[Pid] = clientFrame:addFrame():setSize("{parent.width}", "{parent.height}")
    local f = sub[Pid]
    addTask(sub[Pid], title, Pid)

    f:addLabel()
        :setSize("{parent.width}", 1)
        :setBackground(colors.blue)
        :setForeground(colors.black)
        :setText(title)

    f:addProgram()
        :setSize(f.width, f.height - 1)
        :setPosition(1, 2)
        :execute(path or "rom/programs/shell.lua")

    f:addButton()
        :setSize(5, 1)
        :setText("Close")
        :setBackground(colors.blue)
        :setForeground(colors.red)
        :setPosition("{parent.width-5}", 1)
        :onClick(function()
            f:destroy()
            updateTaskBar(buttonPos[Pid])
            buttonPos[Pid] = nil
            taskbarBtns[Pid]:destroy()
            sub[Pid] = nil
            for _, b in pairs(sub) do b:setVisible(false) end
            sub["Desktop"]:setVisible(true)
        end)
    return f
end
local desktopBtns = {}
local Apps = 0

local function loadDesktopBtns()
    for _, v in pairs(apps) do
        Apps = Apps + 1
        local x, y = v.posx, v.posy
        local name = v.name
        local path = v.path
        if not fs.exists(path) then return end
        desktopBtns[name] = sub["Desktop"]:addButton()
            :setText(name)
            :setPosition(x, y)
            :setSize(10, 3)
            :setBackground(colors.white)
        desktopBtns[name]:onClick(
            function()
                openProgram(path, name)
            end)
    end
end

loadDesktopBtns()
-- Editing buttons for the desktop
local function editMode()
    local editFrame = clientFrame:addFrame():setPosition(1, 1):setSize("{parent.width}", 3):setBackground(colors.white)
    -- MyX --> TrueX   TrueX = (MyX*12)-10
    -- Formula for MyY --> TrueY   TrueY = (MyY*4)-2
    editFrame:addLabel():setText("Pos:")
    editFrame:addLabel():setText(","):setX(9)
    editFrame:addLabel():setText("App Path:"):setX(16)
    editFrame:addLabel():setText("Name:"):setX(34)
    local errorLabel = editFrame:addLabel():setText("On Screen X 1-4, On Screen Y 1-4"):setY(3):setForeground(colors.red)
    local xInput = editFrame:addInput():setPlaceholder("X"):setX(5):setSize(4, 1)
    local yInput = editFrame:addInput():setPlaceholder("Y"):setX(10):setSize(4, 1)
    local pathInput = editFrame:addInput():setPlaceholder("Path..."):setX(25)
    local iApps = {}
    for _, app in pairs(installedApps) do
        table.insert(iApps, { text = app.text, callback = function() pathInput:setText(app.path) end })
    end
    local nameInput = editFrame:addComboBox():setSelectedText("Name..."):setX(39):setSize(11, 1):setAutoComplete(true)
        :setItems(iApps)
    local function translateXnY(inx, iny)
        local x = tonumber(inx)
        local y = tonumber(iny)
        if x > 4 or y > 4 then errorLabel:setText("X or Y is offscreen, but Desktop is scrollable") end
        x = (x * 12) - 10
        y = (y * 4) - 1
        return x, y
    end
    editFrame:addButton():setText("Add App"):setY(2):setSize(7, 1):onClick(
        function()
            Apps = Apps + 1
            local inx, iny = xInput:getText(), yInput:getText()
            if inx == "" or iny == "" then return end
            local x, y = translateXnY(inx, iny)
            local name = nameInput:getText()
            if name == "" then name = "App " .. tostring(Apps) end
            local path = pathInput:getText()
            if not fs.exists(path) then
                errorLabel:setText("Error! Path does not exist")
                return
            end
            desktopBtns[name] = sub["Desktop"]:addButton()
                :setText(name)
                :setPosition(x, y)
                :setSize(10, 3)
                :setBackground(colors.white)
            desktopBtns[name]:onClick(
                function()
                    openProgram(path, name)
                end)
            apps[name] = { posx = x, posy = y, name = name, path = path }
            saveConfig()
        end)
    editFrame:addButton():setText("Remove App"):setSize(10, 1):setPosition(9, 2):onClick(function()
        local name = nameInput:getText()
        if not desktopBtns[name] then
            errorLabel:setText(name .. " Does not exist or multiple entries")
            return
        end
        desktopBtns[name]:destroy()
        desktopBtns[name] = nil
        apps[name] = nil
        saveConfig()
    end)
    editFrame:addButton():setText("Exit"):setPosition(20, 2):setSize(4, 1):onClick(function() editFrame:destroy() end)
end

desktopBar:addButton()
    :setText("Edit Desktop")
    :setPosition(1, 1)
    :setSize(14, 1)
    :setBackground(colors.blue)
    :onClick(
        function()
            editMode()
        end)
if not fs.exists("/.Dependencies/clientCLI.lua") then --Makes the lightweight CLI executable
    local f = fs.open("/.Dependencies/clientCLI.lua", "w")
    f.write("local client = require(\"client\") os.sleep(1) client.cliLoop()")
    f.close()
end

sub["Network Shell"]:addProgram()
    :execute("/.Dependencies/clientCLI.lua")
    :setPosition(1, 1)
    :setSize(clientFrame.width, clientFrame.height)
--Slight Rework
sub["Shell"]:addProgram():execute("/rom/programs/shell.lua"):setPosition(1, 1):setSize(clientFrame.width,
    clientFrame.height)


-- Settings Frame All this might be fine, but double check anyway
local setBNP = (client.getBNP() or " N/A")                           -- Settings BNP variable
local setDNS = (client.getHostSvrBNP() or " N/A")                    -- Settings DNSBNP variable
local BNPError =
"Error: Invalid BNP, should follow num.num.num.num"                  -- BNP error, used like 3 times got tired of writing it tbh

--Setup for Settings
local function buildSettingsFrame(user)
    sub["Settings"]:addLabel():setText("Username: "):setPosition(2, 6):setForeground(colors.white)          -- Label for Username
    sub["Settings"]:addLabel():setText("Password: "):setPosition(2, 8):setForeground(colors.white)          -- Label for Password
    local setErrLabel = sub["Settings"]:addLabel():setPosition(2, 10):setForeground(colors.red):setText("Error text appears here")
    local inputUsername = sub["Settings"]:addInput():setPlaceholder(username):setPosition(12, 6):setSize(14, 1) -- 13 characters max input for username
    local inputPass = sub["Settings"]:addInput():setPlaceholder(("*"):rep(#password)):setPosition(12, 8):setSize(16, 1):setReplaceChar("*")-- input for password
    -- Button to submit the Username in input
    sub["Settings"]:addButton():setText("Change Username"):setPosition(34, 6):setSize(16, 1):setForeground(colors.white)
    :setBackground(colors.lightBlue):onClick(function()
        local input = inputUsername:getText()
        if not input then
            username = "User"
            setErrLabel:setText("Error: No username input, setting to 'User'")
        else
            username = input or "User"
            usernameLabel:setText(input)
            saveConfig()
        end
    end)
    -- Button to submit the Password in input
    sub["Settings"]:addButton():setText("Change Password"):setPosition(34, 8):setSize(16, 1):setForeground(colors.white)
    :setBackground(colors.lightBlue):onClick(function()
        local input = inputPass:getText()
        if not input then
            password = "Password"
            setErrLabel:setText("Error: No password input, setting to 'Password'")
        else
            password = input or "password"
            saveConfig()
        end
    end)
    -- Button to submit the BNP in input
    sub["Settings"]:addLabel():setText("BNP: "):setPosition(2, 2):setForeground(colors.white)               -- Label for BNP
    local inputmyBNP = sub["Settings"]:addInput():setPlaceholder(setBNP):setPosition(7, 2):setSize(24, 1)   -- input for BNP
    sub["Settings"]:addButton():setText("Change BNP"):setPosition(34, 2):setSize(10, 1):setForeground(colors.white)
    :setBackground(colors.lightBlue):onClick(function()
        local inputBNP = inputmyBNP:getText()
        if not inputBNP then
            client.setBNP(nil)
            setErrLabel:setText(BNPError .. "BNP currently nil")
        elseif inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then
            client.setBNP(inputBNP)
        elseif not inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then
            setErrLabel:setText(BNPError)
        end
    end)
    -- Button to submit the DNS BNP in input
    sub["Settings"]:addLabel():setText("DNS: "):setPosition(2, 4):setForeground(colors.white)               -- Label for DNS BNP
    local inputDNSBNP = sub["Settings"]:addInput():setPlaceholder(setDNS):setPosition(7, 4):setSize(24, 1)  -- input for DNS BNP
    sub["Settings"]:addButton():setText("Change DNS"):setPosition(34, 4):setSize(10, 1):setForeground(colors.white)
        :setBackground(colors.lightBlue):onClick(function()
        local inputBNP = inputDNSBNP:getText()
        if not inputBNP then
            client.setHostSvrBNP(nil)
            setErrLabel:setText(BNPError .. "BNP currently nil")
        elseif inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then
            client.setHostSvrBNP(inputBNP)
        elseif not inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then
            setErrLabel:setText(BNPError)
        end
    end)
end
buildSettingsFrame()
basalt.run() -- actually runs the GUI
