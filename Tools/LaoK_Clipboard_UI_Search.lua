-- @noindex
local M = {}

local function compute_search_dropdown_height(common, state)
  if common.Trim(state.search_text) == "" then return 0 end
  local max_h = state.user_data.settings and state.user_data.settings.search_dropdown_max_h or 260
  local row_h = 28
  local height = math.min(#state.search_results * row_h + 6, max_h)
  if height < 0 then height = 0 end
  return height
end

local function select_track(track)
  if not track then return end
  if reaper.SelectAllMediaItems then
    reaper.SelectAllMediaItems(0, false)
  end
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(40913, 0)
end

local function select_item(item)
  if not item then return end
  if reaper.SelectAllMediaItems then
    reaper.SelectAllMediaItems(0, false)
  end
  local track = reaper.GetMediaItemTrack(item)
  if track then
    reaper.SetOnlyTrackSelected(track)
  end
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(40914, 0)
end

local function jump_to_entry(common, entry)
  if not entry or not entry.project_handle then return end
  reaper.SelectProjectInstance(entry.project_handle)

  if entry.type == "TRACK" then
    local track = common.GetTrackByGUID(entry.project_handle, entry.locator.track_guid)
    if not track then
      track = reaper.GetTrack(entry.project_handle, entry.locator.track_index - 1)
    end
    select_track(track)
  elseif entry.type == "ITEM" or entry.type == "MEDIA" then
    local item = common.GetItemByGUID(entry.project_handle, entry.locator.item_guid)
    if not item and entry.locator.track_index then
      local track = reaper.GetTrack(entry.project_handle, entry.locator.track_index - 1)
      if track then
        local item_count = reaper.CountTrackMediaItems(track)
        for i = 0, item_count - 1 do
          local cand = reaper.GetTrackMediaItem(track, i)
          local pos = reaper.GetMediaItemInfo_Value(cand, "D_POSITION")
          if math.abs(pos - entry.locator.item_pos) < 0.0001 then
            item = cand
            break
          end
        end
      end
    end
    if item then
      select_item(item)
      if entry.locator.item_pos then
        reaper.SetEditCurPos(entry.locator.item_pos, false, false)
      end
    end
  elseif entry.type == "MARKER" or entry.type == "REGION" then
    if reaper.GoToMarker then
      reaper.GoToMarker(entry.project_handle, entry.locator.marker_index, entry.locator.is_region)
    else
      reaper.SetEditCurPos(entry.locator.position or 0, true, false)
    end
  end
end

local function draw_search_results(ctx, common, state, style)
  local height = compute_search_dropdown_height(common, state)
  if height <= 0 then return end

  local ok = style.BeginChild(ctx, "SearchDropdown", -1, height, true)
  if ok then
    local avail = reaper.ImGui_GetContentRegionAvail(ctx)
    local pop_colors = 0
    if reaper.ImGui_Col_Border then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), style.Colors.text_dark)
      pop_colors = pop_colors + 1
    end
    if reaper.ImGui_Col_Separator then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), style.Colors.text_dark)
      pop_colors = pop_colors + 1
    end

    if reaper.ImGui_BeginTable then
      local flags = reaper.ImGui_TableFlags_BordersInnerV() |
        reaper.ImGui_TableFlags_RowBg() |
        reaper.ImGui_TableFlags_Resizable()
      if reaper.ImGui_BeginTable(ctx, "SearchTable", 3, flags, avail) then
        local type_w = 90
        local proj_w = 140
        reaper.ImGui_TableSetupColumn(ctx, "Name", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)
        reaper.ImGui_TableSetupColumn(ctx, "Type", reaper.ImGui_TableColumnFlags_WidthFixed(), type_w)
        reaper.ImGui_TableSetupColumn(ctx, "Project", reaper.ImGui_TableColumnFlags_WidthFixed(), proj_w)
        for i, entry in ipairs(state.search_results) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local label = entry.display_name .. "##sr" .. tostring(i)
          if reaper.ImGui_Selectable(ctx, label, false, reaper.ImGui_SelectableFlags_SpanAllColumns()) then
            jump_to_entry(common, entry)
          end
          if reaper.ImGui_SetTooltip and reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, entry.display_name)
          end
          reaper.ImGui_TableSetColumnIndex(ctx, 1)
          reaper.ImGui_Text(ctx, entry.type)
          reaper.ImGui_TableSetColumnIndex(ctx, 2)
          reaper.ImGui_Text(ctx, entry.project_name)
        end
        reaper.ImGui_EndTable(ctx)
      end
    else
      reaper.ImGui_Columns(ctx, 3, "SearchCols", false)
      local type_w = 90
      local proj_w = 140
      local name_w = math.max(avail - type_w - proj_w, 120)
      reaper.ImGui_SetColumnWidth(ctx, 0, name_w)
      reaper.ImGui_SetColumnWidth(ctx, 1, type_w)
      reaper.ImGui_SetColumnWidth(ctx, 2, proj_w)
      for i, entry in ipairs(state.search_results) do
        local label = entry.display_name .. "##sr" .. tostring(i)
        if reaper.ImGui_Selectable(ctx, label, false, reaper.ImGui_SelectableFlags_SpanAllColumns()) then
          jump_to_entry(common, entry)
        end
        if reaper.ImGui_SetTooltip and reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, entry.display_name)
        end
        reaper.ImGui_NextColumn(ctx)
        reaper.ImGui_Text(ctx, entry.type)
        reaper.ImGui_NextColumn(ctx)
        reaper.ImGui_Text(ctx, entry.project_name)
        reaper.ImGui_NextColumn(ctx)
      end
      reaper.ImGui_Columns(ctx, 1)
    end

    if pop_colors > 0 then
      reaper.ImGui_PopStyleColor(ctx, pop_colors)
    end
    reaper.ImGui_EndChild(ctx)
  end
end

function M.GetDropdownHeight(common, state)
  return compute_search_dropdown_height(common, state)
end

function M.DrawSearchArea(ctx, common, state, style, indexer)
  reaper.ImGui_PushItemWidth(ctx, -1)
  local changed
  if reaper.ImGui_InputTextWithHint then
    changed, state.search_text = reaper.ImGui_InputTextWithHint(ctx, "##search", "Search tracks, items, media, regions, markers...", state.search_text)
  else
    changed, state.search_text = reaper.ImGui_InputText(ctx, "##search", state.search_text)
  end
  reaper.ImGui_PopItemWidth(ctx)

  local filter, raw = indexer.ParseSearchFilter(state.search_text)
  state.search_filter = filter
  state.search_query = raw or ""

  if filter then
    local label = filter
    if filter == "ITEM" then
      label = "Item"
    elseif filter == "TRACK" then
      label = "Track"
    elseif filter == "REGION" then
      label = "Region"
    elseif filter == "MARKER" then
      label = "Marker"
    end
    local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, label)
    local badge_h = math.max(12, math.min(text_h + 6, (max_y - min_y) - 6))
    local badge_w = text_w + 10
    local badge_x = max_x - badge_w - 6
    local badge_y = min_y + ((max_y - min_y) - badge_h) * 0.5
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, badge_x, badge_y, badge_x + badge_w, badge_y + badge_h, style.Colors.teal, 4)
    reaper.ImGui_DrawList_AddText(draw_list, badge_x + (badge_w - text_w) * 0.5, badge_y + (badge_h - text_h) * 0.5, style.Colors.text_dark, label)
  end

  if changed then
    state.search_dirty = true
    state.last_search_change = reaper.time_precise()
  end

  draw_search_results(ctx, common, state, style)
end

return M
