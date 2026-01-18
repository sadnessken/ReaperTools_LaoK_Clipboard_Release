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

local function console_enabled(settings)
  return not (settings and settings.disable_paste_console_logs)
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
  return data
end

local function find_pin(data, pin_id)
  for _, pin in ipairs(data.pins) do
    if pin.pin_id == pin_id then return pin end
  end
  return nil
end

local function get_project_path()
  local proj, proj_path = reaper.EnumProjects(-1, "")
  if proj_path == "" then
    return nil
  end
  return proj, proj_path
end

local function parse_media_path_from_chunk(proj)
  if not reaper.GetProjectStateChunk then return nil, nil end
  local ok, chunk = reaper.GetProjectStateChunk(proj, "", false)
  if not ok or not chunk or chunk == "" then return nil, nil end
  local projmedia = chunk:match("\nPROJMEDIA%s+\"(.-)\"") or chunk:match("^PROJMEDIA%s+\"(.-)\"")
  local record = chunk:match("\nRECORD_PATH%s+\"(.-)\"") or chunk:match("^RECORD_PATH%s+\"(.-)\"")
  return projmedia, record
end

local function resolve_media_root(proj, proj_path, settings)
  local diag = {}
  local ok_media, media_path = reaper.GetSetProjectInfo_String(proj, "PROJECT_MEDIA_PATH", "", false)
  local ok_record, record_path = reaper.GetSetProjectInfo_String(proj, "RECORD_PATH", "", false)
  local chunk_media, chunk_record = parse_media_path_from_chunk(proj)
  diag.project_media_path_ok = ok_media
  diag.project_media_path = media_path or ""
  diag.record_path_ok = ok_record
  diag.record_path = record_path or ""
  diag.chunk_media_path = chunk_media or ""
  diag.chunk_record_path = chunk_record or ""

  if console_enabled(settings) then
    reaper.ShowConsoleMsg(string.format("[LaoK Clipboard] PROJECT_MEDIA_PATH ok=%s val=%s\n", tostring(ok_media), tostring(media_path)))
  end
  if console_enabled(settings) then
    reaper.ShowConsoleMsg(string.format("[LaoK Clipboard] RECORD_PATH ok=%s val=%s\n", tostring(ok_record), tostring(record_path)))
  end
  log("INFO", "PROJECT_MEDIA_PATH ok=" .. tostring(ok_media) .. " val=" .. tostring(media_path))
  log("INFO", "RECORD_PATH ok=" .. tostring(ok_record) .. " val=" .. tostring(record_path))

  local source = ""
  if ok_media and media_path ~= "" then
    source = "PROJECT_MEDIA_PATH"
  elseif ok_record and record_path ~= "" then
    media_path = record_path
    source = "RECORD_PATH"
  elseif chunk_media and chunk_media ~= "" then
    media_path = chunk_media
    source = "CHUNK_PROJMEDIA"
  elseif chunk_record and chunk_record ~= "" then
    media_path = chunk_record
    source = "CHUNK_RECORD_PATH"
  end
  if media_path == "" then
    local proj_dir = common.GetProjectDir(proj_path)
    media_path = common.JoinPath(proj_dir, "Media")
    source = "DEFAULT_MEDIA"
  else
    if media_path:sub(1, 1) ~= "/" and not media_path:match("^%a:[/\\]") then
      local proj_dir = common.GetProjectDir(proj_path)
      media_path = common.JoinPath(proj_dir, media_path)
    end
  end

  log("INFO", "Resolved media root candidate: " .. tostring(media_path))
  log("INFO", "Media root source: " .. tostring(source))
  diag.media_root_candidate = media_path
  diag.media_root_source = source
  local ok_dir, raw_dir = common.EnsureDir(media_path)
  if not ok_dir then
    log("WARN", "RecursiveCreateDirectory failed for: " .. tostring(media_path) .. " (code=" .. tostring(raw_dir) .. ")")
    return nil, diag, "Failed to create media directory"
  end
  if console_enabled(settings) then
    reaper.ShowConsoleMsg("[LaoK Clipboard] Media root: " .. media_path .. "\n")
  end
  log("INFO", "Media root: " .. media_path)
  return media_path, diag
