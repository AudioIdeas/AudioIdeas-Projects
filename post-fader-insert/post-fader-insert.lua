--[[
@description Post-fader-insert
@version 1.10
@author Vesa Laasanen
@changelog
   1.10:
   Mute and solo functionality
   1.02:
   initial version
@about
   # Post-fader-insert script

   This post fader insert functionality requires post-fader-insert.lua script and JS: post-fader-fx-start and JS: post-fader-fx-end plugins. The script monitors channel volume faders, track volume and trim volume automation and sends the combinedvalue to the plugins. You need to have post-fader-insert.lua script running when using the channel plugins.

   Alternatively you can use post-fader-fx-helper plugin to modulate other plugins with post-fader volume parameter.

   Usage Instructions:
     - Run post-fader-insert.lua script
     - Insert JS: post-fader-fx-start and JS: post-fader-fx-end plugins to a channel. Any plugin between these plugins will emulate post-fader insert. JS: post-fader-fx-start multiplies the signal volume by channel fader value and JS: post-fader-fx-end reverses the volume change.
     - Alternatively insert JS: post-fader-fx-helper to a channel. You can now modulate other plugins with post-fader volume parameter.

   Dependencies:
     - None
--]] 


local volumeDelay = 0.1 -- Delay between volume checks
local pluginDelay = 1.0 -- Delay between plugin checks
local lastVolumes = {} -- Last known volumes for each track
local lastTrackVolumes = {} -- Last known track volumes for each track
local lastTrimVolumes = {} -- Last known trim volumes for each track
local lastMutes = {}
local lastSolos = {}
local lastFXCounts = {} -- Last known FX counts for each track
local lastPluginCheckTime = reaper.time_precise() -- Time of the last plugin check
local lastPosition = reaper.GetPlayPosition() -- Initialize with an impossible value

function solosActive()
    for _, value in pairs(lastSolos) do
        if value ~= 0 then
            return true -- Found a non-zero value, return true
        end
    end
    return false -- All values are zero, return false
end

function IsEnvelopeActive(envelope)
    local retval, envelopeStateChunk = reaper.GetEnvelopeStateChunk(envelope, "", false)
    if retval then
        local isActive = string.match(envelopeStateChunk, "ACT (%d)")
        return isActive == "1"
    end
    return false
end

function ProcessPositionChange()
    local currentPosition = reaper.GetCursorPosition() -- Get current position of the playhead
    if currentPosition ~= lastPosition then
        lastPosition = currentPosition -- Update last known position
        ProcessTracksWithAutomation()
    end
end

function HasVolumeAutomation(track)
    local volumeEnvelope = reaper.GetTrackEnvelopeByName(track, "Volume")
    local trimVolumeEnvelope = reaper.GetTrackEnvelopeByName(track, "Trim Volume")
    if volumeEnvelope or trimVolumeEnvelope then
        return true
    end
    return false
end

function ProcessTracksWithAutomation()
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if HasVolumeAutomation(track) then
            ApplyCurrentAutomationVolume(track, i)
        end
    end
end

function ApplyCurrentAutomationVolume(track, trackIndex)
    local volumeEnvelope = reaper.GetTrackEnvelopeByName(track, "Volume")
    local trimVolumeEnvelope = reaper.GetTrackEnvelopeByName(track, "Trim Volume")
    local position
    if reaper.GetPlayState() ~= 0 then
        position = reaper.GetPlayPosition()
    else 
        position = lastPosition
    end
    if IsEnvelopeActive(volumeEnvelope) then
        if volumeEnvelope then
            local retval, value = reaper.Envelope_Evaluate(volumeEnvelope, position, 0, 0)
            local scaledValue = reaper.ScaleFromEnvelopeMode(reaper.GetEnvelopeScalingMode(volumeEnvelope), value)
            if retval then
              lastTrackVolumes[trackIndex] = scaledValue 
            end
        end
    else
        lastTrackVolumes[trackIndex] = 1
    end
    if IsEnvelopeActive(trimVolumeEnvelope) then
        if trimVolumeEnvelope then
            local retval, value = reaper.Envelope_Evaluate(trimVolumeEnvelope, position, 0, 0)
            local scaledValue = reaper.ScaleFromEnvelopeMode(reaper.GetEnvelopeScalingMode(trimVolumeEnvelope), value)
            if retval then
                lastTrimVolumes[trackIndex] =  scaledValue
            end
        end
    else
        lastTrimVolumes[trackIndex] = 1
    end
    UpdateTrackJSFXVolume(track, trackIndex)
end


function UpdateChannel()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
        if not lastVolumes[i] or lastVolumes[i] ~= volume then
            lastVolumes[i] = volume
            UpdateTrackJSFXVolume(track, i)
        end
        local mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        if not lastMutes[i] or lastMutes[i] ~= mute then
            lastMutes[i] = mute
            UpdateTrackJSFXMute(track, i)
        end
        local solo = reaper.GetMediaTrackInfo_Value(track, "I_SOLO")
        if not lastSolos[i] or lastSolos[i] ~= solo then
            lastSolos[i] = solo
            UpdateTrackJSFXSolo(track, i)
        end
    end
