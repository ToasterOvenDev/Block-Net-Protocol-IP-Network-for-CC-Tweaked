local function update(filename, webpage) -- Installs the files from github
	if fs.exists(filename) then -- Checks if file provided exsists
		fs.delete(filename) -- Deletes it if it does
		print("Deleted old "..filename)
	else -- If it doesn't exist it installs it
		print(filename.."not found. Installing "..filename)
	end

	shell.run("wget "..webpage.." "..filename) -- Runs the install command using provided URL and the filename
	print("Downloaded latest "..filename)
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
        local args = {}
        for word in line:gmatch("%S+") do table.insert(args, word) end
        local cmd = args[1]
        if cmd=="router" then -- Installs router
       		update("router.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/Router.lua")
			print("Routers can also be run with servers installed. Please update any server files on device.")
			break
        elseif cmd=="client" then -- Installs CLI version of client
       		update("client.lua", "https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/Client.lua")
			break
		elseif cmd=="wirelessClient" then -- Installs Wireless Client
        	update("wirelessClient.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WirelessNetwork/wirelessClient.lua")
			break
        elseif cmd=="switch" then -- Installs wireless Client
            update("switch.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/switch.lua")
			break
        elseif cmd=="fileServer" then -- Installs File Server
            update("fileServer.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/FileServer.lua")
			break
        elseif cmd=="hostServer" then -- Installs Host Server
            update("hostServer.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WiredNetwork/hostServer.lua")
			break
		elseif cmd=="cellTower" then -- Installs Cell Tower
            update("cellTower.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/WirelessNetwork/cellTower.lua")
			break
        elseif cmd=="updater" then -- Updates the Updater to latest version
            update("updater.lua","https://raw.githubusercontent.com/ToasterOvenDev/Block-Net-Protocol-IP-Network-for-CC-Tweaked/refs/heads/Stable/UtilityFiles/Updater.lua")
			break
        elseif cmd=="quit" then -- Aborts the installer
            break
        else -- Prints a helper if the command isn't recongnized
           	print("Usage: router | client | switch | fileServer | hostServer | updater | cellTower | wirelessClient | quit") 
        end
    end
end

cliLoop()
