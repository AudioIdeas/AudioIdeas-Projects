--[[
@description Post-fader-insert
@version 1.22
@author Vesa Laasanen
@changelog
   1.22:
   GUI toggle for mute/solo mode, persisted via ExtState
   Support FX containers (recursive)
   1.13:
   Fix bug with finding plugins with pathnames
   1.11:
   Fix bug with opening a project
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

   Mute/Solo Mode:
     The script window has a toggle button for "Mute/Solo Mode". When off (default), REAPER
     handles mute/solo natively - use this for folder tracks and Dolby Atmos Composer. When on,
     the script controls mute/solo via the JSFX plugins - use this for Airwindows Console.
     The setting is saved globally and persists across REAPER restarts.

   Dependencies:
     - None
--]]


local EXT_SECTION = "post_fader_insert"
local EXT_KEY = "enable_mute_solo"
local volumeDelay = 0.1
local pluginDelay = 1.0
local lastVolumes = {}
local lastTrackVolumes = {}
local lastTrimVolumes = {}
local lastMutes = {}
local lastSolos = {}
local lastFXCounts = {}
local lastPluginCheckTime = reaper.time_precise()
local lastPosition = reaper.GetPlayPosition()

local guiW = 220
local guiH = 50
local btnX = 10
local btnY = 10
local btnW = 200
local btnH = 30
local mouseWasDown = false

function GetEnableMuteSolo()
    local val = reaper.GetExtState(EXT_SECTION, EXT_KEY)
    return val == "1"
end

function SetEnableMuteSolo(val)
    reaper.SetExtState(EXT_SECTION, EXT_KEY, val and "1" or "0", true)
end

function InitGUI()
    gfx.init("Post-Fader Insert", guiW, guiH, 0)
    gfx.setfont(1, "Arial", 13)
end

function UpdateGUI()
    local enabled = GetEnableMuteSolo()
    local label = enabled and "Mute/Solo: ON (Internal)" or "Mute/Solo: OFF (Native)"
    if enabled then
        gfx.set(0.3, 0.5, 0.3, 1)
    else
        gfx.set(0.3, 0.3, 0.4, 1)
    end
    gfx.rect(btnX, btnY, btnW, btnH)
    gfx.set(1, 1, 1, 1)
    local strW, strH = gfx.measurestr(label)
    gfx.x = btnX + (btnW - strW) / 2
    gfx.y = btnY + (btnH - strH) / 2
    gfx.drawstr(label)
    gfx.update()
end

function HandleGUIClick()
    local char = gfx.getchar()
    if char == -1 then return false end
    local mouseDown = gfx.mouse_cap & 1 == 1
    local inBtn = gfx.mouse_x >= btnX and gfx.mouse_x <= btnX + btnW
                  and gfx.mouse_y >= btnY and gfx.mouse_y <= btnY + btnH
    if mouseDown and not mouseWasDown and inBtn then
        SetEnableMuteSolo(not GetEnableMuteSolo())
        local track_count = reaper.CountTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local fxs = FindPostFaderFX(track)
            if #fxs > 0 then
                if GetEnableMuteSolo() then
                    UpdateTrackJSFXMute(track, i)
                    UpdateTrackJSFXSolo(track, i)
                else
                    ResetMuteSolo(track, i)
                end
            end
        end
    end
    mouseWasDown = mouseDown
    return true
end

function ResetMuteSolo(track, trackIndex)
    local fxs = FindPostFaderFX(track)
    for _, fx in ipairs(fxs) do
        if containsIgnoreCase(fx.name, "start") then
            reaper.TrackFX_SetParam(track, fx.idx, 1, 0)
            reaper.TrackFX_SetParam(track, fx.idx, 2, 0)
            reaper.TrackFX_SetParam(track, fx.idx, 3, 0)
        end
    end
end

function solosActive()
    for _, value in pairs(lastSolos) do
        if value ~= 0 then
            return true
        end
    end
    return false
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
    local currentPosition = reaper.GetCursorPosition()
    if currentPosition ~= lastPosition then
        lastPosition = currentPosition
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
    if volumeEnvelope and IsEnvelopeActive(volumeEnvelope) then
        local retval, value = reaper.Envelope_Evaluate(volumeEnvelope, position, 0, 0)
        local scaledValue = reaper.ScaleFromEnvelopeMode(reaper.GetEnvelopeScalingMode(volumeEnvelope), value)
        if retval then
            lastTrackVolumes[trackIndex] = scaledValue
        end
    else
        lastTrackVolumes[trackIndex] = 1
    end
    if trimVolumeEnvelope and IsEnvelopeActive(trimVolumeEnvelope) then
        local retval, value = reaper.Envelope_Evaluate(trimVolumeEnvelope, position, 0, 0)
        local scaledValue = reaper.ScaleFromEnvelopeMode(reaper.GetEnvelopeScalingMode(trimVolumeEnvelope), value)
        if retval then
            lastTrimVolumes[trackIndex] = scaledValue
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
        if GetEnableMuteSolo() then
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
end

