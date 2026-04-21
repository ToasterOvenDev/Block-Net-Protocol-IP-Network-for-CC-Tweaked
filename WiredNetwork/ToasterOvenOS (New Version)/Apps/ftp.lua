package.path = package.path .. ";../Dependencies/?.lua"
local basalt = require("basalt")
local client = require("client")

local myPassword -- Password for peer to peer FTP
local myBNP = client.getBNP()
local FILE_DIR = "/Files/"


-- Need to create a list based on flags so that we can filter host results based on flags
local hosts = {} -- Hosts list from DNS Server (Host Server) or from local dir
local flagslist = {} -- List of flags that exist in ftp capable hosts other than "FTPSVR" or "FTP"
local ftpHosts = {} -- Filted version of hosts to only include FTP capable hosts, key = hostname value = flags table

local function reload()
    hosts = {} -- Empty hosts out
    client.requestFullHosts() -- Update hosts from DNS Server
    hosts = client.getHosts() -- Reload hosts
    flagslist = {} -- Empty out flagslist to get rid of old entries that may be gone
    ftpHosts = {} -- Empty out ftpHosts to get rid of old entries that may be gone
    -- Making a list that only includes FTP capable hosts
    for k in pairs(hosts) do
        for _, v in pairs(hosts[k].flags) do
            if v == "FTPSVR" or v == "FTP" then
                ftpHosts[k] = hosts[k].flags -- Pre-filtered for FTP list
                break
            end
        end
    end
    -- Inserts all flags into a list for filtering later
    for k in pairs(ftpHosts) do
        for _, v in pairs(ftpHosts[k]) do
            if not flagslist[v] and v ~= "FTPSVR" and v ~= "FTP" then -- Filtering list for extra flags
                table.insert(flagslist,v)
            end
        end
    end

end

reload()

local gui = basalt.createFrame():setBackground(colors.cyan)
local helpGUI = gui:addFrame():setPosition(1,1):setSize("parent.w","parent.h"):setBackground(colors.cyan):hide()
gui:addLabel():setText("Host Names") -- Label for Host list
local hostlist = gui:addList():setBackground(colors.lightBlue):setPosition(1,2):setSize(12,10):setScrollable()
local hostEntries = {}

gui:addPane():setSize(35,6):setPosition(15,2):setBackground(colors.lightBlue)
gui:addPane():setSize(35,5):setPosition(15,10):setBackground(colors.lightBlue)
gui:addPane():setSize(37,3):setPosition(15,17):setBackground(colors.lightBlue)

gui:addLabel():setText("Output"):setPosition(16,16) -- Label for File Requesting Frame
local ErrLabel = gui:addLabel():setPosition(16,17):setSize(37,3):setForeground(colors.red):setText("Goes Here")


gui:addLabel():setText("File Requesting"):setPosition(16,1) -- Label for File Requesting Frame
gui:addLabel():setText("Host Name or BNP:"):setPosition(16,3) -- Label for requestee input
local requesteeInput = gui:addInput():setPosition(33,3):setSize(15,1):setDefaultText(" Hostname...") -- BNP or hostname of the requestee

gui:addLabel():setText("Hosts Password:"):setPosition(16,4) -- Label for Password input
local password = gui:addInput():setPosition(31,4):setSize(17,1):setDefaultText(" Password...") -- Input for password for the requestee 

gui:addLabel():setText("Filename:"):setPosition(16,5) -- Label for File input
local fileInput = gui:addInput():setPosition(25,5):setSize(23,1):setDefaultText(" Filename...") -- Input for filename you want to request


gui:addLabel():setText("File Hosting"):setPosition(16,9) -- Label for File Hosting Frame
gui:addLabel():setText("My Password:"):setPosition(16,11) -- Label for myPassword
local myPasswordInput = gui:addInput():setPosition(28,11):setSize(20,1):setDefaultText(" Password...") -- Input for hosting password

gui:addLabel():setText("My Files:"):setPosition(16,12) -- Label for Accessable Files Dir
local filesDir = gui:addInput():setPosition(25,12):setSize(23,1):setDefaultText(" File Direcotry...") -- Input for the files you want to host directory

for k,v in pairs(ftpHosts) do
    hostEntries[k] = hostlist:addItem(k, colors.cyan, colors.black, v) -- List so Users know what hostname translations exist
    hostEntries[k]:onSelect(function(self,event,item)
        if item then
            requesteeInput:setValue(item.text)
        end
    end)