end        


-- Checks and updates the plugin count, if necessary
function UpdatePluginsIfNeeded()
    local currentTime = reaper.time_precise()
    if currentTime - lastPluginCheckTime >= pluginDelay then
        CheckAndHandlePluginChanges()
        lastPluginCheckTime = currentTime
    end
end

-- Handles plugin changes for each track
function CheckAndHandlePluginChanges()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local fx_count = reaper.TrackFX_GetCount(track)
        if not lastFXCounts[i] or lastFXCounts[i] ~= fx_count then
            lastFXCounts[i] = fx_count
            for j = 0, fx_count - 1 do
                local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
                if retval and (fx_name:find("JS: Post-fader-insert-start", 1, true) or fx_name:find("JS: Post-fader-insert-end", 1, true) or fx_name:find("JS: Post-fader-insert-helper", 1, true)) then
                    local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
                    UpdateTrackJSFXVolume(track, i)
                    local mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
                    UpdateTrackJSFXMute(track, i)
                    local solo = reaper.GetMediaTrackInfo_Value(track, "I_SOLO")
                    UpdateTrackJSFXSolo(track, i)
                end
            end
        end
    end
end

-- Updates the volume of JS FX for a specific track
function UpdateTrackJSFXVolume(track, trackIndex)
    local fx_count = reaper.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
        local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
        if retval and (fx_name:find("JS: Post-fader-insert-start", 1, true) or fx_name:find("JS: Post-fader-insert-end", 1, true) or fx_name:find("JS: Post-fader-insert-helper", 1, true)) then
            local param_index = 0 -- Assuming the volume par ameter index is 0
            local volume = lastVolumes[trackIndex]
            local trackVolume = lastTrackVolumes[trackIndex]
            local trimVolume = lastTrimVolumes[trackIndex]
            if not lastVolumes[trackIndex] then
              volume = 1
            end
            if not lastTrackVolumes[trackIndex] then
              trackVolume = 1
            end
            if not lastTrackVolumes[trackIndex] then
              trimVolume = 1
            end
            local totalAmplitude = volume*trackVolume*trimVolume
            totalVolume = 20 * math.log(totalAmplitude,10)
            reaper.TrackFX_SetParam(track, j, param_index, totalVolume)
        end
    end
end

function UpdateTrackJSFXMute(track, trackIndex)
    local fx_count = reaper.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
        local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
        if retval and (fx_name:find("JS: Post-fader-insert-start", 1, true) ) then
            local param_index = 1 -- Assuming the mute parameter index is 1
            local mute = lastMutes[trackIndex]
            if not lastMutes[trackIndex] then
              mute = 0
            end
            reaper.TrackFX_SetParam(track, j, param_index, mute)
        end
    end
end

function UpdateTrackJSFXSolo(track, trackIndex)
    local fx_count = reaper.TrackFX_GetCount(track)
    local solo_index = 2 -- Assuming the solo parameter index is 2
    local solo_other_index = 3 -- Assuming the solo parameter index is 2 
    for j = 0, fx_count - 1 do
        local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
        if retval and (fx_name:find("JS: Post-fader-insert-start", 1, true) ) then
            local solo = lastSolos[trackIndex]
            if not lastSolos[trackIndex] then
              solo = 0
            end
            reaper.TrackFX_SetParam(track, j, solo_index, solo)
            reaper.TrackFX_SetParam(track, j, solo_other_index, 0)
        end
    end
    local solosAreActive = 0
    if solosActive() then
        solosAreActive = 1
    end
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local fx_count = reaper.TrackFX_GetCount(track)
        for j = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
            if retval and (fx_name:find("JS: Post-fader-insert-start", 1, true) ) then
                if solosAreActive == 0 then
                    reaper.TrackFX_SetParam(track, j, solo_other_index, 0)
                else
                    local trackSolo = 1 - reaper.TrackFX_GetParam(track, j, solo_index)
                    reaper.TrackFX_SetParam(track, j, solo_other_index, trackSolo)
                end
            end 
        end
    end    
end

-- Main loop function, managing delay execution and calling update functions
function MainLoop() 
    if reaper.GetPlayState() ~= 0 then -- If REAPER is playing
        ProcessTracksWithAutomation()
    else
        ProcessPositionChange()
    end
    UpdateChannel() 
    UpdatePluginsIfNeeded()

    -- Schedule the next update using deferred execution
    reaper.defer(MainLoop)
end

-- Initial delay setup to kickstart the loop after the specified delay
function DelayedStart()
    local startTime = reaper.time_precise()
    local function CheckDelay()
        if reaper.time_precise() - startTime >= volumeDelay then
            MainLoop()
        else
            reaper.defer(CheckDelay)
        end
    end
    reaper.defer(CheckDelay)
end

DelayedStart() -- Start the script