function UpdatePluginsIfNeeded()
    local currentTime = reaper.time_precise()
    if currentTime - lastPluginCheckTime >= pluginDelay then
        CheckAndHandlePluginChanges()
        lastPluginCheckTime = currentTime
    end
end

function CheckAndHandlePluginChanges()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local fx_count = reaper.TrackFX_GetCount(track)
        if not lastFXCounts[i] or lastFXCounts[i] ~= fx_count then
            lastFXCounts[i] = fx_count
            local fxs = FindPostFaderFX(track)
            if #fxs > 0 then
                UpdateTrackJSFXVolume(track, i)
                if GetEnableMuteSolo() then
                    UpdateTrackJSFXMute(track, i)
                    UpdateTrackJSFXSolo(track, i)
                else
                    ResetMuteSolo(track, i)
                end
            end
        end
    end
end

function containsIgnoreCase(fullString, substring)
    local lowerFullString = fullString:lower()
    local lowerSubstring = substring:lower()
    return lowerFullString:find(lowerSubstring, 1, true) ~= nil
end

function EnumerateFXRecursive(track, fxIndex, results, stride, containerBase)
    local retval, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "")
    if retval and containsIgnoreCase(fx_name, "post-fader") then
        if containsIgnoreCase(fx_name, "end") or
           containsIgnoreCase(fx_name, "start") or
           containsIgnoreCase(fx_name, "helper") then
            table.insert(results, { idx = fxIndex, name = fx_name })
        end
    end
    local ok, cnt = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "container_count")
    if ok and cnt then
        local childCount = tonumber(cnt)
        if childCount and childCount > 0 then
            local base
            if containerBase then
                base = containerBase
            else
                base = fxIndex + 1
            end
            for c = 0, childCount - 1 do
                local childIdx = 0x2000000 + (c + 1) * stride + base
                EnumerateFXRecursive(track, childIdx, results, stride, childIdx - 0x2000000)
            end
        end
    end
end

function FindPostFaderFX(track)
    local results = {}
    local fx_count = reaper.TrackFX_GetCount(track)
    local stride = fx_count + 1
    for j = 0, fx_count - 1 do
        EnumerateFXRecursive(track, j, results, stride, nil)
    end
    return results
end

function UpdateTrackJSFXVolume(track, trackIndex)
    local fxs = FindPostFaderFX(track)
    for _, fx in ipairs(fxs) do
        local param_index = 0
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
        local totalAmplitude = volume * trackVolume * trimVolume
        local totalVolume = 20 * math.log(totalAmplitude, 10)
        reaper.TrackFX_SetParam(track, fx.idx, param_index, totalVolume)
    end
end

function UpdateTrackJSFXMute(track, trackIndex)
    local fxs = FindPostFaderFX(track)
    for _, fx in ipairs(fxs) do
        if containsIgnoreCase(fx.name, "start") then
            local param_index = 1
            local mute = lastMutes[trackIndex]
            if not lastMutes[trackIndex] then
                mute = 0
            end
            reaper.TrackFX_SetParam(track, fx.idx, param_index, mute)
        end
    end
end

function UpdateTrackJSFXSolo(track, trackIndex)
    local solo_index = 2
    local solo_other_index = 3
    local fxs = FindPostFaderFX(track)
    for _, fx in ipairs(fxs) do
        if containsIgnoreCase(fx.name, "start") then
            local solo = lastSolos[trackIndex]
            if not lastSolos[trackIndex] then
                solo = 0
            end
            reaper.TrackFX_SetParam(track, fx.idx, solo_index, solo)
            reaper.TrackFX_SetParam(track, fx.idx, solo_other_index, 0)
        end
    end
    local solosAreActive = 0
    if solosActive() then
        solosAreActive = 1
    end
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local trk = reaper.GetTrack(0, i)
        local allFxs = FindPostFaderFX(trk)
        for _, fx in ipairs(allFxs) do
            if containsIgnoreCase(fx.name, "start") then
                if solosAreActive == 0 then
                    reaper.TrackFX_SetParam(trk, fx.idx, solo_other_index, 0)
                else
                    local trackSolo = 1 - reaper.TrackFX_GetParam(trk, fx.idx, solo_index)
                    reaper.TrackFX_SetParam(trk, fx.idx, solo_other_index, trackSolo)
                end
            end
        end
    end
end

function MainLoop()
    if not HandleGUIClick() then return end
    UpdateGUI()
    if reaper.GetPlayState() ~= 0 then
        ProcessTracksWithAutomation()
    else
        ProcessPositionChange()
    end
    UpdateChannel()
    UpdatePluginsIfNeeded()
    reaper.defer(MainLoop)
end

function DelayedStart()
    local startTime = reaper.time_precise()
    local function CheckDelay()
        if reaper.time_precise() - startTime >= volumeDelay then
            InitGUI()
            MainLoop()
        else
            reaper.defer(CheckDelay)
        end
    end
    reaper.defer(CheckDelay)
end

DelayedStart()
