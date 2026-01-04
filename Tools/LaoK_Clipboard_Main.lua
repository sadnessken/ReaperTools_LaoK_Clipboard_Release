-- @description LaoK Clipboard
-- @author sadnessken
-- @version 0.1.0
-- @changelog
--   Initial public release
-- @provides
--   Tools/LaoK_Clipboard_Shared.lua
--   Tools/LaoK_Clipboard_Action_Paste.lua
--   Tools/LaoK_Clipboard_Action_Pin.lua
--   Tools/LaoK_Clipboard_Toolbar_Toggle.lua
local info = debug.getinfo(1, "S")
local script_path = info and info.source and info.source:sub(2) or ""
local script_dir = script_path:match("^(.*)[/\\]") or "."

local common = dofile(script_dir .. "/LaoK_Clipboard_Shared.lua")

local SECTION = "LaoK_Clipboard"
reaper.gmem_attach(SECTION)
if reaper.set_action_options then
  reaper.set_action_options(1)
end

local HEARTBEAT_TIMEOUT = 3.0

local function is_main_running()
  if reaper.gmem_read(0) ~= 1 then return false end
  local now = reaper.time_precise()
  local hb = reaper.gmem_read(1) or 0
  if hb <= 0 or (now - hb) > HEARTBEAT_TIMEOUT then
    reaper.gmem_write(0, 0)
    reaper.gmem_write(1, 0)
    return false
  end
  return true
end

local function set_main_running(v)
  reaper.gmem_write(0, v and 1 or 0)
  if v then
    reaper.gmem_write(1, reaper.time_precise())
  else
    reaper.gmem_write(1, 0)
  end
end

local function request_toggle_visibility()
  reaper.SetExtState(SECTION, "toggle_request", tostring(reaper.time_precise()), false)
end

local _, _, _, cmdID = reaper.get_action_context()

if is_main_running() then
  request_toggle_visibility()
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 1)
    reaper.RefreshToolbar2(0, cmdID)
  end
  return
end
set_main_running(true)

if not reaper.ImGui_CreateContext then
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 0)
    reaper.RefreshToolbar2(0, cmdID)
  end
  set_main_running(false)
  reaper.ShowMessageBox("ReaImGui is required.", "LaoK Clipboard", 0)
  return
end

local ctx = reaper.ImGui_CreateContext("LaoK Clipboard")
if not ctx then
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 0)
    reaper.RefreshToolbar2(0, cmdID)
  end
  set_main_running(false)
  reaper.ShowMessageBox("Failed to create ImGui context.", "LaoK Clipboard", 0)
  return
end

local state

local function hex_color(hex, alpha)
  local r = ((hex >> 16) & 0xFF) / 255
  local g = ((hex >> 8) & 0xFF) / 255
  local b = (hex & 0xFF) / 255
  local a = alpha or 1.0
  return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)
end

local COLORS = {
  bg = hex_color(0x19243B),
  plate = hex_color(0x212F4D),
  card = hex_color(0x293C57),
  input = hex_color(0x0F1926),
  input_hover = hex_color(0x142131),
  input_active = hex_color(0x121E2D),
  teal = hex_color(0x1AA391),
  teal_hover = hex_color(0x1FB8A3),
  teal_active = hex_color(0x148A7A),
  tag_idle = hex_color(0x22344F),
  tag_hover = hex_color(0x2A4061),
  tag_active = hex_color(0x263B59),
  pin_idle = hex_color(0x2A3E5A),
  pin_hover = hex_color(0x33506F),
  pin_active = hex_color(0x2D4666),
  text = hex_color(0xD1E6F2),
  text_dark = hex_color(0x000000),
  border_big = hex_color(0x29405C),
  border_card = hex_color(0x334E77),
  title_bg = hex_color(0x1A2E47),
  title_border = hex_color(0x2E4D6B),
  title_icon = hex_color(0xCCE6F5),
  title_icon_hover = hex_color(0xF2FAFF),
}

local function push_global_style()
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 12, 10)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 8)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 6)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), COLORS.bg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLORS.text)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), COLORS.input)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), COLORS.input_hover)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), COLORS.input_active)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.teal)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.teal_hover)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.teal_active)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), COLORS.border_card)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), COLORS.plate)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), COLORS.plate)
end

local function pop_global_style()
  reaper.ImGui_PopStyleColor(ctx, 11)
  reaper.ImGui_PopStyleVar(ctx, 5)
end

local function push_button_colors(bg, hover, active, text)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active)
  if text then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text)
    return 4
  end
  return 3
end

local function ensure_selected_tag(tags)
  local default_tag_id = tags[1] and tags[1].tag_id or "default"
  if state.selected_tag_id == "" or not state.selected_tag_id then
    state.selected_tag_id = default_tag_id
    common.SetExtState("selected_tag_id", state.selected_tag_id)
  else
    local tag_ok = false
    for _, tag in ipairs(tags) do
      if tag.tag_id == state.selected_tag_id then
        tag_ok = true
        break
      end
    end
    if not tag_ok then
      state.selected_tag_id = default_tag_id
      common.SetExtState("selected_tag_id", state.selected_tag_id)
    end
  end
  return default_tag_id
end

local function count_pins_for_tag(pins, tag_id)
  local count = 0
  for _, pin in ipairs(pins) do
    if pin.tag_id == tag_id then
      count = count + 1
    end
  end
  return count
end

