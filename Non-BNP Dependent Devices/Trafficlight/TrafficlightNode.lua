-- TrafficlightNode.lua
-- Global Variables
local group
local light = peripheral.wrap("bottom")
local modem = peripheral.wrap("top")
local GROUPTXT = "/group.txt"

-- Creates group.txt and
if not fs.exists(GROUPTXT) then
    local f = fs.open(GROUPTXT,"w") f.writeLine("")
else -- Loads group number from group.txt 
-- (Edit group.txt to set manually if you don't want to use Controller)
    local f = fs.open(GROUPTXT,"r")
    group = f.readLine()
    if group == "" then
        group = nil
    else
        group = tonumber(group)
        print("Group number loaded, I'm apart of group " .. group)
    end
end
local function saveGroup()
    local f = fs.open(GROUPTXT,"w")
    f.writeLine(group or "")
    f.close()
end

-- Opens modem for commands
modem.open(1)

-- Sets colors of monitor to more Intense colors 
light.setPaletteColour(colors.red, 0xFF0000)
light.setPaletteColour(colors.yellow, 0xffff00)
light.setPaletteColour(colors.green, 0x00ff00)

-- Light change function
local function change(clr)
    light.setBackgroundColor(clr)
    light.clear()
end

-- Command logic
local function trafficlight(cmd)
    if group ~= 1 and group ~= 2 then
        if cmd.command == "set group" then
            group = tonumber(cmd.group)
            print("Set Group to " .. cmd.group)
            saveGroup()
        else
            printError("No group assigned cannot function")
        end
    elseif cmd.group == group then
        if cmd.command == "turn red" then
            change(colors.red)
            print("Red")
        elseif cmd.command == "turn yellow" then
            change(colors.yellow)
            print("Yellow")
        elseif cmd.command == "turn green" then
            change(colors.green)
            print("Green")
        end
    elseif cmd.group ~= group then
        print("Ignoring, not my group")
    end
end

-- Listener function for commands
local function listener()
    while true do
        local _, _, _, _, msg, _ = os.pullEvent("modem_message")
        trafficlight(msg)
    end
end

listener()
