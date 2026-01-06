-- @noindex
local M = {}

local BASE_INTERVAL = 0.6
local PLAY_INTERVAL = 2.0

function M.InitIndexer(state)
  state.indexer = {
    last_poll = 0,
    idle_nochange = 0,
    interval = BASE_INTERVAL,
  }
end

local function get_project_display_name(common, proj, proj_path)
  local ok, name = reaper.GetProjectName(proj, "")
  if ok and type(name) == "string" and name ~= "" then return name end
  if reaper.GetSetProjectInfo_String then
    local ok2, pname = reaper.GetSetProjectInfo_String(proj, "PROJECT_NAME", "", false)
    if ok2 and pname ~= "" then return pname end
  end
  if proj_path and proj_path ~= "" then
    local base = common.BaseName(proj_path)
    if base ~= "" then return base end
  end
  return "<untitled>"
end

local function build_project_index(common, proj, proj_path)
  local entries = {}
  local proj_name = get_project_display_name(common, proj, proj_path)

  local track_count = reaper.CountTracks(proj)
  for ti = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, ti)
    local ok, track_name = reaper.GetTrackName(track, "")
    if not ok or track_name == "" then
      track_name = string.format("Track %d", ti + 1)
    end
    local track_guid = reaper.GetTrackGUID(track)

    entries[#entries + 1] = {
      type = "TRACK",
      display_name = track_name,
      search_text = track_name:lower(),
      project_handle = proj,
      project_name = proj_name,
      locator = {
        track_guid = track_guid,
        track_index = ti + 1,
      },
    }

    local item_count = reaper.CountTrackMediaItems(track)
    for ii = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, ii)
      local take = reaper.GetActiveTake(item)
      local item_name = ""
      if take then
        item_name = reaper.GetTakeName(take) or ""
      end
      if item_name == "" then
        local ok_notes, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if ok_notes and notes ~= "" then
          item_name = notes
        end
      end
      if item_name == "" then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        item_name = string.format("Item %.2f", pos)
      end
      local ok_notes, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      if not ok_notes then notes = "" end

      local media_name = ""
      if take then
        local src = reaper.GetMediaItemTake_Source(take)
        if src then
          local buf = ""
          local ok_src, filename = reaper.GetMediaSourceFileName(src, buf)
          if ok_src and filename ~= "" then
            media_name = common.BaseName(filename)
          end
        end
      end

      local item_guid = common.GetItemGUID(item)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local search_text = (item_name .. " " .. (notes or "") .. " " .. (media_name or "") .. " " .. track_name):lower()

      entries[#entries + 1] = {
        type = "ITEM",
        display_name = item_name,
        search_text = search_text,
        project_handle = proj,
        project_name = proj_name,
        locator = {
          item_guid = item_guid,
          track_guid = track_guid,
          track_index = ti + 1,
          item_pos = pos,
        },
      }

      if media_name ~= "" then
        entries[#entries + 1] = {
          type = "MEDIA",
          display_name = media_name,
          search_text = search_text,
          project_handle = proj,
          project_name = proj_name,
          locator = {
            item_guid = item_guid,
            track_guid = track_guid,
            track_index = ti + 1,
            item_pos = pos,
          },
        }
      end
    end
  end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions
  local enum_markers = reaper.EnumProjectMarkers2 or reaper.EnumProjectMarkers
  local use_proj = enum_markers == reaper.EnumProjectMarkers2
  for i = 0, total - 1 do
    local retval, is_region, pos, rgnend, name, idx
    if use_proj then
      retval, is_region, pos, rgnend, name, idx = enum_markers(proj, i)
    else
      retval, is_region, pos, rgnend, name, idx = enum_markers(i)
    end
    if retval then
      if name == "" then
        name = is_region and ("Region " .. idx) or ("Marker " .. idx)
      end
      entries[#entries + 1] = {
        type = is_region and "REGION" or "MARKER",
        display_name = name,
        search_text = name:lower(),
        project_handle = proj,
        project_name = proj_name,
        locator = {
          marker_index = idx,
          is_region = is_region,
          position = pos,
        },
      }
    end
  end

  return entries, proj_name