local function compute_pins_layout(tags, pins_count)
  local tag_btn_h = 26
  local tag_rows = math.max(2, math.min(#tags + 1, 5))
  local tag_child_h = tag_rows * (tag_btn_h + 6) + 6

  local spacing = 8
  local grid_btn_h = 40
  local pin_btn_w = 200
  local cols = math.min(math.max(pins_count, 1), 5)
  local pin_rows = math.min(math.max(math.ceil(pins_count / cols), 1), 5)
  local grid_h = pin_rows * (grid_btn_h + spacing) + 6
  local pins_area_h = math.max(tag_child_h, grid_h)
  local grid_w = cols * pin_btn_w + (cols - 1) * spacing
  local tag_w = 80
  local min_cols = 2
  local min_grid_w = min_cols * pin_btn_w + (min_cols - 1) * spacing
  local pins_area_w = tag_w + spacing + math.max(grid_w, min_grid_w)

  return {
    tag_w = tag_w,
    tag_btn_h = tag_btn_h,
    tag_child_h = tag_child_h,
    spacing = spacing,
    grid_btn_h = grid_btn_h,
    grid_h = grid_h,
    pin_btn_w = pin_btn_w,
    cols = cols,
    pins_area_h = pins_area_h,
    pins_area_w = pins_area_w,
  }
end

local function compute_search_dropdown_height()
  if common.Trim(state.search_text) == "" then return 0 end
  local max_h = state.user_data.settings and state.user_data.settings.search_dropdown_max_h or 260
  local row_h = 28
  local height = math.min(#state.search_results * row_h + 6, max_h)
  if height < 0 then
    height = 0
  end
  return height
end

local function is_context_valid()
  if not ctx then return false end
  if reaper.ImGui_ValidatePtr then
    return reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*")
  end
  if reaper.ValidatePtr2 then
    return reaper.ValidatePtr2(0, ctx, "ImGui_Context*")
  end
  return true
end

local function ensure_context()
  if is_context_valid() then return true end
  if reaper.ImGui_DestroyContext and ctx then
    pcall(reaper.ImGui_DestroyContext, ctx)
  end
  ctx = reaper.ImGui_CreateContext("LaoK Clipboard")
  if not ctx then
    return false
  end
  return is_context_valid()
end

state = {
  user_data = common.NewUserData(),
  current_path = "",
  is_dirty = false,
  search_text = "",
  search_results = {},
  search_dirty = false,
  last_search_change = 0,
  project_index = {},
  last_index_poll = 0,
  last_external_check = 0,
  last_user_data_sig = "",
  last_external_conflict_sig = "",
  settings_open = false,
  pending_logs = {},
  selected_pin_id = common.GetExtState("selected_pin_id") or "",
  selected_tag_id = common.GetExtState("selected_tag_id") or "",
  rename_pin_id = nil,
  rename_text = "",
  rename_pin_open = false,
  rename_tag_id = nil,
  rename_tag_text = "",
  rename_tag_open = false,
  add_tag_open = false,
  add_tag_text = "",
  last_report_raw = "",
  last_report = nil,
  last_dirty_time = 0,
  auto_save_pending = false,
  needs_user_setup = false,
  user_name_prompt_open = false,
  user_name_prompt_text = "",
  user_name_prompt_mode = "",
  user_name_prompt_force = false,
  pending_user_dir = "",
}

local ui_visible = reaper.GetExtState(SECTION, "ui_visible")
ui_visible = (ui_visible ~= "0")

local function set_ui_visible(v)
  ui_visible = v
  reaper.SetExtState(SECTION, "ui_visible", v and "1" or "0", false)
end

local function consume_toggle_request()
  local val = reaper.GetExtState(SECTION, "toggle_request")
  if val ~= "" and val ~= "0" then
    reaper.SetExtState(SECTION, "toggle_request", "0", false)
    set_ui_visible(not ui_visible)
  end
end

local function log(level, msg)
  local line = string.format("[%s] %s", level, msg)
  local ok = common.AppendLog(state.current_path, line)
  if not ok then
    state.pending_logs[#state.pending_logs + 1] = line
  end
end

local function set_dirty(flag)
  state.is_dirty = flag
  if flag then
    state.last_dirty_time = reaper.time_precise()
    state.auto_save_pending = true
  else
    state.auto_save_pending = false
  end
  common.SetExtState("is_dirty", flag and "1" or "0")
end

local function auto_save_if_needed(now)
  if not state.is_dirty or not state.auto_save_pending then return end
  if state.current_path == "" then return end
  if now - state.last_dirty_time < 0.8 then return end
  local ok, err = common.SaveUserData(state.current_path, state.user_data)
  if ok then
    set_dirty(false)
    log("INFO", "Auto saved user data")
  else
    log("WARN", "Auto save failed: " .. tostring(err))
    state.auto_save_pending = false
  end
end

local function update_last_report()
  local raw = common.GetExtState("last_report_json")
  if raw ~= state.last_report_raw then
    state.last_report_raw = raw
    if raw ~= "" then
      local data = common.JsonDecode(raw)
      state.last_report = data
      return data
    end
    state.last_report = nil
  end
  return nil
end

local function maybe_append_pin_from_report(report)
  if not report or report.action ~= "pin" then return end
  local pin_id = report.pin_id or ""
  if pin_id == "" then return end
  local pins = state.user_data.pins or {}
  for _, pin in ipairs(pins) do
    if pin.pin_id == pin_id then
      state.selected_pin_id = pin_id
      return
    end
  end
  if state.current_path == "" then return end
  local data = common.LoadUserData(state.current_path)
  if not data or not data.pins then return end
  for _, pin in ipairs(data.pins) do
    if pin.pin_id == pin_id then
      pins[#pins + 1] = pin
      state.user_data.pins = pins
      state.selected_pin_id = pin_id
      return
    end
  end
end

local begin_child_signature = nil

local function begin_child(id, w, h, border)
  local flags = 0
  if reaper.ImGui_ChildFlags_Border and border then
    flags = reaper.ImGui_ChildFlags_Border()
  end

  if begin_child_signature == "flags" then
    local ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, flags)
    if ok then return true end
    begin_child_signature = nil
  elseif begin_child_signature == "border" then
    local ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border)
    if ok then return true end
    begin_child_signature = nil
  elseif begin_child_signature == "border_flags" then
    local ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border, flags)
    if ok then return true end
    begin_child_signature = nil
  end

  local ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, flags)
  if ok then
    begin_child_signature = "flags"
    return true
  end

  ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border)
  if ok then
    begin_child_signature = "border"
    return true
  end

  ok = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border, flags)
  if ok then
    begin_child_signature = "border_flags"
    return true
  end

  return false
