-- Updates or installs files from the unstable branch on github

local function update(filename, webpage) -- Installs the files from github
	if fs.exists(filename) then -- Checks if file provided exsists
		fs.delete(filename) -- Deletes it if it does
		print("Deleted old "..filename)
	else -- If it doesn't exist it installs it
		print(filename.."not found. Installing "..filename)
	end

	shell.run("wget "..webpage.." "..filename) -- Runs the install command using provided URL and the filename
	print("Downloaded latest stable "..filename)
end

local function cliLoop()
    term.setTextColor(colors.red)
    print("UPDATER MUST BE RAN IN SAME DIR AS FILE YOU WANT TO UPDATE")
    term.setTextColor(colors.white)
    print("Updater ready. Command arguments:")
    print("router, client, switch, fileServer, hostServer, updater, cellTower, wirelessClient")
    while true do
       	term.setTextColor(colors.yellow)
        io.write("> ")
        term.setTextColor(colors.white)
        local line = io.read()
        if not line then break end
        local cmd = line:lower()
        if cmd=="router" then -- Installs router
       		update("router.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WiredNetwork/Router.lua")
			break
        elseif cmd=="client" then -- Installs CLI version of client
       		update("client.lua", "https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WiredNetwork/Client.lua")
			break
		elseif cmd=="wirelessclient" then -- Installs Wireless Client
        	update("wirelessClient.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WirelessNetwork/wirelessClient.lua")
			break
        elseif cmd=="switch" then -- Installs wireless Client
            update("switch.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WiredNetwork/switch.lua")
			break
        elseif cmd=="fileserver" then -- Installs File Server
            update("fileServer.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WiredNetwork/FileServer.lua")
			break
        elseif cmd=="dnsServer" then -- Installs DNS Server
            update("dnsserver.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WiredNetwork/dnsServer.lua")
			break
		elseif cmd=="celltower" then -- Installs Cell Tower
            update("cellTower.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/WirelessNetwork/cellTower.lua")
			break
        elseif cmd=="updater" then -- Updates the Updater to latest version
            update("updater.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Unstable/UtilityFiles/unstableUpdater.lua")
			break
        elseif cmd=="quit" then -- Aborts the installer
            break
        else -- Prints a helper if the command isn't recongnized
           	print("Usage: router | client | switch | fileServer | hostServer | updater | cellTower | wirelessClient | quit")
        end
    end
end

cliLoop()
