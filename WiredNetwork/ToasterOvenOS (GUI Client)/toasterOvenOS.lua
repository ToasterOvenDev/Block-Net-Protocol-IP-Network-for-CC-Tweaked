-- toasterOvenOS.lua

package.path = package.path .. ";./Dependencies/?.lua"

local basalt = require("basalt")
local client = require("client")
local password = "Password"
local username = "User"

local apps = {}
 
local config = { usrn = username, psw = password, buttonx = x, buttony = y,}
local configFile = "Configs/ClientConfigGUI.txt"

-- Loads all config variables
if not fs.exists(configFile) then -- Creates if neccesary
    local f = fs.open(configFile, "w")
    f.writeLine("")
    f.close()
else -- Loads if exists
    local f = fs.open(configFile,"r")
    local Loadedconfig = f.readAll()
    config = textutils.unserialize(Loadedconfig)
    f.close()
    if config=="" then
        password = "Password"
        username = "User"
    else
        password = config.psw
        username = config.usrn
    end
end
-- Saves all the configs
local function saveConfig()
    config.psw = password
    config.usrn = username
    local f = fs.open(configFile,"w")
    f.writeLine(textutils.serialize(config))
    f.close()
end

saveConfig()

local function loadApps()
    if fs.exists("/Configs/installedApps.txt") then
        local f = fs.open("Configs/installedApps.txt")
        apps = textutils.unserialize(f.readAll()) or {}
        f.close()
    end
end

local main = basalt.createFrame():setBackground(colors.gray)
local clientFrame = basalt.createFrame():setBackground(colors.lightBlue)

local input = main:addInput()
    :setPosition(2,2)
    :setSize(25,1)
    :setForeground(colors.white)
    :setDefaultText("Enter Password here...")
    :setInputType("password")

local label = main:addLabel()
    :setPosition(2,4)
    :setForeground(colors.white)

label:setText("Enter Password Above")

local button = main:addButton()
    :setPosition(2,6)
    :setSize(6,1)
    :setVerticalAlign("bottom")
    :setText("Submit")
    :setForeground(colors.white)
    :setBackground(colors.green)
    :onClick(
        function()
            local text = input:getValue()
            if text == password then
                label:setForeground(colors.green)
                label:setText("Password Correct Opening Client...")
                clientFrame:show()
            else
                label:setForeground(colors.red)
                label:setText("Incorrect, try again!")
            end
        end)

local sidebar = clientFrame:addFrame():setBackground(colors.white):setPosition("parent.w", 1):setSize(15, "parent.h"):setZIndex(25)
:onGetFocus(function(self)
    self:setPosition("parent.w - (self.w-1)")
end)
:onLoseFocus(function(self)
    self:setPosition("parent.w")
end)

-- subframes of clientFrame they act as tabs on the computer with the first ones like seperate desktops that can all run different programs seperately and the last two being shells for more experienced users
local sub = { -- Desc: Subframes of clientFrame aka. Tabs on the desktop
    ["Desktop 1"] = clientFrame:addFrame():setPosition(1, 1):setSize("parent.w", "parent.h"):setBackground(colors.lightBlue):hide(),
    ["Desktop 2"] = clientFrame:addFrame():setPosition(1, 1):setSize("parent.w", "parent.h"):setBackground(colors.lightBlue):hide(),
    ["Desktop 3"] = clientFrame:addFrame():setPosition(1, 1):setSize("parent.w", "parent.h"):setBackground(colors.lightBlue):hide(),
    ["Network Shell"] = clientFrame:addFrame():setPosition(1, 1):setSize("parent.w", "parent.h"):setBackground(colors.lightBlue),
    ["Shell"] = clientFrame:addFrame():setPosition(1, 1):setSize("parent.w", "parent.h"):setBackground(colors.lightBlue):hide(),
}

local settings = basalt.createFrame():setPosition(1, 1):setBackground(colors.black):hide()

--[[ This Can be uncommeted to make a scrollbar if more tabs are needed
local scrollbar = sidebar:addScrollbar():setPosition("parent.w", 1):setSize(1, 28):setScrollAmount(10)

sidebar:setOffset(0, 0)

scrollbar:onChange(function(self, _, value)
  sidebar:setOffset(0, value-1)
end)
--]]

