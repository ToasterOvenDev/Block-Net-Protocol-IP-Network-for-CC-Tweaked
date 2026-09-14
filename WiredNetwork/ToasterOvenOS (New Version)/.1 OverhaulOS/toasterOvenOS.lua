-- ToasterOvenOS
-- This is the main file that will get ran and manages all other files

package.path = package.path .. ";./.Dependencies/?.lua"
package.path = package.path .. ";../?.lua"

local basalt = require("basalt")

MainFrame = basalt.getMainFrame()
MainFrameW = MainFrame.getWidth()
MainFrameH = MainFrame.getHeight()
ColorPallete = { primary = colors.white, secondary = colors.blue, tritary = colors.red }
Taskbar = nil

local debugFile = "toDebugFile.txt"
if not fs.exists(debugFile) then
    local f = fs.open(debugFile,"w")
    f.write("")
    f.close()
else
    fs.delete(debugFile)
    local f = fs.open(debugFile,"w")
    f.write("")
    f.close()
end

function DebugPrint(msg)
    local time = os.date("%H:%M:%S")
	local f = fs.open(debugFile,"a")
	f.writeLine("[DEBUG "..time.."] " .. msg)
	f.close()
end