end

local function build_media_map(pin, media_root, settings)
  local map = {}
  local missing = {}
  local copied = 0
  local reused = 0
  local hash_enabled = settings and settings.hash_dedupe_enabled ~= false
  local hash_mode = settings and settings.hash_failure_mode or "FALLBACK"

  local media = pin.media or {}
  for _, entry in ipairs(media) do
    local src = entry.src_path
    if src and src ~= "" and common.FileExists(src) then
      local suffix
      if hash_enabled then
        local hash, err = common.ComputeHash(src)
        if not hash then
          if hash_mode == "HARD_FAIL" then
            missing[src] = true
            log("WARN", "Hash failed (hard): " .. tostring(err) .. " src=" .. tostring(src))
            goto continue
          end
          suffix = common.FallbackHashFromStat(src)
          log("WARN", "Hash failed, using fallback: " .. tostring(err) .. " src=" .. tostring(src))
        else
          suffix = hash:sub(1, 8)
        end
      else
        suffix = common.FallbackHashFromStat(src)
      end

      local base = common.BaseName(src)
      local name, ext = common.SplitExt(base)
      local dest_name
      if ext ~= "" then
        dest_name = string.format("%s__%s.%s", name, suffix, ext)
      else
        dest_name = string.format("%s__%s", name, suffix)
      end
      local dest = common.JoinPath(media_root, dest_name)
      if not common.FileExists(dest) then
        local ok, copy_err = common.CopyFile(src, dest)
        if not ok then
          missing[src] = true
          log("WARN", "Copy failed: " .. tostring(copy_err) .. " src=" .. tostring(src))
        else
          copied = copied + 1
          map[src] = dest
        end
      else
        reused = reused + 1
        map[src] = dest
      end
    else
      if src and src ~= "" then
        missing[src] = true
      end
    end
    ::continue::
  end

  return map, missing, copied, reused
end

local function capture_selected_items()
  local items = {}
  local count = reaper.CountSelectedMediaItems(0)
  for i = 0, count - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  return items
end

local function restore_selected_items(items)
  if reaper.SelectAllMediaItems then
    reaper.SelectAllMediaItems(0, false)
  end
  for _, item in ipairs(items) do
    reaper.SetMediaItemSelected(item, true)
  end
end

local function build_peaks_for_items(items)
  if #items == 0 then return end
  local prev = capture_selected_items()
  if reaper.SelectAllMediaItems then
    reaper.SelectAllMediaItems(0, false)
  end
  for _, item in ipairs(items) do
    reaper.SetMediaItemSelected(item, true)
  end
  reaper.Main_OnCommand(40047, 0)
  restore_selected_items(prev)
end

local function collect_missing_from_items(items, project_path)
  local missing = {}
  for _, item in ipairs(items or {}) do
    local take_count = reaper.CountTakes(item)
    for t = 0, take_count - 1 do
      local take = reaper.GetTake(item, t)
      if take then
        local src = reaper.GetMediaItemTake_Source(take)
        local path = common.GetMediaSourceFileNameSafe(src)
        if path ~= "" then
          local abs = common.ResolveMaybeRelativePath(path, project_path)
          if abs ~= "" and not common.FileExists(abs) then
            missing[abs] = true
          end
        end
      end
    end
  end
  return missing
end

local function ensure_track_at_index(index)
  local track_count = reaper.CountTracks(0)
  while track_count < index do
    reaper.InsertTrackAtIndex(track_count, true)
    track_count = reaper.CountTracks(0)
  end
  return reaper.GetTrack(0, index - 1)
end

