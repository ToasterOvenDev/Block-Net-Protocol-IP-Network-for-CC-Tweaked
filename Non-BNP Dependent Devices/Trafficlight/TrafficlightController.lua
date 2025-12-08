--trafficlightController.lua
--Controls connected trafficlightNode.lua
--CLI to configure Trafficlight nodes

local timer = 15 -- Time until light changes from green or red, yellow is timer/3

-- Opens Traffic Light Controller's modems to Traffic Light Nodes
local sides = {"back","front","right","left","bottom","top"}
local interfaces = {}

for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        interfaces[side] = m
        pcall(function() m.open(1) end)
        print("Opened side " .. side)
    end
end

if next(interfaces) == nil then error("No modems found!") end

-- Light changer functions
-- Red light changer
local function redlight(group)
    local red = {
        group = group,
        command = "turn red"
    }
    for _, m in pairs(interfaces) do
        m.transmit(1,1,red)
    end
    print("light is red for group " .. group)
end
-- Yellow light changer
local function yellowlight(group)
    local yellow = {
        group = group,
        command = "turn yellow"
    }
    for _, m in pairs(interfaces) do
        m.transmit(1,1,yellow)
    end
    print("light is yellow for group " .. group)
end
-- Green light changer
local function greenlight(group)
    local green = {
        group = group,
        command = "turn green"
    }
    for _, m in pairs(interfaces) do
        m.transmit(1,1,green)
    end
    print("light is green for group " .. group)
end

-- Main function changes light colors
local function trafficlight()
term.setTextColor(colors.green)
print("Green means Group 1")
term.setTextColor(colors.red)
print("Red means Group 2")
term.setTextColor(colors.white)
    while true do
        local yTimer = timer/3
        term.setTextColor(colors.green)
        greenlight(1) -- Group 1 is green
        term.setTextColor(colors.white)
        term.setTextColor(colors.red)
        redlight(2) -- Group 2 is red
        term.setTextColor(colors.white)
        os.sleep(timer) -- Wait to change light
        term.setTextColor(colors.red)
        yellowlight(2) -- Group 2 transition to green from red
        term.setTextColor(colors.white)
        os.sleep(yTimer) -- Wait for full change to green
        term.setTextColor(colors.green)
        redlight(1) -- Group 1 is red
        term.setTextColor(colors.white)
        term.setTextColor(colors.red)
        greenlight(2) -- Group 2 is green
        term.setTextColor(colors.white)
        os.sleep(timer) -- Wait to vhange light
        term.setTextColor(colors.green)
        yellowlight(1) -- Group 1 transition to green from red
        term.setTextColor(colors.white)
        os.sleep(yTimer) -- Wait for full change to green
    end
end

-- CLI Helper
local function printCommands()
    local cmds = {
        "exit",
        "help",
        "set group <1 or 2> <side>"
    }
    print("Traffic Light Commands:")
    for i, cmd in ipairs(cmds) do
        print("    " .. cmd)
    end
end

-- CLI Loop
local function CLI()
    os.sleep(.1)
    print("CLI Loading...")
    os.sleep(1)
    printCommands()
    while true do
        io.write(">")
        local line = io.read()
        if not line then break end
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args,word) end
        local cmd = args[1]
        
        if cmd == "exit" then return
        elseif cmd == "help" then printCommands()
        elseif cmd == "set" and args[2] == "group" then
           local packet = { 
               command = "set group",
               group = args[3]
           }
           local s = tostring(args[4])
           print(textutils.serialize(packet))
           interfaces[s].transmit(1,1,packet)
       else
           printError("Command not recognized")
           printCommands()
       end
   end
end
    
-- Run both CLI and the trafficlight at the same time
parallel.waitForAny(CLI,trafficlight)