end

gui:addButton():setText("help"):onClick( function() helpGUI:show() end):setPosition(2,13):setSize(6,1):setBackground(colors.cyan)

helpGUI:addLabel():setText("Host List can be clicked to fill in Host Names")
helpGUI:addLabel():setText("File Hosting needs a password and a file directory"):setPosition(1,2)
helpGUI:addLabel():setText("to make available for requesting"):setPosition(1,3)
helpGUI:addLabel():setText("EX:  My Password: 101"):setPosition(1,5)
helpGUI:addLabel():setText("     My Files: /sharefolder/"):setPosition(1,6)

local running = false

local submitreqButton = gui:addButton()
    :setText("Request")
    :setPosition(16,7)
    :setSize(8,1)
    :setBackground(colors.lightBlue)
    :onClick(
        function()
            requestee = requesteeInput:getValue()
            rpass = password:getValue()
            file = fileInput:getValue()
            client.setFile(file)
            os.sleep(0.1)
            client.sendACK(requesteeInput,rpass)
        end)
        
local reloadbutton = gui:addButton()
    :setText("Reload")
    :setPosition(2,15)
    :setSize(8,1)
    :setBackground(colors.cyan)
    :onClick(
        function()
            reload()
        end)
            
local function sendFile(dst, filename)
    local fullPath = FILE_DIR..filename
    if not fs.exists(fullPath) then
        ErrLabel:setText("File not found, aborting file send")
        return
    else
        ErrLabel:setText("Sending ".. filename .." to " .. dst)
    end

    local f = fs.open(fullPath,"r")
    local data = f.readAll()
    f.close()

    local chunks = {}
    for i=1,#data,512 do
        local chunk = data:sub(i, math.min(i+512-1,#data))
        table.insert(chunks,chunk)
    end

    for i,chunk in ipairs(chunks) do
        client.sendPacket(dst,{ type="FILE_CHUNK", filename=filename, seq=i, total=#chunks, data=chunk })
    end
    client.sendPacket(dst,{ type="FILE_END", filename=filename })
end

local function listener()
    running = true
    ErrLabel:setText("Started Hosting waiting for file requests for files from " .. FILE_DIR)
    while true do
        local e, side, ch, reply, message, dist = os.pullEvent("modem_message")
        if type(message)=="table" and myBNP and (message.dst==myBNP or message.dst=="0") then
            local payload = message.payload
            if type(payload)~="table" then
                return
            else
                if payload.type == "ACK_START" then -- A client is trying to establish a connection to transfer a file
                    if not myPassword then
                        ErrLabel:setText("No password set peers can't access files")
                        client.sendPacket(message.src,{ type="ERROR", message="Peer has no password, try messaging them!" })
                    elseif payload.password == myPassword then
                        ErrLabel:setText("Peer trying to establish a connection to download a file, sending an ACK")
                        client.sendPacket(message.src,{ type="ACK" })
                    else
                        client.sendPacket(message.src,{ type="ERROR", message="Invalid password" })
                    end
                elseif payload.type == "ERROR" then -- Error during a file trasfer or any other kind of message
                    ErrLabel:setText("Packet Error: "..(payload.message or "Unknown"))
                elseif payload.type == "FILE_REQUEST" then -- AcK handshake has completed and the file is started to be sent
                    ErrLabel:setText("Peer established a connection and is requesting " .. payload.filename .. " Attempting to send file...")
                    sendFile(message.src,payload.filename)
                else
                    return -- Otherfiles might handle
                end
            end
        end
    end
end

local listenerThread = gui:addThread()

local submithostButton = gui:addButton()
    :setText("Start Hosting")
    :setPosition(20,14)
    :setSize(8,1)
    :setBackground(colors.lightBlue)
    :setForeground(colors.green)

submithostButton:onClick(function()
    myPassword = myPasswordInput:getValue() or ""
    FILE_DIR = fileInput:getValue() or "/"
    if running then
        running = false
        submithostButton:setText("Start Hosting")
        submithostButton:setForeground(colors.green)
        if listenerThread then
            listenerThread:stop()
        end
    else
        submithostButton:setText("Stop Hosting")
        submithostButton:setForeground(colors.red)
        listenerThread:start(listener)
    end
end)
basalt.autoUpdate()