--[[
@description Set hardware insert
@version 1.0
@author Vesa Laasanen
@changelog
  1.0:
  initial version
@about
  # Set-hw-insert
  This Reaper script facilitates the easy setup of hardware inserts using the ReaInsert VST plugin. To tailor this script for various presets, follow the steps below:

  Basic Usage:
    - Create presets in ReaScript plugin for the insert you want to use
    - Modify the Preset Name in the Script: Open the script in a text editor. Locate the line: local preset_name = "MyPreset". Replace "MyPreset" with the exact name of the preset you want the script to use. For instance: local preset_name = "YourDesiredPresetName"
    - Select the track where you wish to apply the hardware insert.
    - Run the script.
    - If the selected track or its subsequent tracks are named HW_INS-(something), the script will replace the ReaInsert plugin on that track. Otherwise, it creates a new child track and configures the ReaInsert plugin with the specified preset on it.

  Customizing for Multiple Presets:
    - Duplicate the Script: Make a copy of the script for each preset you wish to recall.
    - Rename the Script: Give each duplicated script a meaningful name, indicating which preset it's associated with.
    - Modify the Preset Name in each script
--]]


-- Declare parameters
local preset_name = "MyPreset"
local plugin_name = "VST:ReaInsert (Cockos)"
local plugin_real_name = "VST: ReaInsert (Cockos)"

-- Checks if preset is already in use in any track
function check_preset_in_use()
    local total_tracks = reaper.CountTracks(0)

    for i = 0, total_tracks - 1 do
        local track = reaper.GetTrack(0, i)

        for j = 0, reaper.TrackFX_GetCount(track) - 1 do
            local _, fx_name = reaper.TrackFX_GetFXName(track, j, "")

            if fx_name == plugin_real_name then
                local _, current_preset = reaper.TrackFX_GetPreset(track, j, "")

                if current_preset == preset_name then
                    reaper.ShowMessageBox("Insert already used in track " .. tostring(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")), "Warning", 0)
                    return true
                end
            end
        end
    end

    return false
end

-- Adds and configures ReaInsert plugin on a given track
function add_and_configure_plugin(track, fx_index)
    local instantiate_position = -1000 - fx_index
    local fx_idx = reaper.TrackFX_AddByName(track, plugin_name, false, instantiate_position)

    if fx_idx == -1 then
        reaper.ShowMessageBox("Failed to add ReaInsert plugin.", "Error", 0)
        return false
    end

    local preset_loaded = reaper.TrackFX_SetPreset(track, fx_idx, preset_name)

    if preset_loaded == 0 then
        reaper.ShowMessageBox("Failed to load preset.", "Error", 0)
        return false
    end

    return true
end

-- Main script logic
function main()
    reaper.Undo_BeginBlock()

    if check_preset_in_use() then return end

    local count_sel_tracks = reaper.CountSelectedTracks(0)

    if count_sel_tracks ~= 1 then
        reaper.ShowMessageBox("Please select exactly one track", "Error", 0)
        return
    end

    local parent_track = reaper.GetSelectedTrack(0, 0)
    local _, parent_track_name = reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "", false)
    local parent_track_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local item_count = reaper.CountTrackMediaItems(parent_track)

    local child_already_exists = false
    local child_track = nil

    for j = parent_track_idx + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, j)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

        if string.match(track_name, "HW_INS-") then
            for k = j, parent_track_idx + 1, -1 do
                local track_parent = reaper.GetParentTrack(reaper.GetTrack(0, k))

                if track_parent == nil then break end

                if track_parent == parent_track then
                    child_already_exists = true
                    child_track = track
                    break
                end
            end
        end

        if child_already_exists then break end
    end

    if not child_already_exists then
        if parent_track_idx ~= reaper.CountTracks(0) - 1 then
            local track_parent = reaper.GetParentTrack(reaper.GetTrack(0, parent_track_idx + 1))

            if track_parent == parent_track then
                reaper.ShowMessageBox("Select a track with no child tracks", "Error", 0)
                return
            end
        end
    end

    if child_already_exists then
        local fx_index = reaper.TrackFX_AddByName(child_track, plugin_name, false, 0)
        reaper.TrackFX_Delete(child_track, fx_index)
        if not add_and_configure_plugin(child_track, fx_index) then return end
    else
        reaper.InsertTrackAtIndex(parent_track_idx + 1, false)
        child_track = reaper.GetTrack(0, parent_track_idx + 1)

        reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
        reaper.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", -1)
        reaper.GetSetMediaTrackInfo_String(child_track, "P_NAME", "HW_INS-" .. parent_track_name, true)

        for j = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(parent_track, 0)
            reaper.MoveMediaItemToTrack(item, child_track)
        end

        if not add_and_configure_plugin(child_track, -1) then return end
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Apply HW_INS preset", -1)
end

-- Execute the main function
main()