local function get_base_track()
  local count = reaper.CountSelectedTracks(0)
  if count > 0 then
    local track = reaper.GetSelectedTrack(0, 0)
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    return track, idx
  end
  local track_count = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(track_count, true)
  local track = reaper.GetTrack(0, track_count)
  return track, track_count + 1
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

local env_template_cache = {}

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

local function find_env_template_in_project(tag)
  local track_count = reaper.CountTracks(0)
  for ti = 0, track_count - 1 do
    local track = reaper.GetTrack(0, ti)
    local env_count = reaper.CountTrackEnvelopes(track)
    for ei = 0, env_count - 1 do
      local env = reaper.GetTrackEnvelope(track, ei)
      if env and reaper.GetEnvelopeStateChunk then
        local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
        if ok and get_env_tag_from_chunk(chunk) == tag then
          return sanitize_env_block(chunk)
        end
      end
    end
  end
  return nil
end

local function get_env_template(tag)
  if env_template_cache[tag] ~= nil then
    return env_template_cache[tag]
  end
  local template = find_env_template_in_project(tag)
  env_template_cache[tag] = template or false
  return template
end

local function build_env_block(tag)
  local template = get_env_template(tag)
  if template then
    return template
  end
  return table.concat({
    "<" .. tag,
    "EGUID " .. reaper.genGuid(),
    "ACT 1",
    "VIS 1 1 1",
    "ARM 1",
    "LANEHEIGHT 0 0",
    "DEFSHAPE 0 -1 -1",
    ">",
  }, "\n")
end

local function env_block_pattern(tag)
  return "(<" .. tag .. "%s[%s%S]-\n>)"
end

local function env_block_exists(chunk, tag)
  if not chunk or not tag then
    return false
  end
  return chunk:find("<" .. tag .. "%s") ~= nil
end

local TRACK_ENV_ACTIONS = {
  VOLENV = { 40408, 41865 },
  PANENV = { 40409, 41867 },
  WIDTHENV = { 41869 },
  VOLENV2 = { 40406, 41866 },
  PANENV2 = { 40407, 41868 },
  WIDTHENV2 = { 41870 },
  MUTEENV = { 40867, 41871 },
  VOLENV3 = { 42021 },
}






local function save_selected_tracks()
  local tracks = {}
  local count = reaper.CountSelectedTracks(0)
  for i = 0, count - 1 do
    tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i)
  end
  return tracks
end

local function restore_selected_tracks(tracks)
  local total = reaper.CountTracks(0)
  for i = 0, total - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
  for _, tr in ipairs(tracks) do
    reaper.SetTrackSelected(tr, true)
  end
end

local function find_track_envelope_by_tag(track, tag)
  local count = reaper.CountTrackEnvelopes(track)
  for i = 0, count - 1 do
    local env = reaper.GetTrackEnvelope(track, i)
    if env and reaper.GetEnvelopeStateChunk then
      local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
      if ok and get_env_tag_from_chunk(chunk) == tag then
        return env
      end
    end
  end
  return nil
end

local function build_env_map(track)
  local map = {}
  local count = reaper.CountTrackEnvelopes(track)
  for i = 0, count - 1 do
    local env = reaper.GetTrackEnvelope(track, i)
    if env and reaper.GetEnvelopeStateChunk then
      local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
      local tag = ok and get_env_tag_from_chunk(chunk) or nil
      if tag and TRACK_ENV_TAG_SET[tag] then
        map[tag] = env
      end
    end
  end
  return map
end

local env_tag_action_map = nil