end

local function draw_icon_button(label, x, y, size)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  reaper.ImGui_InvisibleButton(ctx, label, size, size)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  return hovered, reaper.ImGui_IsItemClicked(ctx, 0)
end

local function draw_title_bar()
  local title_h = 26
  local pos_x, pos_y = reaper.ImGui_GetWindowPos(ctx)
  local width = reaper.ImGui_GetWindowWidth(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

  reaper.ImGui_DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_bg, 0)
  reaper.ImGui_DrawList_AddRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_border, 0, 0, 1.2)
  reaper.ImGui_DrawList_AddText(draw_list, pos_x + 12, pos_y + 6, COLORS.text, "LaoK Clipboard v0.1")

  local icon_size = 14
  local pad = 12
  local icon_y = pos_y + (title_h - icon_size) / 2
  local cy = icon_y + icon_size / 2
  local x_hide = pos_x + width - pad - icon_size
  local x_settings = x_hide - 10 - icon_size

  local hovered, clicked = draw_icon_button("##hide", x_hide, icon_y, icon_size)
  local color = hovered and COLORS.title_icon_hover or COLORS.title_icon
  reaper.ImGui_DrawList_AddLine(draw_list, x_hide, cy, x_hide + icon_size, cy, color, 1.6)
  local hide_clicked = clicked

  hovered, clicked = draw_icon_button("##settings", x_settings, icon_y, icon_size)
  color = hovered and COLORS.title_icon_hover or COLORS.title_icon
  local cx = x_settings + icon_size / 2
  reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, icon_size / 2 - 1, color, 12, 1.4)
  reaper.ImGui_DrawList_AddLine(draw_list, cx, icon_y, cx, icon_y + 3, color, 1.2)
  reaper.ImGui_DrawList_AddLine(draw_list, cx, icon_y + icon_size - 3, cx, icon_y + icon_size, color, 1.2)
  reaper.ImGui_DrawList_AddLine(draw_list, x_settings, cy, x_settings + 3, cy, color, 1.2)
  reaper.ImGui_DrawList_AddLine(draw_list, x_settings + icon_size - 3, cy, x_settings + icon_size, cy, color, 1.2)
  local settings_clicked = clicked

  return title_h, hide_clicked, settings_clicked
end

local function draw_settings_title_bar(title, show_close)
  local title_h = 26
  local pos_x, pos_y = reaper.ImGui_GetWindowPos(ctx)
  local width = reaper.ImGui_GetWindowWidth(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

  reaper.ImGui_DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_bg, 0)
  reaper.ImGui_DrawList_AddRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_border, 0, 0, 1.2)
  reaper.ImGui_DrawList_AddText(draw_list, pos_x + 12, pos_y + 6, COLORS.text, title or "Settings")

  local close_clicked = false
  if show_close then
    local icon_size = 14
    local pad = 12
    local icon_y = pos_y + (title_h - icon_size) / 2
    local x_close = pos_x + width - pad - icon_size
    local hovered, clicked = draw_icon_button("##settings_close", x_close, icon_y, icon_size)
    local color = hovered and COLORS.title_icon_hover or COLORS.title_icon
    reaper.ImGui_DrawList_AddLine(draw_list, x_close, icon_y, x_close + icon_size, icon_y + icon_size, color, 1.6)
    reaper.ImGui_DrawList_AddLine(draw_list, x_close + icon_size, icon_y, x_close, icon_y + icon_size, color, 1.6)
    close_clicked = clicked
  end

  return title_h, close_clicked
end

local function button_black_text(label, w, h)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLORS.text_dark)
  local clicked = reaper.ImGui_Button(ctx, label, w, h)
  reaper.ImGui_PopStyleColor(ctx)
  return clicked
end

local function normalize_save_path(path, ext)
  if not path or path == "" then return "" end
  if ext and ext ~= "" then
    local lower = path:lower()
    local suffix = "." .. ext:lower()
    if lower:sub(-#suffix) ~= suffix then
      path = path .. "." .. ext
    end
  end
  return path
end

local function prompt_save_path(title, ext)
  if reaper.GetUserFileNameForWrite then
    local ok, path = reaper.GetUserFileNameForWrite("", title, ext)
    return ok, normalize_save_path(path, ext)
  end
  local ok, path = reaper.GetUserInputs(title, 1, "File path", "")
  if not ok then return false, "" end
  return true, normalize_save_path(path, ext)
end

local function prompt_open_path(title, ext)
  if reaper.GetUserFileNameForRead then
    return reaper.GetUserFileNameForRead("", title, ext)
  end
  return reaper.GetUserInputs(title, 1, "File path", "")
end

local function get_user_data_signature(path)
  if path == "" then return "" end
  if not common.FileExists(path) then return "" end
  local size = common.GetFileSize(path) or 0
  local mtime = common.GetFileModTime(path) or 0
  return tostring(size) .. ":" .. tostring(mtime)
end

local function apply_loaded_data(data, path)
  state.user_data = data
  state.current_path = path or ""
  state.search_results = {}
  state.search_dirty = true
  set_dirty(false)
  if not data.settings then
    state.user_data.settings = common.DefaultSettings()
  end
  common.EnsureTags(state.user_data)
  common.EnsureUserName(state.user_data)
  common.SetExtState("current_user_data_path", state.current_path)
  if state.current_path ~= "" then
    common.SetExtState("last_user_data_path", state.current_path)
  end
  state.needs_user_setup = false
  local pins = state.user_data.pins or {}
  local has_selected = false
  for _, pin in ipairs(pins) do
    if pin.pin_id == state.selected_pin_id then
      has_selected = true
      break
    end
  end
  if not has_selected then
    state.selected_pin_id = pins[1] and pins[1].pin_id or ""
    common.SetExtState("selected_pin_id", state.selected_pin_id)
  end
  local tags = state.user_data.tags or {}
  local selected_tag_id = state.selected_tag_id
  local tag_ok = false
  for _, tag in ipairs(tags) do
    if tag.tag_id == selected_tag_id then
      tag_ok = true
      break
    end
  end
  if not tag_ok then
    selected_tag_id = tags[1] and tags[1].tag_id or "default"
  end
  state.selected_tag_id = selected_tag_id
  common.SetExtState("selected_tag_id", selected_tag_id or "")
  state.last_user_data_sig = get_user_data_signature(state.current_path)
  state.last_external_conflict_sig = ""
  if #state.pending_logs > 0 then
    for _, line in ipairs(state.pending_logs) do
      common.AppendLog(state.current_path, line)
    end
    state.pending_logs = {}
  end
end

local function get_project_display_name(proj, proj_path)
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

local function build_project_index(proj, proj_path)
  local entries = {}
  local proj_name = get_project_display_name(proj, proj_path)

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
          position = pos,
          is_region = is_region,
        },
      }
    end
  end

  return entries
