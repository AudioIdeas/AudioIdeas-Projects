--[[
@description Generate hardware insert scripts from ReaInsert presets
@version 1.0
@author Vesa Laasanen
@changelog
  1.0:
  Initial version
@about
 # Generate-hw-insert-scripts-from-presets
 This Reaper script automates the generation of individual hardware insert scripts using presets from the ReaInsert VST plugin. When executed, the script will:

 1. Scan for available ReaInsert presets.
 2. For each found preset, duplicate the `set-hw-insert.lua` script.
 3. Rename the duplicated scripts according to the associated ReaInsert preset.
 4. Modify the preset name inside each duplicated script accordingly.

 **Usage:**
- Ensure the base script `set-hw-insert.lua` is placed in the correct directory.
- Run this script to generate individual insert scripts for each ReaInsert preset.
- The new scripts will be saved under a subdirectory named `Generated_HW_Inserts`.

 **Notes:**
- If you have custom paths or folder structures, ensure you adjust the script accordingly.
- This script assumes that ReaInsert presets are saved in the standard location.
--]]

-- Get Resource Path and OS-specific separator
local resourcePath = reaper.GetResourcePath()
local pathSeparator = package.config:sub(1,1)
local osType = reaper.GetOS()

-- Source directory where the 'set-hw-insert.lua' is located
local sourceDir = resourcePath .. pathSeparator .. "Scripts" .. pathSeparator .. "Audioideas ReaScripts" .. pathSeparator .. "Hardware_insert_scripts"

-- Target directory where the new scripts will be saved
local targetDir = sourceDir .. pathSeparator .. "GeneratedInserts"

-- Check if target directory exists. If not, attempt to create it.
if not reaper.file_exists(targetDir) then
    local success = os.execute("mkdir " .. '"' .. targetDir .. '"')

    -- If directory creation fails, show an error and exit
    if not success then
        local errorMessage = "Failed to create the subdirectory. Please create it manually.\n\nPath: " .. targetDir
        reaper.MB(errorMessage, "Error", 0)
        return
    end
end

-- Read the original script
local sourceScriptPath = sourceDir .. pathSeparator .. "set-hw-insert.lua"
local file = io.open(sourceScriptPath, "r")
local originalScript = file:read("*all")
file:close()

-- Load the preset file
local presetFilePath = resourcePath .. pathSeparator .. "presets" .. pathSeparator .. "vst-reainsert.ini"
local presetFile = io.open(presetFilePath, "r")
local presetsData = presetFile:read("*all")
presetFile:close()

-- Extract and process each preset name
for presetName in presetsData:gmatch("Name=(.-)\n") do
    -- Replace the placeholder in the script with the actual preset name
    local newScript = originalScript:gsub("MyPreset", presetName)

    -- Save the new script
    local newScriptPath = targetDir .. pathSeparator .. "set-hw-insert-" .. presetName .. ".lua"
    local outputFile = io.open(newScriptPath, "w")
    outputFile:write(newScript)
    outputFile:close()
end

reaper.MB("Scripts generated successfully!", "Info", 0)
