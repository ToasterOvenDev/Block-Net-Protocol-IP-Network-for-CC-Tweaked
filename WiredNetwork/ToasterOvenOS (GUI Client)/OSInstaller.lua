-- OSInstaller.lua
-- Installs GUI version along with it's dependencies without using Basalt to be as lightweight as possible
-- User can pick a package to install
-- Barebones package  Only the client GUI and it's dependencies with NO addons (doesn't have full CLI funcionality)
-- Essentals package  Installs client GUI with all the CLI functionality
-- Full package  Installs all Modules for GUI
-- VERY WIP right now all packages are barebones, I don't have all the apps I want made yet
--[[ CLI and GUI will both have access to all the same programs, CLI will launch programs in 
their CLI versions while GUI will launch programs in their GUI versions, CLI will also have 
more technical abilities like ping or  (useless to make GUI version) --]]

for i=1,2 do
    term.clear()
    term.setCursorPos(1,1)
    print("Making reqired Directories.")
    os.sleep(0.5)
    term.clear()
    term.setCursorPos(1,1)
    print("Making reqired Directories..")
    os.sleep(0.5)
    term.clear()
    term.setCursorPos(1,1)
    print("Making reqired Directories...")
    os.sleep(0.5)
end
fs.makeDir("/Dependencies/")
fs.makeDir("/Apps/")
fs.makeDir("/Configs/")
os.sleep(0.5)

local function printPicker()
    term.setTextColor(colors.blue)
    term.clear()
    term.setCursorPos(1,1)
    print("Choose your package: | Barebones | Essentials | \n| Full |")
    term.setTextColor(colors.green)
    print("Barebones package: Only the ToasterOvenOS and it's dependencies with NO addons (doesn't have all the CLI's funcionality)")
    term.setTextColor(colors.cyan)
    print("Essentals package: Installs ToasterOvenOS with all the CLI's functionality")
    term.setTextColor(colors.blue)
    print("Full package: Installs all Modules for ToasterOvenOS")
    term.setTextColor(colors.white)
end

local function areYouSure()
    print("Are you sure? | Yes | No |")
    local asking = true
    while asking do
        local event, button, x, y = os.pullEvent("mouse_click")
        if x>=16 and x<=20 and y == 2 then
            return true
        elseif x>=22 and x<=25 and y == 2 then
            return false
        else
            print("click y or n")
        end
    end

end

-- autostart setup
local function ensureStartup()
    local startupContent = ""
    if fs.exists("startup") then
        local f = fs.open("startup","r")
        startupContent = f.readAll()
        f.close()
    end
    if not startupContent:match("shell%.run%(\'toasterOvenOS.lua\'%)") then
        local f = fs.open("startup","a")
        f.writeLine("shell.run('toasterOvenOS.lua')")
        f.close()
    end
end

-- Barebones package installer
local function barebones()
    term.clear()
    term.setCursorPos(1,1) 
    print("Chose Barebones")
    os.sleep(1)
    local yn = areYouSure()
    if yn then
        print("Downlaoding Full Package")
        print("Starting with Dependencies")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Dependencies/client.lua client.lua")
        fs.move("client.lua","/Dependencies/")
        print("Installed Client")
        shell.run("wget run https://raw.githubusercontent.com/Pyroxenium/Basalt/refs/heads/master/docs/install.lua release latest.lua")
        fs.move("basalt.lua","/Dependencies/")
        print("Installed Basalt")
        print("ToasterOvenOS Installing")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/toasterOvenOS.lua clientGUI.lua")
        print("Installed GUI")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Apps/intaller.lua installer.lua")
        print("Installed Installer (for addons)")
        print("OS Installed")

        print("Ensuring that OS starts on computer boot")
        ensureStartup()
        return false
    else
        print("Aborting Download")
        os.sleep(1)
        printPicker()
        return true
    end
end
-- Essentials package installer
local function essentials()
    term.clear()
    term.setCursorPos(1,1)
    print("Chose Essentials")
    os.sleep(1)
    local yn = areYouSure()
    if yn then
        print("Downlaoding Full Package")
        print("Starting with Dependencies")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Dependencies/client.lua client.lua")
        fs.move("client.lua","/Dependencies/")
        print("Installed Client")
        shell.run("wget run https://raw.githubusercontent.com/Pyroxenium/Basalt/refs/heads/master/docs/install.lua release latest.lua")
        fs.move("basalt.lua","/Dependencies/")
        print("Installed Basalt")
        print("ToasterOvenOS Installing")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/toasterOvenOS.lua clientGUI.lua")
        print("Installed GUI")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Apps/intaller.lua installer.lua")
        print("Installed Installer (for addons)")
        print("OS Installed")

        print("Ensuring that OS starts on computer boot")
        ensureStartup()
        return false
    else
        print("Aborting Download")
        os.sleep(1)
        printPicker()
        return true
    end
end
-- Full package installer
local function full()
    term.clear()
    term.setCursorPos(1,1)
    print("Chose Full")
    os.sleep(1)
    local yn = areYouSure()
    if yn then
        print("Downlaoding Full Package")
        print("Starting with Dependencies")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Dependencies/client.lua client.lua")
        fs.move("client.lua","/Dependencies/")
        print("Installed Client")
        shell.run("wget run https://raw.githubusercontent.com/Pyroxenium/Basalt/refs/heads/master/docs/install.lua release latest.lua")
        fs.move("basalt.lua","/Dependencies/")
        print("Installed Basalt")
        print("ToasterOvenOS Installing")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/toasterOvenOS.lua clientGUI.lua")
        print("Installed GUI")
        shell.run("wget https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/ToasterOvenOS%20(GUI%20Client)/Apps/intaller.lua installer.lua")
        print("Installed Installer (for addons)")
        print("OS Installed")

        print("Ensuring that OS starts on computer boot")
        ensureStartup()
        return false
    else
        print("Aborting Download")
        os.sleep(1)
        printPicker()
        return true
    end
end
-- Listens for user input
local function listener()
    printPicker()
    local downloading = true
    while downloading do
        local event, button, x, y = os.pullEvent("mouse_click")
        if x >= 23 and x <= 33 and y == 1 then
            downloading = barebones()
        elseif x>=35 and x<=46 and y==1 then
            downloading = essentials()
        elseif x>=1 and x<=7 and y==2 then
            downloading = full()
        end
    end
end

listener()