end

local function update_indexes(now)
  if now - state.last_index_poll < 0.6 then return end
  state.last_index_poll = now

  local proj_list = {}
  local idx = 0
  while true do
    local proj, proj_path = reaper.EnumProjects(idx, "")
    if not proj then break end
    proj_list[#proj_list + 1] = { handle = proj, path = proj_path }
    idx = idx + 1
  end

  local existing = {}
  for _, proj_data in ipairs(proj_list) do
    local proj = proj_data.handle
    existing[proj] = true
    local change = reaper.GetProjectStateChangeCount(proj)
    local cached = state.project_index[proj]
    if not cached or cached.last_change ~= change then
      local entries = build_project_index(proj, proj_data.path)
      state.project_index[proj] = {
        last_change = change,
        entries = entries,
        project_name = get_project_display_name(proj, proj_data.path),
      }
      log("INFO", string.format("Reindex %s: %d entries", get_project_display_name(proj, proj_data.path), #entries))
      state.search_dirty = true
    end
  end

  for proj, _ in pairs(state.project_index) do
    if not existing[proj] then
      state.project_index[proj] = nil
      state.search_dirty = true
    end
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

local function run_search()
  local query = common.Trim(state.search_text):lower()
  if query == "" then
    state.search_results = {}
    return
  end
  local tokens = common.SplitTokens(query)
  local fuzzy = state.user_data.settings and state.user_data.settings.fuzzy_enabled ~= false
  local max_results = (state.user_data.settings and state.user_data.settings.max_results) or 80

  local current_proj = select(1, reaper.EnumProjects(-1, ""))
  local results = {}
  for _, proj_data in pairs(state.project_index) do
    for _, entry in ipairs(proj_data.entries) do
      local score = score_entry(entry, tokens, query, fuzzy, current_proj)
      if score then
        results[#results + 1] = { entry = entry, score = score }
      end
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

local function select_track(track)
  if not track then return end
  reaper.Main_OnCommand(40296, 0)
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(40913, 0)
end

local function select_item(item)
  if not item then return end
  reaper.Main_OnCommand(40297, 0)
  reaper.SetMediaItemSelected(item, true)
  local track = reaper.GetMediaItemTrack(item)
  if track then
    reaper.SetTrackSelected(track, true)
  end
  reaper.Main_OnCommand(40914, 0)
end

local function jump_to_entry(entry)
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

local function ensure_user_data_loaded()
  if state.current_path ~= "" then return true end
  return false
end

local function sanitize_user_name(name)
  name = common.Trim(name or "")
  if name == "" then return "" end
  name = name:gsub("[\\/:*?\"<>|]", "_")
  return name
end

local function build_user_data_path(user_name, base_dir)
  local safe = sanitize_user_name(user_name)
  if safe == "" then return "" end
  local filename = safe .. "_ClipUserData.json"
  if base_dir == "" then return filename end
  return common.JoinPath(base_dir, filename)
end

local function save_user_data(path, data)
  common.EnsureUserName(data)
  local ok, err = common.SaveUserData(path, data)
  if not ok then
    log("WARN", "Save user data failed: " .. tostring(err))
    return false
  end
  return true
end

local function create_new_user_data(user_name, base_dir)
  local safe = sanitize_user_name(user_name)
  if safe == "" then return false end
  if base_dir == "" then return false end
  common.EnsureDir(base_dir)
  local path = build_user_data_path(safe, base_dir)
  local data = common.NewUserData()
  data.user_name = user_name
  if not save_user_data(path, data) then
    return false
  end
  apply_loaded_data(data, path)
  state.needs_user_setup = false
  return true
end

local function rename_current_user(user_name)
  local safe = sanitize_user_name(user_name)
  if safe == "" then return false end
  local dir = common.DirName(state.current_path)
  if dir == "" then return false end
  local new_path = build_user_data_path(safe, dir)
  state.user_data.user_name = user_name
  local ok = true
  if state.current_path ~= "" and state.current_path ~= new_path then
    local renamed = os.rename(state.current_path, new_path)
    if not renamed then
      ok = save_user_data(new_path, state.user_data)
    else
      ok = save_user_data(new_path, state.user_data)
    end
  else
    ok = save_user_data(state.current_path ~= "" and state.current_path or new_path, state.user_data)
  end
  if ok then
    apply_loaded_data(state.user_data, new_path)
    return true
  end
  return false
end

local function start_new_user_flow()
  local ok, path = prompt_save_path("New User Data", "json")
  if not ok or path == "" then return end
  state.pending_user_dir = common.DirName(path)
  state.user_name_prompt_text = "DefaultUser"
  state.user_name_prompt_mode = "new"
  state.user_name_prompt_force = true
  state.user_name_prompt_open = true
end

local function start_rename_user_flow()
  if state.current_path == "" then
    state.needs_user_setup = true
    return
  end
  state.user_name_prompt_text = state.user_data.user_name or "DefaultUser"
  state.user_name_prompt_mode = "rename"
  state.user_name_prompt_force = false
  state.user_name_prompt_open = true
end

local function do_new_user_data()
  start_new_user_flow()
end

local function do_load_user_data()
  if state.is_dirty and state.current_path ~= "" then
    local ok = save_user_data(state.current_path, state.user_data)
    if ok then
      set_dirty(false)
    end
  end
  local ok, path = prompt_open_path("Load User Data", "json")
  if not ok or path == "" then return end
  local data, err = common.LoadUserData(path)
  if not data then
    log("WARN", "Load failed: " .. tostring(err))
    return
  end
  apply_loaded_data(data, path)
  log("INFO", "Loaded user data: " .. path)
  state.needs_user_setup = false
end

local do_save_as_user_data

local function do_save_user_data()
  if state.current_path == "" then
    return do_save_as_user_data()
  end
  local ok, err = common.SaveUserData(state.current_path, state.user_data)
  if not ok then
    reaper.ShowMessageBox("Save failed: " .. tostring(err), "LaoK Clipboard", 0)
    return
  end
  set_dirty(false)
  state.last_user_data_sig = get_user_data_signature(state.current_path)
  log("INFO", "Saved user data")
end

do_save_as_user_data = function()
  local ok, path = prompt_save_path("Save User Data As", "json")
  if not ok or path == "" then return end
  local saved, err = common.SaveUserData(path, state.user_data)
  if not saved then
    reaper.ShowMessageBox("Save failed: " .. tostring(err), "LaoK Clipboard", 0)
    return
  end
  apply_loaded_data(state.user_data, path)
  log("INFO", "Saved user data as: " .. path)
end

local function load_last_user_data()
  local last_path = common.GetExtState("last_user_data_path")
  if last_path == "" then
    state.needs_user_setup = true
    return
  end
  if not common.FileExists(last_path) then
    state.needs_user_setup = true
    return
  end
  local data, err = common.LoadUserData(last_path)
  if not data then
    log("WARN", "Load failed: " .. tostring(err))
    state.needs_user_setup = true
    return
  end
  local auto_load = true
  if data.settings and data.settings.auto_load_last_file == false then
    auto_load = false
  end
  if auto_load then
    apply_loaded_data(data, last_path)
    log("INFO", "Auto loaded: " .. last_path)
    state.needs_user_setup = false
  else
    state.needs_user_setup = false
  end
end

local function refresh_user_data_if_changed(now)
  if state.current_path == "" then return end
  if now - state.last_external_check < 0.8 then return end
  state.last_external_check = now

  local sig = get_user_data_signature(state.current_path)
  if sig == "" or sig == state.last_user_data_sig then return end

  if state.is_dirty then
    if sig ~= state.last_external_conflict_sig then
      log("WARN", "External user data changed; local changes not saved, auto reload skipped")
      state.last_external_conflict_sig = sig
    end
    return
  end

  local data, err = common.LoadUserData(state.current_path)
  if not data then
    log("WARN", "Failed to reload user data: " .. tostring(err))
    return
  end
  apply_loaded_data(data, state.current_path)
  log("INFO", "User data reloaded from disk")
end

load_last_user_data()

local function draw_settings()
  if not state.settings_open then return end
  push_global_style()
  local title_h_fixed = 26
  local frame_h = 26
  if reaper.ImGui_GetFrameHeight then
    frame_h = reaper.ImGui_GetFrameHeight(ctx)
  end
  local text_line_h = 18
  if reaper.ImGui_GetTextLineHeightWithSpacing then
    text_line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  end
  local btn_h = 24
  local spacing_y = 6
  local user_pad_y = 6
  local settings_pad_y = 10
  local line_h = math.max(btn_h, text_line_h)
  local user_h = math.floor(user_pad_y * 2 + line_h + text_line_h)
  local gap = 8
  local settings_h = math.floor(settings_pad_y * 2 + frame_h * 2 + spacing_y)
  local desired_h = math.floor(title_h_fixed + 12 + user_h + gap + settings_h + 10)
  reaper.ImGui_SetNextWindowSize(ctx, 720, desired_h, reaper.ImGui_Cond_Always())
  local flags = reaper.ImGui_WindowFlags_NoTitleBar() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_NoScrollbar() |
    reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if reaper.ImGui_WindowFlags_NoDocking then
    flags = flags | reaper.ImGui_WindowFlags_NoDocking()
  end
  local visible, open = reaper.ImGui_Begin(ctx, "Settings", true, flags)
  if visible then
    local title_h, close_clicked = draw_settings_title_bar("Settings", true)
    if close_clicked then
      open = false
    end
    reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, user_pad_y)
    local user_ok = begin_child("SettingsUserData", -1, user_h, true)
    if user_ok then
      local user_name = state.user_data.user_name or "DefaultUser"
      reaper.ImGui_Text(ctx, "User: " .. user_name)
      local btn_h = 24
      local btn_w = 90
      local total = btn_w * 2 + 8
      local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
      local cursor_x = reaper.ImGui_GetCursorPosX(ctx)
      local region_max_x = cursor_x + (avail_w or 0)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, math.max(region_max_x - total, cursor_x))
      if reaper.ImGui_Button(ctx, "Switch User", btn_w, btn_h) then
        do_load_user_data()
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Rename", btn_w, btn_h) then
        start_rename_user_flow()
      end

      local path_text = state.current_path ~= "" and state.current_path or "<no user data>"
      reaper.ImGui_Text(ctx, "Path: " .. path_text)
      reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)

    reaper.ImGui_Dummy(ctx, 0, gap)

    local settings_ok = begin_child("SettingsOptions", -1, settings_h, true)
    if settings_ok then
      local settings = state.user_data.settings
      if not settings then
        settings = common.DefaultSettings()
        state.user_data.settings = settings
      end

      local changed
      changed, settings.debounce_ms = reaper.ImGui_InputInt(ctx, "Debounce (ms)", settings.debounce_ms or 120)
      if changed then
        set_dirty(true)
        state.search_dirty = true
      end

      changed, settings.max_results = reaper.ImGui_InputInt(ctx, "Max results", settings.max_results or 80)
      if changed then
        set_dirty(true)
        state.search_dirty = true
      end
      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_End(ctx)
  end
  pop_global_style()
  if not open then
    state.settings_open = false
  end
end

local function draw_user_setup()
  if not state.needs_user_setup then return end
  push_global_style()
  reaper.ImGui_SetNextWindowSize(ctx, 250, 130, reaper.ImGui_Cond_Appearing())
  local flags = reaper.ImGui_WindowFlags_NoTitleBar() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_NoScrollbar() |
    reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if reaper.ImGui_WindowFlags_NoDocking then
    flags = flags | reaper.ImGui_WindowFlags_NoDocking()
  end
  local visible = reaper.ImGui_Begin(ctx, "User Setup", true, flags)
  if visible then
    local title_h = draw_settings_title_bar("User Data Setup", false)
    reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)
    reaper.ImGui_Text(ctx, "未找到用户数据，请先设定用户信息。")
    reaper.ImGui_Dummy(ctx, 0, 12)
    if reaper.ImGui_Button(ctx, "新建", 100, 28) then
      start_new_user_flow()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "打开已有", 120, 28) then
      do_load_user_data()
    end
    reaper.ImGui_End(ctx)
  end
  pop_global_style()
