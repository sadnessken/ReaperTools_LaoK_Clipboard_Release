-- @noindex
local info = debug.getinfo(1, "S")
local script_path = info and info.source and info.source:sub(2) or ""
local script_dir = script_path:match("^(.*)[/\\]") or "."

local common = dofile(script_dir .. "/LaoK_Clipboard_Shared.lua")

local function get_user_data_path()
  return common.GetExtState("current_user_data_path")
end

local function log(level, msg)
  local line = string.format("[%s] %s", level, msg)
  common.AppendLog(get_user_data_path(), line)
end

local function ensure_user_data_path()
  local path = common.GetExtState("current_user_data_path")
  if path == "" then
    reaper.ShowMessageBox("No user data file. Open the main UI and New/Load one first.", "LaoK Clipboard", 0)
    return nil
  end
  return path
end

local function load_user_data(path)
  local data, err = common.LoadUserData(path)
  if not data then
    reaper.ShowMessageBox("Load failed: " .. tostring(err), "LaoK Clipboard", 0)
    return nil
  end
  data.pins = data.pins or {}
  data.settings = data.settings or common.DefaultSettings()
  common.EnsureTags(data)
  return data
end

local function get_item_take_paths(item, project_path)
  local paths = {}
  local take_count = reaper.CountTakes(item)
  for t = 0, take_count - 1 do
    local take = reaper.GetTake(item, t)
    local path = ""
    if take then
      local src = reaper.GetMediaItemTake_Source(take)
      if src then
        local filename = common.GetMediaSourceFileNameSafe(src)
        if filename ~= "" then
          path = common.ResolveMaybeRelativePath(filename, project_path)
        end
      end
    end
    paths[#paths + 1] = path
  end
  return paths
end

local function build_item_file_map(item, item_chunk, project_path)
  local raw_paths = common.ExtractFilePathsFromChunkOrdered(item_chunk)
  local abs_paths = get_item_take_paths(item, project_path)
  local map = {}
  for i, raw in ipairs(raw_paths) do
    local abs = abs_paths[i]
    if not abs or abs == "" then
      abs = common.ResolveMaybeRelativePath(raw, project_path)
    end
    if raw and raw ~= "" and abs and abs ~= "" then
      map[raw] = abs
    end
  end
  return map, abs_paths
end

local function replace_chunk_file_paths_map(chunk, map)
  local replaced = chunk:gsub('FILE%s+"(.-)"', function(original)
    local abs = map[original]
    if abs and abs ~= "" then
      return 'FILE "' .. abs .. '"'
    end
    return 'FILE "' .. original .. '"'
  end)
  return replaced
end

local function collect_tracks_for_pin()
  local tracks = {}
  local included = {}
  local selected = {}
  local selected_count = reaper.CountSelectedTracks(0)
  for i = 0, selected_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      selected[track] = true
    end
  end

  local track_count = reaper.CountTracks(0)
  local i = 0
  while i < track_count do
    local track = reaper.GetTrack(0, i)
    if included[track] then
      i = i + 1
    elseif selected[track] then
      tracks[#tracks + 1] = track
      included[track] = true
      local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0
      if depth > 0 then
        i = i + 1
        while depth > 0 and i < track_count do
          local child = reaper.GetTrack(0, i)
          if not included[child] then
            tracks[#tracks + 1] = child
            included[child] = true
          end
          local child_depth = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") or 0
          depth = depth + child_depth
          i = i + 1
        end
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  return tracks
end

local function collect_internal_sends(selected_tracks)
  local slot_by_track = {}
  for slot, track in ipairs(selected_tracks) do
    slot_by_track[track] = slot
  end

  local keys = {
    "D_VOL",
    "D_PAN",
    "D_PANLAW",
    "I_SENDMODE",
    "I_SRCCHAN",
    "I_DSTCHAN",
    "I_MIDIFLAGS",
    "B_MUTE",
    "B_PHASE",
    "B_MONO",
  }

  local sends = {}
  for slot, track in ipairs(selected_tracks) do
    local send_count = reaper.GetTrackNumSends(track, 0)
    for i = 0, send_count - 1 do
      local dest = reaper.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
      local dst_slot = slot_by_track[dest]
      if dst_slot then
        local send = {
          src_slot = slot,
          dst_slot = dst_slot,
          params = {},
        }
        for _, key in ipairs(keys) do
          send.params[key] = reaper.GetTrackSendInfo_Value(track, 0, i, key)
        end
        sends[#sends + 1] = send
      end
    end
  end
  return sends
end

local function pin_items(project_path)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return nil, "Nothing selected" end

  local items = {}
  local media = {}
  local seen_media = {}
  local anchor_pos = nil
  local base_track_index = nil
  local default_name = nil

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local ok, chunk = reaper.GetItemStateChunk(item, "", false)
    if not ok then
      return nil, "Failed to read item chunk"
    end
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if not anchor_pos or pos < anchor_pos then
      anchor_pos = pos
    end
    local track = reaper.GetMediaItemTrack(item)
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    if not base_track_index or track_index < base_track_index then
      base_track_index = track_index
    end

    if not default_name then
      local take = reaper.GetActiveTake(item)
      if take then
        default_name = reaper.GetTakeName(take)
      end
      if not default_name or default_name == "" then
        local ok_notes, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if ok_notes and notes ~= "" then
          default_name = notes
        end
      end
    end

    local file_map, abs_paths = build_item_file_map(item, chunk, project_path)
    local replaced_chunk = replace_chunk_file_paths_map(chunk, file_map)

    items[#items + 1] = {
      chunk = replaced_chunk,
      pos = pos,
      track_index = track_index,
    }

    for _, path in ipairs(abs_paths) do
      if path ~= "" and not seen_media[path] then
        seen_media[path] = true
        media[#media + 1] = {
          src_path = path,
          src_size = common.GetFileSize(path) or 0,
          src_mtime = common.GetFileModTime(path) or 0,
        }
      end
    end
    for _, path in pairs(file_map) do
      if path ~= "" and not seen_media[path] then
        seen_media[path] = true
        media[#media + 1] = {
          src_path = path,
          src_size = common.GetFileSize(path) or 0,
          src_mtime = common.GetFileModTime(path) or 0,
        }
      end
    end
  end

  for _, item in ipairs(items) do
    item.offset = item.pos - anchor_pos
    item.pos = nil
  end

  return {
    pin_type = "ITEMS",
    payload = {
      anchor_mode = "RELATIVE_TO_FIRST_ITEM_START",
      anchor_pos = anchor_pos or 0,
      base_track_index = base_track_index or 1,
      items = items,
      tracks = {},
    },
    media = media,
    default_name = default_name,
  }
end

local function pin_tracks(project_path)
  local count = reaper.CountSelectedTracks(0)
  if count == 0 then return nil, "Nothing selected" end

  local tracks = {}
  local items = {}
  local media = {}
  local seen_media = {}
  local default_name = nil
  local selected_tracks = collect_tracks_for_pin()
  if #selected_tracks == 0 then
    return nil, "Nothing selected"
  end

  local anchor_pos = nil
  for _, track in ipairs(selected_tracks) do
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      if not anchor_pos or pos < anchor_pos then
        anchor_pos = pos
      end
    end
  end
  if not anchor_pos then anchor_pos = 0 end

  local sends = collect_internal_sends(selected_tracks)

  for slot, track in ipairs(selected_tracks) do
    local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
    if not ok then
      return nil, "Failed to read track chunk"
    end
    if common.StripItemBlocksFromTrackChunk then
      chunk = common.StripItemBlocksFromTrackChunk(chunk)
    end
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    if not default_name then
      local ok_name, name = reaper.GetTrackName(track, "")
      if ok_name and name ~= "" then
        default_name = name
      end
    end
    tracks[#tracks + 1] = {
      chunk = chunk,
      track_index = track_index,
      track_slot = slot,
    }
  end

  for slot, track in ipairs(selected_tracks) do
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local ok_item, item_chunk = reaper.GetItemStateChunk(item, "", false)
      if ok_item then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local file_map, abs_paths = build_item_file_map(item, item_chunk, project_path)
        local replaced_chunk = replace_chunk_file_paths_map(item_chunk, file_map)

        items[#items + 1] = {
          chunk = replaced_chunk,
          offset = pos - anchor_pos,
          abs_pos = pos,
          track_slot = slot,
        }

        for _, path in ipairs(abs_paths) do
          if path ~= "" and not seen_media[path] then
            seen_media[path] = true
            media[#media + 1] = {
              src_path = path,
              src_size = common.GetFileSize(path) or 0,
              src_mtime = common.GetFileModTime(path) or 0,
            }
          end
        end
        for _, path in pairs(file_map) do
          if path ~= "" and not seen_media[path] then
            seen_media[path] = true
            media[#media + 1] = {
              src_path = path,
              src_size = common.GetFileSize(path) or 0,
              src_mtime = common.GetFileModTime(path) or 0,
            }
          end
        end
      end
    end
  end

  return {
    pin_type = "TRACKS",
    payload = {
      anchor_mode = "RELATIVE_TO_FIRST_ITEM_START",
      anchor_pos = anchor_pos,
      absolute_items = true,
      base_track_index = nil,
      items = items,
      tracks = tracks,
      sends = sends,
    },
    media = media,
    default_name = default_name,
  }
end

local function default_pin_name(pin_type, payload)
  if pin_type == "ITEMS" then
    if #payload.items == 1 then
      if payload.default_name and payload.default_name ~= "" then
        return payload.default_name
      end
      return "Item Pin"
    end
    return string.format("Items (%d)", #payload.items)
  end
  if #payload.tracks == 1 then
    if payload.default_name and payload.default_name ~= "" then
      return payload.default_name
    end
    return "Track Pin"
  end
  return string.format("Tracks (%d)", #payload.tracks)
end

local function run()
  local path = ensure_user_data_path()
  if not path then return end

  local data = load_user_data(path)
  if not data then return end

  local selected_tag_id = common.GetExtState("selected_tag_id")
  if selected_tag_id == "" then
    selected_tag_id = (data.tags and data.tags[1] and data.tags[1].tag_id) or "default"
  end
  local tag_valid = false
  for _, tag in ipairs(data.tags or {}) do
    if tag.tag_id == selected_tag_id then
      tag_valid = true
      break
    end
  end
  if not tag_valid then
    selected_tag_id = (data.tags and data.tags[1] and data.tags[1].tag_id) or "default"
  end

  local proj, proj_path, proj_name = common.GetCurrentProject()

  local pin_data, err = pin_items(proj_path)
  if not pin_data then
    pin_data, err = pin_tracks(proj_path)
  end
  if not pin_data then
    reaper.ShowMessageBox(err or "Nothing selected", "LaoK Clipboard", 0)
    return
  end

  local pin_id = common.GenerateId()
  local pin = {
    pin_id = pin_id,
    pin_name = default_pin_name(pin_data.pin_type, {
      items = pin_data.payload.items,
      tracks = pin_data.payload.tracks,
      default_name = pin_data.default_name,
    }),
    pin_type = pin_data.pin_type,
    created_at = common.IsoNowUtc(),
    tag_id = selected_tag_id,
    source_hint = {
      project_name = proj_name,
      project_path = proj_path,
    },
    media = pin_data.media,
    payload = pin_data.payload,
  }

  data.pins[#data.pins + 1] = pin

  local ok, save_err = common.SaveUserData(path, data)
  if not ok then
    reaper.ShowMessageBox("Save failed: " .. tostring(save_err), "LaoK Clipboard", 0)
    return
  end

  common.SetExtState("selected_pin_id", pin_id)
  common.SetExtState("current_user_data_path", path)
  common.SetExtState("last_user_data_path", path)
  common.SetExtState("is_dirty", "0")

  local report = {
    action = "pin",
    pin_id = pin_id,
    pin_type = pin.pin_type,
    item_count = #pin.payload.items,
    track_count = #pin.payload.tracks,
    media_count = #pin.media,
    timestamp = common.IsoNowUtc(),
  }
  common.SetExtState("last_report_json", common.JsonEncode(report))

  log("INFO", string.format("Pin saved: id=%s type=%s items=%d tracks=%d media=%d", pin_id, pin.pin_type, #pin.payload.items, #pin.payload.tracks, #pin.media))
  reaper.ShowMessageBox("Pin saved.", "LaoK Clipboard", 0)
end

run()