local function get_actions_for_tag(tag)
  if env_tag_action_map == nil and reaper.InsertTrackAtIndex and reaper.DeleteTrack then
    local selected_tracks = save_selected_tracks()
    local selected_env = reaper.GetSelectedEnvelope and reaper.GetSelectedEnvelope(0) or nil
    local total = reaper.CountTracks(0)
    local action_ids = { 40406, 40407, 40408, 40409, 40867, 41865, 41866, 41867, 41868, 41869, 41870, 41871, 42021 }
    env_tag_action_map = {}
    for _, cmd in ipairs(action_ids) do
      reaper.InsertTrackAtIndex(total, true)
      local temp = reaper.GetTrack(0, total)
      if reaper.SetOnlyTrackSelected then
        reaper.SetOnlyTrackSelected(temp)
      else
        restore_selected_tracks({ temp })
      end
      reaper.Main_OnCommand(cmd, 0)
      local envs = build_env_map(temp)
      for t in pairs(envs) do
        env_tag_action_map[t] = env_tag_action_map[t] or {}
        env_tag_action_map[t][#env_tag_action_map[t] + 1] = cmd
      end
      reaper.DeleteTrack(temp)
    end
    restore_selected_tracks(selected_tracks)
    if selected_env and reaper.SetCursorContext then
      reaper.SetCursorContext(2, selected_env)
    end
  end

  if env_tag_action_map and env_tag_action_map[tag] then
    return env_tag_action_map[tag]
  end
  return TRACK_ENV_ACTIONS[tag] or {}
end



local function activate_env_block(block)
  local lines = {}
  for line in block:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then
    return block
  end
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
  local insert_at = #lines + 1
  if lines[#lines] == ">" then
    insert_at = #lines
  end
  if not has_act then
    table.insert(lines, insert_at, "ACT 1")
    insert_at = insert_at + 1
  end
  if not has_vis then
    table.insert(lines, insert_at, "VIS 1 1 1")
    insert_at = insert_at + 1
  end
  if not has_arm then
    table.insert(lines, insert_at, "ARM 1")
  end
  return table.concat(lines, "\n")
end

local function ensure_track_envelope_exists(track, tag, template)
  if not (tag and TRACK_ENV_TAG_SET[tag]) then
    return false
  end
  if not (reaper.GetTrackStateChunk and reaper.SetTrackStateChunk) then
    return false
  end
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok or not chunk or chunk == "" then
    return false
  end
  if env_block_exists(chunk, tag) then
    local updated = chunk:gsub(env_block_pattern(tag), function(env_block)
      return activate_env_block(env_block)
    end, 1)
    if updated ~= chunk then
      reaper.SetTrackStateChunk(track, updated, false)
      if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
      end
      if reaper.UpdateArrange then
        reaper.UpdateArrange()
      end
      return true
    end
    return false
  end
  local block = template and sanitize_env_block(template) or build_env_block(tag)
  if not block or block == "" then
    return false
  end
  local updated = chunk:gsub("\n>[%s]*$", "\n" .. block .. "\n>\n", 1)
  if updated == chunk then
    updated = chunk .. "\n" .. block .. "\n"
  end
  reaper.SetTrackStateChunk(track, updated, false)
  if reaper.TrackList_AdjustWindows then
    reaper.TrackList_AdjustWindows(false)
  end
  if reaper.UpdateArrange then
    reaper.UpdateArrange()
  end
  return true
end


local function ensure_envelope_active(env)
  if not (reaper.GetEnvelopeStateChunk and reaper.SetEnvelopeStateChunk) then
    return
  end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk or chunk == "" then
    return
  end
  local updated = chunk:gsub("ACT%s+%d+", "ACT 1")
  updated = updated:gsub("VIS%s+[%d%.%-]+%s+[%d%.%-]+%s+[%d%.%-]+", "VIS 1 1 1")
  updated = updated:gsub("ARM%s+%d+", "ARM 1")
  if updated ~= chunk then
    reaper.SetEnvelopeStateChunk(env, updated, false)
  end
end

local function ensure_track_envelope(track, tag, template)
  if not (tag and TRACK_ENV_TAG_SET[tag]) then
    return nil
  end
  local env = find_track_envelope_by_tag(track, tag)
  if env then
    ensure_envelope_active(env)
    return env
  end

  local env_after = nil
  if template then
    ensure_track_envelope_exists(track, tag, template)
    env_after = find_track_envelope_by_tag(track, tag)
    if env_after then
      ensure_envelope_active(env_after)
      return env_after
    end
  end

  local selected_tracks = save_selected_tracks()
  local selected_env = reaper.GetSelectedEnvelope and reaper.GetSelectedEnvelope(0) or nil

  if reaper.SetOnlyTrackSelected then
    reaper.SetOnlyTrackSelected(track)
  else
    restore_selected_tracks({ track })
  end

  local cmds = get_actions_for_tag(tag)
  if reaper.Main_OnCommand then
    for _, cmd in ipairs(cmds) do
      reaper.Main_OnCommand(cmd, 0)
      local env_try = find_track_envelope_by_tag(track, tag)
      if env_try then
        env_after = env_try
        break
      end
    end
  end

  if not env_after and reaper.GetSelectedEnvelope then
    local sel_env = reaper.GetSelectedEnvelope(0)
    if sel_env and reaper.GetEnvelopeStateChunk then
      local ok, chunk = reaper.GetEnvelopeStateChunk(sel_env, "", false)
      if ok and get_env_tag_from_chunk(chunk) == tag then
        env_after = sel_env
      end
    end
  end

  restore_selected_tracks(selected_tracks)
  if selected_env and reaper.SetCursorContext then
    reaper.SetCursorContext(2, selected_env)
  end

  if not env_after then
    ensure_track_envelope_exists(track, tag, nil)
    env_after = find_track_envelope_by_tag(track, tag)
  end
  if env_after then
    ensure_envelope_active(env_after)
  end
  return env_after
end


local function normalize_env_value(tag, value)
  if tag == "VOLENV" or tag == "VOLENV2" or tag == "VOLENV3" then
    if math.abs(value) > 10 then
      local norm = value / 1000
      if reaper.ScaleFromEnvelopeMode then
        return reaper.ScaleFromEnvelopeMode(1, norm)
      end
      return norm
    end
  end
  return value
end

local function to_api_env_value(env, tag, value, env_data)
  if env_data and env_data.value_mode and env_data.value_mode ~= "" then
    local mode = reaper.GetEnvelopeScalingMode and reaper.GetEnvelopeScalingMode(env) or env_data.scale_mode
    if env_data.value_mode == "scale_from" and reaper.ScaleFromEnvelopeMode then
      local scaled = reaper.ScaleFromEnvelopeMode(mode or 0, value)
      if scaled ~= nil then
        return scaled
      end
    elseif env_data.value_mode == "scale_to" and reaper.ScaleToEnvelopeMode then
      local raw = reaper.ScaleToEnvelopeMode(mode or 0, value)
      if raw ~= nil then
        return raw
      end
    end
    return value
  end
  return normalize_env_value(tag, value)
end

local function build_env_block_with_points(tag, template, points)
  local base = template and sanitize_env_block(template) or build_env_block(tag)
  if not base or base == "" then
    return nil
  end
  local lines = {}
  for line in base:gmatch("[^\r\n]+") do
    if line ~= ">" then
      lines[#lines + 1] = line
    end
  end
  table.sort(points, function(a, b) return a.time < b.time end)
  for _, pt in ipairs(points) do
    local selected = pt.selected and 1 or 0
    local value = normalize_env_value(tag, pt.value or 0)
    lines[#lines + 1] = string.format("PT %.12f %.12f %d %g %d", pt.time, value, pt.shape or 0, pt.tension or 0, selected)
  end
  lines[#lines + 1] = ">"
  return table.concat(lines, "\n")
end

local function apply_env_points_to_track_chunk(track, tag, points, template)
  if not (reaper.GetTrackStateChunk and reaper.SetTrackStateChunk) then
    return false
  end
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok or not chunk or chunk == "" then
    return false
  end
  local block = build_env_block_with_points(tag, template, points)
  if not block or block == "" then
    return false
  end
  local updated = chunk
  if env_block_exists(chunk, tag) then
    updated = chunk:gsub(env_block_pattern(tag), block, 1)
  else
    updated = chunk:gsub("\n>[%s]*$", "\n" .. block .. "\n>\n", 1)
    if updated == chunk then
      updated = chunk .. "\n" .. block .. "\n"
    end
  end
  if updated ~= chunk then
    reaper.SetTrackStateChunk(track, updated, false)
    if reaper.TrackList_AdjustWindows then
      reaper.TrackList_AdjustWindows(false)
    end
    if reaper.UpdateArrange then
      reaper.UpdateArrange()
    end
  end
  return true
end

local function paste_items(pin, media_map, missing, created_items)
  local base_track, base_index = get_base_track()
  local base_pin_index = pin.payload.base_track_index or 1
  local edit_pos = reaper.GetCursorPosition()
  local base_offset = edit_pos
  local skipped = 0
  local track_map = {}
  local env_write_queue = {}
  local track_required_tags = {}
  local track_required_templates = {}
  local chunk_env_points = {}

  for _, item in ipairs(pin.payload.items or {}) do
    local dest_track_index = base_index + (item.track_index - base_pin_index)
    local track = track_map[item.track_index]
    if not track then
      track = ensure_track_at_index(dest_track_index)
      track_map[item.track_index] = track
    end

    local replaced, item_missing = common.ReplaceChunkFilePaths(item.chunk, media_map, nil)
    for path_key in pairs(item_missing) do
      missing[path_key] = true
    end
    local new_item = reaper.AddMediaItemToTrack(track)
    reaper.SetItemStateChunk(new_item, replaced, false)
    local pos = base_offset + (item.offset or 0)
    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", pos)
    created_items[#created_items + 1] = new_item

    if item.env then
      track_required_tags[track] = track_required_tags[track] or {}
      for _, tag in ipairs(TRACK_ENV_TAGS_ORDER) do
        local env_data = item.env[tag]
        if env_data then
          track_required_tags[track][tag] = true
          track_required_templates[track] = track_required_templates[track] or {}
          if env_data.template and env_data.template ~= "" and not track_required_templates[track][tag] then
            track_required_templates[track][tag] = env_data.template
          end
        end
      end
      env_write_queue[#env_write_queue + 1] = { track = track, pos = pos, env = item.env }
    end
  end

  local track_env_maps = {}
  local env_sort_needed = {}
  for track, tags in pairs(track_required_tags) do
    local templates = track_required_templates[track]
    for _, tag in ipairs(TRACK_ENV_TAGS_ORDER) do
      if tags[tag] then
        local template = templates and templates[tag] or nil
        ensure_track_envelope(track, tag, template)
      end
    end
    track_env_maps[track] = build_env_map(track)
  end

  for _, entry in ipairs(env_write_queue) do
    local env_map = track_env_maps[entry.track]
    if env_map then
      for _, tag in ipairs(TRACK_ENV_TAGS_ORDER) do
        local env_data = entry.env[tag]
        if env_data then
          local env = env_map[tag]
          if env then
            ensure_envelope_active(env)
            for _, pt in ipairs(env_data.points or {}) do
              local value = to_api_env_value(env, tag, pt.value or 0, env_data)
              reaper.InsertEnvelopePoint(env, entry.pos + (pt.time or 0), value, pt.shape or 0, pt.tension or 0, pt.selected or false, true)
            end
            for _, ai in ipairs(env_data.ais or {}) do
              local pool_id = (ai.pool_id ~= nil and ai.pool_id >= 0) and ai.pool_id or -1
              local ai_pos = entry.pos + (ai.pos or 0)
              local ai_len = ai.length or 0
              local ai_idx = reaper.InsertAutomationItem(env, pool_id, ai_pos, ai_len)
              if ai_idx < 0 and pool_id ~= -1 then
                ai_idx = reaper.InsertAutomationItem(env, -1, ai_pos, ai_len)
              end
              if ai_idx >= 0 then
                reaper.GetSetAutomationItemInfo(env, ai_idx, "D_STARTOFFS", ai.startoffs or 0, true)
                reaper.GetSetAutomationItemInfo(env, ai_idx, "D_PLAYRATE", ai.playrate or 1, true)
                reaper.GetSetAutomationItemInfo(env, ai_idx, "D_BASELINE", ai.baseline or 0, true)
                reaper.GetSetAutomationItemInfo(env, ai_idx, "D_AMPLITUDE", ai.amplitude or 0, true)
                reaper.GetSetAutomationItemInfo(env, ai_idx, "B_LOOP", ai.loop or 0, true)
              end
            end
            env_sort_needed[env] = true
          else
            local track_points = chunk_env_points[entry.track]
            if not track_points then
              track_points = {}
              chunk_env_points[entry.track] = track_points
            end
            local list = track_points[tag]
            if not list then
              list = {}
              track_points[tag] = list
            end
            for _, pt in ipairs(env_data.points or {}) do
              list[#list + 1] = {
                time = entry.pos + (pt.time or 0),
                value = pt.value or 0,
                shape = pt.shape or 0,
                tension = pt.tension or 0,
                selected = pt.selected or false,
              }
            end
          end
        end
      end
    end
  end

  for env in pairs(env_sort_needed) do
    reaper.Envelope_SortPoints(env)
  end

  reaper.UpdateArrange()
  for track, tag_map in pairs(chunk_env_points) do
    for _, tag in ipairs(TRACK_ENV_TAGS_ORDER) do
      local points = tag_map[tag]
      if points and #points > 0 then
        local template = track_required_templates[track] and track_required_templates[track][tag] or nil
        apply_env_points_to_track_chunk(track, tag, points, template)
      end
    end
  end

  return skipped
end

local function clear_track_routing(track)
  for _, cat in ipairs({ 0, 1, 2 }) do
    local count = reaper.GetTrackNumSends(track, cat)
    for i = count - 1, 0, -1 do
      reaper.RemoveTrackSend(track, cat, i)
    end
  end
end

local function apply_track_sends(pin, new_tracks)
  local sends = pin.payload.sends or {}
  for _, send in ipairs(sends) do
    local src = new_tracks[send.src_slot]
    local dst = new_tracks[send.dst_slot]
    if src and dst then
      local idx = reaper.CreateTrackSend(src, dst)
      if idx >= 0 and send.params then
        for key, value in pairs(send.params) do
          reaper.SetTrackSendInfo_Value(src, 0, idx, key, value)
        end
      end
    end
  end
end

local function paste_tracks(pin, media_map, missing, created_items)
  local use_absolute = pin.payload and pin.payload.absolute_items
  local cursor_saved = reaper.GetCursorPosition()
  local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if use_absolute then
    reaper.SetEditCurPos(0, false, false)
  end

  local count = reaper.CountSelectedTracks(0)
  local insert_index
  if count > 0 then
    local track = reaper.GetSelectedTrack(0, 0)
    insert_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
  else
    insert_index = reaper.CountTracks(0)
  end

  local new_tracks = {}
  for i, tr in ipairs(pin.payload.tracks or {}) do
    reaper.InsertTrackAtIndex(insert_index + (i - 1), true)
    local track = reaper.GetTrack(0, insert_index + (i - 1))
    local replaced, track_missing = common.ReplaceChunkFilePaths(tr.chunk, media_map, nil)
    for path_key in pairs(track_missing) do
      missing[path_key] = true
    end
    reaper.SetTrackStateChunk(track, replaced, false)
    clear_track_routing(track)
    local slot = tr.track_slot or i
    new_tracks[slot] = track
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  local edit_pos = use_absolute and 0 or cursor_saved
  local skipped = 0
  for _, it in ipairs(pin.payload.items or {}) do
    local track = new_tracks[it.track_slot]
    if track then
      local replaced, item_missing = common.ReplaceChunkFilePaths(it.chunk, media_map, nil)
      for path_key in pairs(item_missing) do
        missing[path_key] = true
      end
      local new_item = reaper.AddMediaItemToTrack(track)
      reaper.SetItemStateChunk(new_item, replaced, false)
      local pos
      if use_absolute then
        if it.abs_pos ~= nil then
          pos = it.abs_pos
        elseif pin.payload and pin.payload.anchor_pos then
          pos = pin.payload.anchor_pos + (it.offset or 0)
        else
          pos = edit_pos + (it.offset or 0)
        end
      else
        pos = edit_pos + (it.offset or 0)
      end
      reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", pos)
      created_items[#created_items + 1] = new_item
    else
      skipped = skipped + 1
    end
  end
  apply_track_sends(pin, new_tracks)
  reaper.UpdateArrange()

  reaper.GetSet_LoopTimeRange2(0, true, false, ts_start, ts_end, false)
  if use_absolute then
    reaper.SetEditCurPos(cursor_saved, false, false)
  end
  return skipped
end

local function run()
  local path = ensure_user_data_path()
  if not path then return end

  local pin_id = common.GetExtState("selected_pin_id")
  if pin_id == "" then
    reaper.ShowMessageBox("No pin selected.", "LaoK Clipboard", 0)
    return
  end

  local proj, proj_path = get_project_path()
  if not proj then
    reaper.ShowMessageBox("Target project must be saved first.", "LaoK Clipboard", 0)
    return
  end

  local data = load_user_data(path)
  if not data then return end
  local pin = find_pin(data, pin_id)
  if not pin then
    reaper.ShowMessageBox("Pin not found.", "LaoK Clipboard", 0)
    return
  end

  local media_root, media_diag, err = resolve_media_root(proj, proj_path, data.settings or {})
  if not media_root then
    local report = {
      action = "paste",
      error = tostring(err),
      media_root_diag = media_diag,
      media_root_candidate = media_diag and media_diag.media_root_candidate or nil,
      timestamp = common.IsoNowUtc(),
    }
    common.SetExtState("last_report_json", common.JsonEncode(report))
    reaper.ShowMessageBox("Media root error: " .. tostring(err), "LaoK Clipboard", 0)
    return
  end

  local map, missing, copied, reused = build_media_map(pin, media_root, data.settings or {})

  reaper.Undo_BeginBlock()
  local skipped = 0
  local created_items = {}
  if pin.pin_type == "TRACKS" then
    skipped = paste_tracks(pin, map, missing, created_items)
  else
    skipped = paste_items(pin, map, missing, created_items)
  end
  reaper.Undo_EndBlock("LaoK Clipboard Paste", -1)

  if data.settings and data.settings.peaks_refresh_after_paste then
    build_peaks_for_items(created_items)
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  local missing_created = collect_missing_from_items(created_items, proj_path)
  local missing_list = {}
  for path_key in pairs(missing_created) do
    if path_key ~= "" then
      missing_list[#missing_list + 1] = path_key
    end
  end

  local report = {
    action = "paste",
    pin_id = pin_id,
    missing_files = missing_list,
    missing_count = #missing_list,
    skipped_items = skipped,
    copied = copied,
    reused = reused,
    media_root = media_root,
    media_root_diag = media_diag,
    timestamp = common.IsoNowUtc(),
  }
  common.SetExtState("last_report_json", common.JsonEncode(report))

  log("INFO", string.format("Paste done: copied=%d reused=%d missing=%d skipped=%d", copied, reused, #missing_list, skipped))
  reaper.ShowMessageBox(string.format("Paste complete. Missing: %d, Skipped: %d", #missing_list, skipped), "LaoK Clipboard", 0)
end

run()