end

local function draw_user_name_prompt()
  push_global_style()
  if state.user_name_prompt_open then
    reaper.ImGui_OpenPopup(ctx, "UserNamePrompt")
    state.user_name_prompt_open = false
  end
  reaper.ImGui_SetNextWindowSize(ctx, 250, 130, reaper.ImGui_Cond_Appearing())
  local popup_flags = 0
  if reaper.ImGui_WindowFlags_NoDocking then
    popup_flags = popup_flags | reaper.ImGui_WindowFlags_NoDocking()
  end
  local popup_visible
  if popup_flags ~= 0 then
    popup_visible = reaper.ImGui_BeginPopupModal(ctx, "UserNamePrompt", true, popup_flags)
  else
    popup_visible = reaper.ImGui_BeginPopupModal(ctx, "UserNamePrompt", true)
  end
  if popup_visible then
    reaper.ImGui_Text(ctx, "请创建用户名")
    local changed
    changed, state.user_name_prompt_text = reaper.ImGui_InputText(ctx, "Name", state.user_name_prompt_text)
    local ok = reaper.ImGui_Button(ctx, "OK", 80, 24)
    if ok then
      local name = common.Trim(state.user_name_prompt_text)
      if name ~= "" then
        local saved = false
        if state.user_name_prompt_mode == "new" then
          saved = create_new_user_data(name, state.pending_user_dir)
        elseif state.user_name_prompt_mode == "rename" then
          saved = rename_current_user(name)
        end
        if saved then
          state.user_name_prompt_mode = ""
          state.pending_user_dir = ""
          state.user_name_prompt_force = false
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      end
    end
    if not state.user_name_prompt_force then
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", 80, 24) then
        state.user_name_prompt_mode = ""
        state.pending_user_dir = ""
        state.user_name_prompt_force = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  pop_global_style()
