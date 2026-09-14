-- This manages the apps running on the OS
-- Keeps tracks of all the apps
-- has a GUI executable that can shutdown apps on the OS
-- Manages the taskbar

local basalt = require("basalt")
local taskManager = {}

taskManager.programs = {} -- The programs currently running
local taskbarW = MainFrameW
local taskbarH = MainFrameH-5
local idNum = 0 -- Amount of programs that have been started on the OS since boot

function taskManager.createTaskbar(frame)
    if not frame then return end -- If we don't have a frame to attach it to return
    Taskbar = frame:addFrame():setY(MainFrameH):setSize(taskbarW,taskbarH):setBackground(ColorPallete.secondary)
    Taskbar:addButton() -- Button that pulls up the taskbar
        :setSize(MainFrameW,1)
        :setBackground(ColorPallete.secondary)
        :setText("/\\")
        :onClick(function(self)
            if self.text == "/\\" then
                Taskbar:setY(5)
                self:setText("\\/")
            elseif self.text == "\\/" then
                Taskbar:setY(MainFrameH)
                self:setText("/\\")
            end
        end)
end

function taskManager.addTask(task, taskName, taskDisplay) -- Task is the frame that a program element is held on
    if not task then return end -- If we don't have a program then we can't start it
    local taskName = taskName or "Task" -- Name of the task to display at the top of the window when it's opened
    local taskDisplay = taskDisplay or string.sub(taskName,1,3) -- Display on the taskbar First 3 characters if one isn't provided
    if taskDisplay.len() > 3 then taskDisplay = string.sub(taskDisplay,1,3) end -- Display cannot be longer than 3 characters

end

function taskManager.destroyTaskbar()
    if Taskbar then
        Taskbar:destroy()
        Taskbar = nil
    else
        DebugPrint("Failed to destroy Taskbar")
    end
end

return taskManager