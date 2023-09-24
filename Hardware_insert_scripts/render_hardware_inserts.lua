@description Render hardware inserts
@version 1.0
@author Vesa Laasanen
@changelog
  1.0:
  initial version

function storeRenderSpeed()
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_STORERENDERSPEED"), 0)
end

function setRenderSpeedToRealTime()
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_SETRENDERSPEEDRT"), 0)
end

function findChildTracks()
  local child_tracks = {}

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if string.match(track_name, "HW_INS-") then
      table.insert(child_tracks, track)
    end
  end

  return child_tracks
end

function freezeChildTracks(child_tracks)
  -- Unselect all tracks first
  reaper.Main_OnCommand(40297, 0)

  -- Select child tracks
  for _, child_track in ipairs(child_tracks) do
    reaper.SetTrackSelected(child_track, true)
  end

  -- Freeze selected tracks to stereo
  reaper.Main_OnCommand(41223, 0)
end

function restoreRenderSpeed()
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_RECALLRENDERSPEED"), 0)
end

-- Main execution
storeRenderSpeed()
setRenderSpeedToRealTime()
local child_tracks = findChildTracks()
freezeChildTracks(child_tracks)
restoreRenderSpeed()