end

local function draw_search_results()
  local height = compute_search_dropdown_height()
  if height <= 0 then return end

  local ok = begin_child("SearchDropdown", -1, height, true)
  if ok then
    local avail = reaper.ImGui_GetContentRegionAvail(ctx)
    if reaper.ImGui_BeginTable then
      local flags = reaper.ImGui_TableFlags_BordersInnerV() |
        reaper.ImGui_TableFlags_RowBg() |
        reaper.ImGui_TableFlags_Resizable()
      if reaper.ImGui_BeginTable(ctx, "SearchTable", 3, flags, avail) then
        reaper.ImGui_TableSetupColumn(ctx, "Name", reaper.ImGui_TableColumnFlags_WidthStretch(), 2.0)
        reaper.ImGui_TableSetupColumn(ctx, "Type", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)
        reaper.ImGui_TableSetupColumn(ctx, "Project", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)
        for i, entry in ipairs(state.search_results) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local label = entry.display_name .. "##sr" .. tostring(i)
          if reaper.ImGui_Selectable(ctx, label, false, reaper.ImGui_SelectableFlags_SpanAllColumns()) then
            -- single click
          end
          if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            jump_to_entry(entry)
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
      local unit = math.max(math.floor(avail / 4), 1)
      reaper.ImGui_SetColumnWidth(ctx, 0, unit * 2)
      reaper.ImGui_SetColumnWidth(ctx, 1, unit)
      reaper.ImGui_SetColumnWidth(ctx, 2, unit)
      for i, entry in ipairs(state.search_results) do
        local label = entry.display_name .. "##sr" .. tostring(i)
        if reaper.ImGui_Selectable(ctx, label, false, reaper.ImGui_SelectableFlags_SpanAllColumns()) then
          -- single click
        end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          jump_to_entry(entry)
        end
        reaper.ImGui_NextColumn(ctx)
        reaper.ImGui_Text(ctx, entry.type)
        reaper.ImGui_NextColumn(ctx)
        reaper.ImGui_Text(ctx, entry.project_name)
        reaper.ImGui_NextColumn(ctx)
      end
      reaper.ImGui_Columns(ctx, 1)
    end
    reaper.ImGui_EndChild(ctx)
  end
end

