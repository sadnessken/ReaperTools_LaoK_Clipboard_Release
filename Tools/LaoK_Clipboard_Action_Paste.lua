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

local function resolve_media_root(proj, proj_path)
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

  reaper.ShowConsoleMsg(string.format("[LaoK Clipboard] PROJECT_MEDIA_PATH ok=%s val=%s\n", tostring(ok_media), tostring(media_path)))
  reaper.ShowConsoleMsg(string.format("[LaoK Clipboard] RECORD_PATH ok=%s val=%s\n", tostring(ok_record), tostring(record_path)))
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
  reaper.ShowConsoleMsg("[LaoK Clipboard] Media root: " .. media_path .. "\n")
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

local function paste_items(pin, media_map, missing, created_items)
  local base_track, base_index = get_base_track()
  local base_pin_index = pin.payload.base_track_index or 1
  local edit_pos = reaper.GetCursorPosition()
  local base_offset = edit_pos
  local skipped = 0
  local track_map = {}

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
  end

  reaper.UpdateArrange()
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

  local media_root, media_diag, err = resolve_media_root(proj, proj_path)
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
