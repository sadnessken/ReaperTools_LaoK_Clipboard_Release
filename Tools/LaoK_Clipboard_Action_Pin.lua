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

local TRACK_ENV_TAGS = {
  "VOLENV",
  "PANENV",
  "WIDTHENV",
  "VOLENV2",
  "PANENV2",
  "WIDTHENV2",
  "VOLENV3",
  "MUTEENV",
}

local TRACK_ENV_TAGS_ORDER = TRACK_ENV_TAGS

local TRACK_ENV_TAG_SET = {}
for _, tag in ipairs(TRACK_ENV_TAGS) do
  TRACK_ENV_TAG_SET[tag] = true
end

local function get_env_tag_from_chunk(chunk)
  if not chunk or chunk == "" then return nil end
  return chunk:match("<%s*([A-Z0-9_]+)")
end

local function sanitize_env_block(chunk)
  if not chunk or chunk == "" then return nil end
  local lines = {}
  for line in chunk:gmatch("[^\r\n]+") do
    if line == ">" then
      -- skip, re-add later
    elseif line:match("^EGUID%s") then
      -- skip, re-add with new guid
    elseif line:match("^PT%s") or line:match("^AI%s") or line:match("^AIPT%s") or line:match("^AIM%s") then
      -- skip automation data
    else
      lines[#lines + 1] = line
    end
  end
  if #lines == 0 or not lines[1]:match("^<") then
    return nil
  end
  table.insert(lines, 2, "EGUID " .. reaper.genGuid())

  local has_act, has_vis, has_arm = false, false, false
  for i, line in ipairs(lines) do
    if line:match("^ACT%s") then
      lines[i] = line:gsub("^ACT%s+%d+", "ACT 1")
      has_act = true
    elseif line:match("^VIS%s") then
      lines[i] = line:gsub("^VIS%s+[%d%.%-]+%s+[%d%.%-]+%s+[%d%.%-]+", "VIS 1 1 1")
      has_vis = true
    elseif line:match("^ARM%s") then
      lines[i] = line:gsub("^ARM%s+%d+", "ARM 1")
      has_arm = true
    end
  end
  if not has_act then lines[#lines + 1] = "ACT 1" end
  if not has_vis then lines[#lines + 1] = "VIS 1 1 1" end
  if not has_arm then lines[#lines + 1] = "ARM 1" end
  lines[#lines + 1] = ">"
  return table.concat(lines, "\n")
end

local function get_sample_pt(chunk, prefer_not_one)
  if not chunk or chunk == "" then
    return nil, nil
  end
  local first_time, first_value
  for line in chunk:gmatch("[^\r\n]+") do
    if line:sub(1, 2) == "PT" then
      local parts = {}
      for w in line:gmatch("%S+") do
        parts[#parts + 1] = w
      end
      if parts[1] == "PT" and #parts >= 3 then
        local time = tonumber(parts[2])
        local value = tonumber(parts[3])
        if time and value then
          if first_time == nil then
            first_time, first_value = time, value
          end
          if prefer_not_one and math.abs(value - 1) > 1e-6 then
            return time, value
          end
        end
      end
    end
  end
  return first_time, first_value
end

local function find_api_point_by_time(env, target_time)
  if not (reaper.CountEnvelopePoints and reaper.GetEnvelopePoint) then
    return nil
  end
  local count = reaper.CountEnvelopePoints(env)
  if not count or count == 0 or target_time == nil then
    return nil
  end
  local closest_val
  local closest_dt
  for i = 0, count - 1 do
    local ok, time, value = reaper.GetEnvelopePoint(env, i)
    if ok and time ~= nil then
      local dt = math.abs(time - target_time)
      if closest_dt == nil or dt < closest_dt then
        closest_dt = dt
        closest_val = value
      end
    end
  end
  return closest_val
end

local function detect_env_value_mode(env, chunk, tag)
  local mode = reaper.GetEnvelopeScalingMode and reaper.GetEnvelopeScalingMode(env) or nil
  if not (reaper.CountEnvelopePoints and reaper.GetEnvelopePoint) then
    return "raw", mode
  end
  local count = reaper.CountEnvelopePoints(env)
  if not count or count == 0 then
    return "raw", mode
  end
  local prefer_not_one = (tag == "VOLENV" or tag == "VOLENV2" or tag == "VOLENV3")
  local sample_time, sample_value = get_sample_pt(chunk, prefer_not_one)
  if sample_time == nil or sample_value == nil then
    return "raw", mode
  end
  local api_val = find_api_point_by_time(env, sample_time)
  if api_val == nil then
    return "raw", mode
  end

  local function near(a, b)
    if a == nil or b == nil then
      return false
    end
    local diff = math.abs(a - b)
    local scale = math.max(1, math.abs(a), math.abs(b))
    return diff <= 1e-6 or diff <= 1e-4 * scale
  end

  if near(api_val, sample_value) then
    return "raw", mode
  end
  if mode ~= nil and reaper.ScaleFromEnvelopeMode then
    local scaled = reaper.ScaleFromEnvelopeMode(mode, sample_value)
    if near(api_val, scaled) then
      return "scale_from", mode
    end
  end
  if mode ~= nil and reaper.ScaleToEnvelopeMode then
    local raw = reaper.ScaleToEnvelopeMode(mode, sample_value)
    if near(api_val, raw) then
      return "scale_to", mode
    end
  end

  return "raw", mode
end

local function env_api_value_at_time(env, t)
  if reaper.Envelope_Evaluate then
    local v1, v2 = reaper.Envelope_Evaluate(env, t, 0, 0)
    if type(v2) == "number" then return v2 end
    if type(v1) == "number" then return v1 end
  end
  return nil
end

local function api_value_to_chunk(value, value_mode, scale_mode)
  if value == nil then
    return nil
  end
  if value_mode == "scale_from" and reaper.ScaleToEnvelopeMode then
    return reaper.ScaleToEnvelopeMode(scale_mode or 0, value)
  end
  if value_mode == "scale_to" and reaper.ScaleFromEnvelopeMode then
    return reaper.ScaleFromEnvelopeMode(scale_mode or 0, value)
  end
  return value
end

local function get_track_env_map(track)
  local map = {}
  local count = reaper.CountTrackEnvelopes(track)
  for i = 0, count - 1 do
    local env = reaper.GetTrackEnvelope(track, i)
    if env and reaper.GetEnvelopeStateChunk then
      local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
      if ok then
        local tag = get_env_tag_from_chunk(chunk)
        if tag and TRACK_ENV_TAG_SET[tag] then
          local value_mode, scale_mode = detect_env_value_mode(env, chunk, tag)
          map[tag] = {
            env = env,
            template = sanitize_env_block(chunk),
            value_mode = value_mode,
            scale_mode = scale_mode,
          }
        end
      end
    end
  end
  return map
end

local function collect_env_points(env, t0, t1)
  local points = {}
  if not reaper.GetEnvelopeStateChunk then
    return points
  end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk or chunk == "" then
    return points
  end
  for line in chunk:gmatch("[^\r\n]+") do
    if line:sub(1, 2) == "PT" then
      local parts = {}
      for w in line:gmatch("%S+") do
        parts[#parts + 1] = w
      end
      if parts[1] == "PT" and #parts >= 3 then
        local time = tonumber(parts[2])
        local value = tonumber(parts[3])
        if time and value and time >= t0 and time <= t1 then
          local shape = tonumber(parts[4]) or 0
          local tension = tonumber(parts[5]) or 0
          local selected = tonumber(parts[6]) or 0
          points[#points + 1] = {
            time = time - t0,
            value = value,
            shape = shape,
            tension = tension,
            selected = (selected ~= 0),
          }
        end
      end
    end
  end
  return points
end

local function collect_env_ais(env, t0, t1)
  local ais = {}
  if reaper.CountAutomationItems and reaper.GetSetAutomationItemInfo then
    local ai_count = reaper.CountAutomationItems(env)
    for ai = 0, ai_count - 1 do
      local pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
      local len = reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
      local ai_end = pos + len
      if ai_end >= t0 and pos <= t1 then
        ais[#ais + 1] = {
          pos = pos - t0,
          length = len,
          startoffs = reaper.GetSetAutomationItemInfo(env, ai, "D_STARTOFFS", 0, false),
          playrate = reaper.GetSetAutomationItemInfo(env, ai, "D_PLAYRATE", 0, false),
          baseline = reaper.GetSetAutomationItemInfo(env, ai, "D_BASELINE", 0, false),
          amplitude = reaper.GetSetAutomationItemInfo(env, ai, "D_AMPLITUDE", 0, false),
          loop = reaper.GetSetAutomationItemInfo(env, ai, "B_LOOP", 0, false),
          pool_id = reaper.GetSetAutomationItemInfo(env, ai, "D_POOL_ID", 0, false),
        }
      end
    end
  end
  return ais
end

local function pin_items(project_path)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return nil, "Nothing selected" end

  local items = {}
  local media = {}
  local seen_media = {}
  local anchor_pos = nil
  local base_track_index = nil
  local env_map_cache = {}
  local default_name = nil

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local ok, chunk = reaper.GetItemStateChunk(item, "", false)
    if not ok then
      return nil, "Failed to read item chunk"
    end
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
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

    local env_map = env_map_cache[track]
    if not env_map then
      env_map = get_track_env_map(track)
      env_map_cache[track] = env_map
    end
    local item_env = {}
    for _, tag in ipairs(TRACK_ENV_TAGS_ORDER) do
      local entry = env_map[tag]
      if entry then
        local env = entry.env
        local pts = collect_env_points(env, pos, pos + len)
        local ais = collect_env_ais(env, pos, pos + len)
        if #pts > 0 or #ais > 0 then
          local start_api = env_api_value_at_time(env, pos)
          local end_api = env_api_value_at_time(env, pos + len)
          item_env[tag] = {
            points = pts,
            ais = ais,
            template = entry.template,
            value_mode = entry.value_mode,
            scale_mode = entry.scale_mode,
            guard_start = api_value_to_chunk(start_api, entry.value_mode, entry.scale_mode),
            guard_end = api_value_to_chunk(end_api, entry.value_mode, entry.scale_mode),
          }
        end
      end
    end
    if next(item_env) then
      items[#items].env = item_env
    end

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
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
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
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
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