local function draw_pins()
  local tags = state.user_data.tags or {}
  local pins = state.user_data.pins or {}
  local default_tag_id = ensure_selected_tag(tags)
  local pins_count = count_pins_for_tag(pins, state.selected_tag_id)

  local layout = compute_pins_layout(tags, pins_count)
  local tag_w = layout.tag_w
  local tag_btn_h = layout.tag_btn_h
  local tag_child_h = layout.tag_child_h
  local cols = layout.cols
  local spacing = layout.spacing
  local grid_btn_h = layout.grid_btn_h
  local grid_h = layout.grid_h
  local pins_area_h = layout.pins_area_h

  local pins_area_ok = begin_child("PinsArea", -1, pins_area_h, false)
  if not pins_area_ok then return end

  reaper.ImGui_BeginGroup(ctx)
  local tag_child_ok = begin_child("TagList", tag_w, tag_child_h, true)
  if tag_child_ok then
    for i, tag in ipairs(tags) do
      local is_active = tag.tag_id == state.selected_tag_id
      local pop_colors
      if is_active then
        pop_colors = push_button_colors(COLORS.teal, COLORS.teal_hover, COLORS.teal_active, COLORS.text_dark)
      else
        pop_colors = push_button_colors(COLORS.tag_idle, COLORS.tag_hover, COLORS.tag_active, COLORS.text)
      end
      if reaper.ImGui_Button(ctx, tag.name .. "##tag" .. i, -1, tag_btn_h) then
        state.selected_tag_id = tag.tag_id
        common.SetExtState("selected_tag_id", state.selected_tag_id)
      end
      reaper.ImGui_PopStyleColor(ctx, pop_colors)

      if reaper.ImGui_BeginPopupContextItem(ctx) then
        if reaper.ImGui_MenuItem(ctx, "Rename") then
          state.rename_tag_id = tag.tag_id
          state.rename_tag_text = tag.name
          state.rename_tag_open = true
        end
        local allow_delete = tag.tag_id ~= default_tag_id
        if reaper.ImGui_MenuItem(ctx, "Delete", nil, false, allow_delete) then
          for pi = #pins, 1, -1 do
            if pins[pi].tag_id == tag.tag_id then
              pins[pi].tag_id = default_tag_id
            end
          end
          table.remove(tags, i)
          if state.selected_tag_id == tag.tag_id then
            state.selected_tag_id = default_tag_id
            common.SetExtState("selected_tag_id", state.selected_tag_id)
          end
          set_dirty(true)
        end
        reaper.ImGui_EndPopup(ctx)
      end
    end
    local pop_colors = push_button_colors(COLORS.tag_idle, COLORS.tag_hover, COLORS.tag_active, COLORS.text)
    if reaper.ImGui_Button(ctx, "+ Add Tag", -1, tag_btn_h) then
      state.add_tag_open = true
      state.add_tag_text = ""
    end
    reaper.ImGui_PopStyleColor(ctx, pop_colors)
    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_EndGroup(ctx)

  reaper.ImGui_SameLine(ctx)

  local avail = reaper.ImGui_GetContentRegionAvail(ctx)
  local grid_ok = begin_child("PinsGrid", avail, grid_h, true)
  if grid_ok then
    local filtered = {}
    for _, pin in ipairs(pins) do
      if pin.tag_id == state.selected_tag_id then
        filtered[#filtered + 1] = pin
      end
    end

    if #filtered == 0 then
      reaper.ImGui_Text(ctx, "使用Pin脚本添加图钉吧！")
    else
      local btn_w = layout.pin_btn_w
      local remove_pin_id = nil
      for i, pin in ipairs(filtered) do
        local is_selected = pin.pin_id == state.selected_pin_id
        local pop_colors
        if is_selected then
          pop_colors = push_button_colors(COLORS.teal, COLORS.teal_hover, COLORS.teal_active, COLORS.text_dark)
        else
          pop_colors = push_button_colors(COLORS.pin_idle, COLORS.pin_hover, COLORS.pin_active, COLORS.text)
        end
        if reaper.ImGui_Button(ctx, pin.pin_name .. "##pin" .. pin.pin_id, btn_w, grid_btn_h) then
          state.selected_pin_id = pin.pin_id
          common.SetExtState("selected_pin_id", state.selected_pin_id)
        end
        reaper.ImGui_PopStyleColor(ctx, pop_colors)
        if reaper.ImGui_BeginPopupContextItem(ctx) then
          if reaper.ImGui_MenuItem(ctx, "Rename") then
            state.rename_pin_id = pin.pin_id
            state.rename_text = pin.pin_name
            state.rename_pin_open = true
          end
          if reaper.ImGui_MenuItem(ctx, "Delete") then
            remove_pin_id = pin.pin_id
          end
          reaper.ImGui_EndPopup(ctx)
        end

        if (i % cols) ~= 0 then
          reaper.ImGui_SameLine(ctx)
        end
      end
      if remove_pin_id then
        for i = #pins, 1, -1 do
          if pins[i].pin_id == remove_pin_id then
            table.remove(pins, i)
            break
          end
        end
        if state.selected_pin_id == remove_pin_id then
          state.selected_pin_id = ""
          common.SetExtState("selected_pin_id", "")
        end
        set_dirty(true)
      end
    end
    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_EndChild(ctx)

  if state.add_tag_open then
    reaper.ImGui_OpenPopup(ctx, "Add Tag")
    state.add_tag_open = false
  end
  if state.rename_pin_open then
    reaper.ImGui_OpenPopup(ctx, "Rename Pin")
    state.rename_pin_open = false
  end
  if state.rename_tag_open then
    reaper.ImGui_OpenPopup(ctx, "Rename Tag")
    state.rename_tag_open = false
  end

  reaper.ImGui_SetNextWindowSize(ctx, 320, 140, reaper.ImGui_Cond_Appearing())
  if reaper.ImGui_BeginPopupModal(ctx, "Add Tag", true) then
    local changed
    changed, state.add_tag_text = reaper.ImGui_InputText(ctx, "Name", state.add_tag_text)
    if reaper.ImGui_Button(ctx, "Create", 80, 24) then
      local name = common.Trim(state.add_tag_text)
      if name ~= "" then
        local tag_id = "tag_" .. common.GenerateId()
        tags[#tags + 1] = { tag_id = tag_id, name = name, order = #tags + 1 }
        state.selected_tag_id = tag_id
        common.SetExtState("selected_tag_id", state.selected_tag_id)
        set_dirty(true)
      end
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel", 80, 24) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SetNextWindowSize(ctx, 320, 140, reaper.ImGui_Cond_Appearing())
  if reaper.ImGui_BeginPopupModal(ctx, "Rename Pin", true) then
    local changed
    changed, state.rename_text = reaper.ImGui_InputText(ctx, "Name", state.rename_text)
    if reaper.ImGui_Button(ctx, "OK", 70, 24) then
      for _, pin in ipairs(pins) do
        if pin.pin_id == state.rename_pin_id then
          pin.pin_name = state.rename_text
          set_dirty(true)
          break
        end
      end
      state.rename_pin_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel", 70, 24) then
      state.rename_pin_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SetNextWindowSize(ctx, 320, 140, reaper.ImGui_Cond_Appearing())
  if reaper.ImGui_BeginPopupModal(ctx, "Rename Tag", true) then
    local changed
    changed, state.rename_tag_text = reaper.ImGui_InputText(ctx, "Name", state.rename_tag_text)
    if reaper.ImGui_Button(ctx, "OK", 70, 24) then
      for _, tag in ipairs(tags) do
        if tag.tag_id == state.rename_tag_id then
          tag.name = state.rename_tag_text
          set_dirty(true)
          break
        end
      end
      state.rename_tag_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel", 70, 24) then
      state.rename_tag_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function draw_header()
  reaper.ImGui_PushItemWidth(ctx, -1)
  local changed
  if reaper.ImGui_InputTextWithHint then
    changed, state.search_text = reaper.ImGui_InputTextWithHint(ctx, "##search", "Search tracks, items, media, regions, markers...", state.search_text)
  else
    changed, state.search_text = reaper.ImGui_InputText(ctx, "##search", state.search_text)
  end
  reaper.ImGui_PopItemWidth(ctx)
  if changed then
    state.search_dirty = true
    state.last_search_change = reaper.time_precise()
  end

  draw_search_results()
end

local function loop()
  local now = reaper.time_precise()
  consume_toggle_request()
  reaper.gmem_write(1, now)
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 1)
    reaper.RefreshToolbar2(0, cmdID)
  end
  update_indexes(now)
  refresh_user_data_if_changed(now)
  local report = update_last_report()
  if report then
    maybe_append_pin_from_report(report)
  end

  if state.search_dirty then
    local debounce = (state.user_data.settings and state.user_data.settings.debounce_ms or 120) / 1000
    if now - state.last_search_change >= debounce then
      run_search()
      state.search_dirty = false
    end
  end

  local open = true
  local should_draw = ui_visible or state.settings_open or state.needs_user_setup or state.user_name_prompt_open
  if should_draw then
    if not ensure_context() then
      reaper.ShowMessageBox("ImGui context invalid.", "LaoK Clipboard", 0)
      return
    end
  end

  if ui_visible then
    push_global_style()
    local tags = state.user_data.tags or {}
    local pins = state.user_data.pins or {}
    ensure_selected_tag(tags)
    local pins_count = count_pins_for_tag(pins, state.selected_tag_id)
    local layout = compute_pins_layout(tags, pins_count)
    local frame_h = 26
    if reaper.ImGui_GetFrameHeight then
      frame_h = reaper.ImGui_GetFrameHeight(ctx)
    end
    local dropdown_h = compute_search_dropdown_height()
    local desired_h = 26 + 12 + frame_h + dropdown_h + 8 + layout.pins_area_h + 8 + 10
    local desired_w = 12 + layout.pins_area_w + 12
    reaper.ImGui_SetNextWindowSize(ctx, desired_w, desired_h, reaper.ImGui_Cond_Always())
    local flags = reaper.ImGui_WindowFlags_NoTitleBar() |
      reaper.ImGui_WindowFlags_NoResize() |
      reaper.ImGui_WindowFlags_NoCollapse() |
      reaper.ImGui_WindowFlags_NoScrollbar() |
      reaper.ImGui_WindowFlags_NoScrollWithMouse()
    local visible
    visible, open = reaper.ImGui_Begin(ctx, "LaoK Clipboard", true, flags)
    if visible then
      local title_h, hide_clicked, settings_clicked = draw_title_bar()
      if settings_clicked then
        state.settings_open = true
      end
      if hide_clicked then
        set_ui_visible(false)
      end
      reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)

      draw_header()
      reaper.ImGui_Dummy(ctx, 0, 8)
      draw_pins()
      reaper.ImGui_Dummy(ctx, 0, 8)

      reaper.ImGui_End(ctx)
    end
    pop_global_style()
  end

  if state.settings_open then
    draw_settings()
  end
  if state.needs_user_setup then
    draw_user_setup()
  end
  local popup_open = false
  if reaper.ImGui_IsPopupOpen then
    popup_open = reaper.ImGui_IsPopupOpen(ctx, "UserNamePrompt")
  end
  if state.user_name_prompt_open or popup_open then
    draw_user_name_prompt()
  end

  auto_save_if_needed(now)

  if open then
    reaper.defer(loop)
  else
    if cmdID and cmdID ~= 0 then
      reaper.SetToggleCommandState(0, cmdID, 0)
      reaper.RefreshToolbar2(0, cmdID)
    end
    set_main_running(false)
    if reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(ctx)
    end
  end
end

reaper.atexit(function()
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 0)
    reaper.RefreshToolbar2(0, cmdID)
  end
  set_main_running(false)
end)

reaper.defer(loop)