local usernameLabel = sidebar:addLabel():setPosition(2,2):setText(username):setForeground(colors.blue) -- label at the top of the sidebar that displays the Username
_G.activeDesktop = "Desktop 1" -- Global variable of active desktop
local tabOrder = {"Desktop 1","Desktop 2","Desktop 3","Network Shell","Shell"}
--This part of the code adds buttons based on the sub table.
local y = 4
for i,k in ipairs(tabOrder)do
    local v = sub[k]
    sidebar:addButton():setText(k) -- creating the button and adding a name k is just the index
    :setBackground(colors.white)
    :setForeground(colors.black)
    :setSize("parent.w - 2", 2)
    :setPosition(2, y)
    :onClick(function() -- here we create a on click event which hides ALL sub frames and then shows the one which is linked to the button
        for a, b in pairs(sub)do b:hide() end
        if k ~= "Shell" or k ~= "Network Shell" then
            activeDesktop = k
        end
        v:show()
    end)
    y = y + 3
end

-- Makes a frame resizable
local function makeResizeable(frame, color, minW, minH, maxW, maxH) 
    minW = minW or 4
    minH = minH or 4
    maxW = maxW or 99
    maxH = maxH or 99
    local btn = frame:addButton()
        :setPosition("parent.w", "parent.h")
        :setSize(1, 1)
        :setText("/")
        :setForeground(colors.blue)
        :setBackground(color or colors.cyan)
        :onDrag(function(self, event, btn, xOffset, yOffset)
            local w, h = frame:getSize()
            local wOff, hOff = w, h
            if(w+xOffset-1>=minW)and(w+xOffset-1<=maxW)then
                wOff = w+xOffset-1
            end
            if(h+yOffset-1>=minH)and(h+yOffset-1<=maxH)then
                hOff = h+yOffset-1
            end
            frame:setSize(wOff, hOff)
        end)
end
-- Variables for Opening programs in a window
local id = 1 -- ID for program
local processes = {} -- All running programs minus the always running shells and GUI
-- Opens a program in a draggable window
local function openProgram(frame, path, title, color, x, y, w, h)
    local pId = id
    id = id + 1
    local f = frame:addMovableFrame()
        :setSize(w or 30, h or 12)
        :setPosition(x or math.random(2, 12), y or math.random(2, 8))
        :setBorder(colors.black)

    f:addLabel()
        :setSize("parent.w", 1)
        :setBackground(colors.blue)
        :setForeground(colors.black)
        :setText(title or "New Program")

    f:addProgram()
        :setSize("parent.w", "parent.h - 1")
        :setPosition(1, 2)
        :execute(path or "rom/programs/shell.lua")

    f:addButton()
        :setSize(1, 1)
        :setText("X")
        :setBackground(colors.blue)
        :setForeground(colors.red)
        :setPosition("parent.w-1", 1)
        :onClick(function()
            f:remove()
            processes[pId] = nil
        end)
    processes[pId] = f
    makeResizeable(f,color or colors.cyan)
    return f
end

local xDynPos = {26,26,26} -- Dynamic x position for adding buttons
local yDynPos = {3,3,3}-- Dynamic y position for adding buttons
local DesktopButtons = { ["Desktop 1"] = {}, ["Desktop 2"] = {}, ["Desktop 3"] = {} }

local function addBtn(frame,app,x,y,desktop) -- Dynamically adds buttons for installed programs
    local btn = frame:addButton()
        :setText(app.program)
        :setPosition(x,y)
        :setSize(10,3)
        :onClick(
            function()
                openProgram(frame, app.path,app.program)
            end)

    table.insert(DesktopButtons[desktop], btn)

    local xp
    local yp
    if x == 38 then
        xp = 2
        yp = y+4
    else
        xp = x+12
        yp = y
    end
    return xp,yp
end

sub["Network Shell"]:addProgram()
    :onError(function(self, event, err) basalt.log("An error occurred: " .. err) end)
    :onDone(function() basalt.log("Program finished successfully") end)
    :execute(
        function() parallel.waitForAny(
            function() client.receiveLoop() end,
            function() client.cliLoop() end)
    end)
    :setPosition(1,1)
    :setSize("parent.w","parent.h")

sub["Shell"]:addProgram():onError(function(self, event, err) basalt.log("An error occurred: " .. err) end):onDone(function() basalt.log("Program finished successfully") end):execute("/rom/programs/shell.lua"):setPosition(1,1):setSize("parent.w","parent.h")

-- Settings Frame
local setBNP = (client.getBNP() or "N/A") -- Settings BNP variable
local setDNS = (client.getHostSvrBNP() or "N/A") -- Settings DNSBNP variable
local BNPError = "Error: Invalid BNP, should follow num.num.num.num" -- BNP error, used like 3 times got tired of writing it tbh

