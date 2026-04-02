--trafficlightController.lua
--Controls connected trafficlightNode.lua
--CLI to configure Trafficlight nodes

local timer = 15 -- Time until light changes from green or red, yellow is timer/3

-- Opens Traffic Light Controller's modems to Traffic Light Nodes
local sides = {"top","back","front","right","left","bottom"}
local interfaces = {}
local groupsSides = {}
local configFile = "traffic.conf"

for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        interfaces[side] = m
        pcall(function() m.open(1) end)
        print("Opened side " .. side)
    end
end

local function saveConfigs()
	local f = fs.open(configFile,"w")
    f.writeLine(textutils.serialize(groupsSides))
    f.close()
end

if not fs.exists(configFile) then
	local f = fs.open(configFile,"w")
	f.write("")
	f.close()
else
	local f = fs.open(configFile,"r")
	local config = textutils.unserialise(f.readAll())
    f.close()
	if config == "" or config == nil then
        local ind1
        local ind2
        local filledI1
        for side in pairs(interfaces) do
            if filledI1 then
                ind2 = side
                break
            end
            ind1 = side
            filledI1 = true
        end
        groupsSides[1] = ind1
        groupsSides[2] = ind2
	else
		groupsSides = config
	end
    saveConfigs()
end

if next(interfaces) == nil then error("No modems found!") end

local group1
local group2
local group1Names
local group2Names

local function fillGroupVars()
    print(textutils.serialize(groupsSides))
    group1 = interfaces[groupsSides[1]]
    group2 = interfaces[groupsSides[2]]
    group1Names = group1.getNamesRemote()
    group2Names = group2.getNamesRemote()
    saveConfigs()
end

fillGroupVars()

for _, name in ipairs(group1Names) do
    group1.callRemote(name, "setPaletteColour",colors.red, 0xFF0000)
    group1.callRemote(name, "setPaletteColour", colors.yellow, 0xffff00)
    group1.callRemote(name, "setPaletteColour", colors.green, 0x00ff00)
end

for _, name in ipairs(group2Names) do
    group2.callRemote(name, "setPaletteColour",colors.red, 0xFF0000)
    group2.callRemote(name, "setPaletteColour", colors.yellow, 0xffff00)
    group2.callRemote(name, "setPaletteColour", colors.green, 0x00ff00)
end

-- Light changer functions

local function change(groupNames,modem,color)
    for _,name in ipairs(groupNames) do
        modem.callRemote(name, "setBackgroundColor", color)
        modem.callRemote(name, "clear")
    end
end

-- Red light changer
local function redlight(group)
    if group == 1 then
        change(group1Names,group1,colors.red)
    elseif group == 2 then
        change(group2Names,group2,colors.red)
    end
    print("Light is red for group " .. tostring(group))
end
-- Yellow light changer
local function yellowlight(group)
    if group == 1 then
        change(group1Names,group1,colors.yellow)
    elseif group == 2 then
        change(group2Names,group2,colors.yellow)
    end
    print("Light is yellow for group " .. tostring(group))
end
-- Green light changer
local function greenlight(group)
    if group == 1 then
        change(group1Names,group1,colors.green)
    elseif group == 2 then
        change(group2Names,group2,colors.green)
    end
    print("Light is green for group " .. tostring(group))
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
        term.setTextColor(colors.red)
        redlight(2) -- Group 2 is red
        term.setTextColor(colors.white)
        os.sleep(timer) -- Wait to change light
        term.setTextColor(colors.green)
        yellowlight(1) -- Group 1 transition to green from red
        term.setTextColor(colors.white)
        os.sleep(yTimer) -- Wait for full change to green
        term.setTextColor(colors.green)
        redlight(1) -- Group 1 is red
        term.setTextColor(colors.red)
        greenlight(2) -- Group 2 is green
        term.setTextColor(colors.white)
        os.sleep(timer) -- Wait to change light
        term.setTextColor(colors.red)
        yellowlight(2) -- Group 2 transition to green from red
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
            -- set group[1] and group[2] to certain sides
            local groupNum = tonumber(args[3])
            local groupSide = args[4]
            local validSide = false
            for side in pairs(interfaces) do
                if side == groupSide then
                    validSide = true
                    break
                end
            end
            if validSide then
                print("Setting group "..args[3].." to interface "..groupSide)
                if groupNum == 1 then
                    groupsSides[2] = groupsSides[1]
                    groupsSides[1] = groupSide
                    fillGroupVars()
                    print("Set group 1 to interface "..groupSide)
                    print("Set group 2 to interface "..groupsSides[2])
                elseif groupNum == 2 then
                    groupsSides[1] = groupsSides[2]
                    groupsSides[2] = groupSide
                    fillGroupVars()
                    print("Set group 1 to interface "..groupsSides[1])
                    print("Set group 2 to interface "..groupSide)
                else
                    print("Group Number not valid")
                end
            else
                print("Side not valid")
            end
        else
           printError("Command not recognized")
           printCommands()
        end
    end
end

-- Run both CLI and the trafficlight at the same time
parallel.waitForAny(CLI,trafficlight)