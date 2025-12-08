package.path = package.path .. ";../Dependencies/?.lua"
local basalt = require("basalt")

local programs = { --This holds all avaliable programs and their webpage
    ["File Transfer"] = "wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Apps/ftp.lua /Apps/ftp.lua",
    ["Bank Client"] = "wget bankClient /Apps/bankClient.lua"
}
local installed = {
    ["File Transfer"] = fs.exists("/Apps/ftp.lua"),
    ["Bank Client"] = fs.exists("/Apps/bankClient.lua"),
}
local programsL = {
    ["File Transfer"] = "/Apps/ftp.lua",
    ["Bank CLient"] = "/Apps/bankClient.lua"
}

local function registerApp(program,path)
    local list = {}

    if fs.exists("../Configs/installedApps.txt") then
        local f = fs.open("../Configs/installedApps.txt", "r")
        list = textutils.unserialize(f.readAll()) or {}
        f.close()
    end
    
    list[activeDesktop] = list[activeDesktop] or {}
    table.insert(list[activeDesktop], {program = program, path = path})

    local f = fs.open("../Configs/installedApps.txt", "w")
    f.write(textutils.serialize(list))
    f.close()
end

local function installerFrame() -- Creates a frame with a radio list
    local gui = basalt.createFrame():setBackground(colors.cyan)
    local radioList = gui:addList():setBackground(colors.cyan)
    for k,v in pairs(programs) do
        radioList:addItem(k, colors.cyan, colors.black, programs[v])
    end
    radioList:onSelect(
        function(self, event, item)
            local iname = item.text
            local webpage = programs[iname]
            if installed[iname] == false then
                shell.run(webpage)
                registerApp(iname,programsL[iname])
                return
            else
                return
            end
        end)
    basalt.autoUpdate()
end

installerFrame()