settings:addButton():setText("Back"):setPosition(1,18):setSize(6,1):onClick(function() clientFrame:show() end):setForeground(colors.white):setBackground(colors.black) -- From settings back to active Desktop
settings:addLabel():setText("BNP: "):setPosition(2,2):setForeground(colors.white) -- Label for BNP
settings:addLabel():setText("DNS: "):setPosition(2,4):setForeground(colors.white) -- Label for DNS BNP
settings:addLabel():setText("Username: "):setPosition(2,6):setForeground(colors.white)-- Label for Username
settings:addLabel():setText("Password: "):setPosition(2,8):setForeground(colors.white) -- Label for Password
local setErrLabel = settings:addLabel():setPosition(2,10):setForeground(colors.red):setText("Error text appears here")
local inputmyBNP = settings:addInput():setDefaultText(setBNP):setPosition(6,2):setInputLimit(23):setSize(24,1) -- input for BNP
local inputDNSBNP = settings:addInput():setDefaultText(setDNS):setPosition(8,4):setInputLimit(23):setSize(24,1) -- input for DNS BNP
local inputUsername = settings:addInput():setDefaultText(username):setPosition(12,6):setInputLimit(12):setSize(13,1) -- 12 characters max input for username
local inputPass = settings:addInput():setDefaultText(("*"):rep(#password)):setPosition(12,8):setInputLimit(24):setSize(25,1):setInputType("password") -- input for password
-- Button to submit the BNP in input
settings:addButton():setText("Change BNP"):setPosition(36,2):setSize(10,1):setForeground(colors.white):setBackground(colors.black):onClick(function() local inputBNP = inputmyBNP:getValue() if not inputBNP then client.setBNP(nil) setErrLabel:setText(BNPError .. "BNP currently nil") elseif inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then client.setBNP(inputBNP) elseif not inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then setErrLabel:setText(BNPError) end end)
-- Button to submit the DNS BNP in input
settings:addButton():setText("Change DNS"):setPosition(36,4):setSize(10,1):setForeground(colors.white):setBackground(colors.black):onClick(function() local inputBNP = inputDNSBNP:getValue() if not inputBNP then client.setHostSvrBNP(nil) setErrLabel:setText(BNPError .. "BNP currently nil") elseif inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then client.setHostSvrBNP(inputBNP) elseif not inputBNP:match("^%d+%.%d+%.%d+%.%d+$") then setErrLabel:setText(BNPError) end end)
-- Button to submit the Username in input
settings:addButton():setText("Change Username"):setPosition(36,6):setSize(10,1):setForeground(colors.white):setBackground(colors.black):onClick(function() local input = inputUsername:getValue() if not input then username = "User" setErrLabel:setText("Error: No username input, setting to 'User'") else username = input or "User" saveConfig() usernameLabel:setText(username) end end)
-- Button to submit the Password in input
settings:addButton():setText("Change Password"):setPosition(36,8):setSize(10,1):setForeground(colors.white):setBackground(colors.black):onClick(function() local input = inputPass:getValue() if not input then password = "Password" setErrLabel:setText("Error: No password input, setting to 'Password'") else password = input or "password" saveConfig() end end)


-- Desktops
local desktops = {"Desktop 1","Desktop 2","Desktop 3"}

for i,k in pairs(desktops) do
    sub[k]:addPane():setSize("parent.w", 1):setPosition(1, 1):setBackground(colors.blue) -- Bar on top of all desktops to make the desktop label more readable
    sub[k]:addLabel():setText(k):setPosition(1,1) -- Top of all desktops to show which one you're on
    sub[k]:addButton():setText("Settings"):setPosition(2,3):setSize(10,3):onClick(function() settings:show() end) -- Settings button to change things like BNP or Username
    sub[k]:addButton():setText("Installer"):setPosition(14,3):setSize(10,3):onClick(function() openProgram(sub[k],"Apps/installer.lua","Installer",colors.cyan) end) --Will be an installer to install other programs for the desktops
    sub[k]:addButton():setText("Reload"):setPosition(43,1):setSize(8,1):setBackground(colors.blue):onClick(function() loadApps() os.sleep(0.5) for _,btn in pairs(DesktopButtons[k]) do btn:remove() end DesktopButtons[k] = {} xDynPos[i] = 26 yDynPos[i] = 3 for j in pairs(apps[k]) do xDynPos[i],yDynPos[i] = addBtn(sub[k],apps[k][j],xDynPos[i],yDynPos[i],k) end end) -- Going to "reolad" the desktop by reloading installed programs and adding a button
end

basalt.autoUpdate() -- actually runs the GUI