end

local function compute_backoff_interval(idle_nochange)
  if idle_nochange >= 30 then
    return 2.0
  end
  if idle_nochange >= 10 then
    return 1.0
  end
  return BASE_INTERVAL
end

function M.UpdateIndexes(common, state, now, play_state, is_typing)
  if not state.indexer then
    M.InitIndexer(state)
  end
  local idx = state.indexer

  if is_typing then
    idx.last_poll = now
    return
  end

  local interval = compute_backoff_interval(idx.idle_nochange or 0)
  if play_state ~= 0 and interval < PLAY_INTERVAL then
    interval = PLAY_INTERVAL
  end
  idx.interval = interval

  if now - (idx.last_poll or 0) < interval then return end
  idx.last_poll = now

  local existing = {}
  local changed = false
  local i = 0
  while true do
    local proj, proj_path = reaper.EnumProjects(i, "")
    if not proj then break end
    existing[proj] = true

    local change = reaper.GetProjectStateChangeCount(proj)
    local proj_data = state.project_index[proj]
    if not proj_data or proj_data.last_change ~= change or proj_data.path ~= proj_path then
      local entries, proj_name = build_project_index(common, proj, proj_path)
      state.project_index[proj] = {
        path = proj_path,
        last_change = change,
        entries = entries,
        project_name = proj_name,
      }
      if state._log then
        state._log("INFO", string.format("Reindex %s: %d entries", proj_name, #entries))
      end
      state.search_dirty = true
      changed = true
    end
    i = i + 1
  end

  for proj, _ in pairs(state.project_index) do
    if not existing[proj] then
      state.project_index[proj] = nil
      state.search_dirty = true
      changed = true
    end
  end

  if changed then
    idx.idle_nochange = 0
  else
    idx.idle_nochange = (idx.idle_nochange or 0) + 1
  end
end

local function score_entry(entry, tokens, query, fuzzy, current_proj)
  local text = entry.search_text
  local name = entry.display_name:lower()
  local score = 0
  if fuzzy then
    for _, tok in ipairs(tokens) do
      if name:sub(1, #tok) == tok then
        score = score + 3
      elseif text:find(tok, 1, true) then
        score = score + 1
      else
        return nil
      end
    end
  else
    if text:find(query, 1, true) then
      if name:sub(1, #query) == query then
        score = score + 3
      else
        score = score + 1
      end
    else
      return nil
    end
  end
  if entry.project_handle == current_proj then
    score = score + 0.1
  end
  return score
end

function M.ParseSearchFilter(text)
  local raw = text or ""
  local raw_lower = raw:lower()
  local filter = nil
  if raw_lower:sub(1, 3) == "-i " then
    filter = "ITEM"
    raw = raw:sub(4)
  elseif raw_lower:sub(1, 3) == "-t " then
    filter = "TRACK"
    raw = raw:sub(4)
  end
  return filter, raw
end

function M.RunSearch(common, state, query)
  local query_text = common.Trim(query or "")
  if query_text == "" then
    state.search_results = {}
    return
  end
  local tokens = common.SplitTokens(query_text:lower())
  local fuzzy = state.user_data.settings and state.user_data.settings.fuzzy_enabled ~= false
  local max_results = (state.user_data.settings and state.user_data.settings.max_results) or 80
  local current_proj = select(1, reaper.EnumProjects(-1, ""))

  local results = {}
  for _, proj_data in pairs(state.project_index) do
    for _, entry in ipairs(proj_data.entries) do
      if state.search_filter and entry.type ~= state.search_filter then
        goto continue
      end
      local score = score_entry(entry, tokens, query_text:lower(), fuzzy, current_proj)
      if score then
        results[#results + 1] = { entry = entry, score = score }
      end
      ::continue::
    end
  end

  table.sort(results, function(a, b)
    if a.score == b.score then
      return a.entry.display_name < b.entry.display_name
    end
    return a.score > b.score
  end)

  local out = {}
  for i = 1, math.min(#results, max_results) do
    out[i] = results[i].entry
  end
  state.search_results = out
end

return M
