-- @noindex
local M = {}

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

local function prompt_open_path(title, ext)
  if reaper.GetUserFileNameForRead then
    return reaper.GetUserFileNameForRead("", title, ext)
  end
  return reaper.GetUserInputs(title, 1, "File path", "")
end

local function get_user_data_signature(common, path)
  if path == "" then return "" end
  if not common.FileExists(path) then return "" end
  local size = common.GetFileSize(path) or 0
  local mtime = common.GetFileModTime(path) or 0
  return tostring(size) .. ":" .. tostring(mtime)
end

local function apply_loaded_data(common, state, data, path)
  state.user_data = data
  state.current_path = path
  common.SetExtState("current_user_data_path", path)
  state.search_dirty = true
  if state._set_dirty then
    state._set_dirty(false)
  end
  local tags = state.user_data.tags or {}
  local default_tag_id = state.ensure_selected_tag and state.ensure_selected_tag(tags) or "default"
  local pins = state.user_data.pins or {}
  if state.selected_pin_id == "" or not state.selected_pin_id then
    state.selected_pin_id = pins[1] and pins[1].pin_id or ""
    common.SetExtState("selected_pin_id", state.selected_pin_id)
  end
  state.last_user_data_sig = get_user_data_signature(common, state.current_path)
  state.last_external_conflict_sig = ""
  if #state.pending_logs > 0 then
    for _, line in ipairs(state.pending_logs) do
      common.AppendLog(state.current_path, line)
    end
    state.pending_logs = {}
  end
  if default_tag_id and state.selected_tag_id == "" then
    state.selected_tag_id = default_tag_id
    common.SetExtState("selected_tag_id", state.selected_tag_id)
  end
end

local function sanitize_user_name(common, name)
  name = common.Trim(name or "")
  if name == "" then return "" end
  name = name:gsub("[\\/:*?\"<>|]", "_")
  return name
end

local function build_user_data_path(common, user_name, base_dir)
  local safe = sanitize_user_name(common, user_name)
  if safe == "" then return "" end
  local filename = safe .. "_ClipUserData.json"
  if base_dir == "" then return filename end
  return common.JoinPath(base_dir, filename)
end

local function save_user_data(common, state, path, data)
  common.EnsureUserName(data)
  local ok, err = common.SaveUserData(path, data)
  if not ok then
    if state._log then
      state._log("WARN", "Save user data failed: " .. tostring(err))
    end
    return false
  end
  return true
end

local function create_new_user_data(common, state, user_name, base_dir)
  local safe = sanitize_user_name(common, user_name)
  if safe == "" then return false end
  if base_dir == "" then return false end
  common.EnsureDir(base_dir)
  local path = build_user_data_path(common, safe, base_dir)
  local data = common.NewUserData()
  data.user_name = user_name
  if not save_user_data(common, state, path, data) then
    return false
  end
  apply_loaded_data(common, state, data, path)
  state.needs_user_setup = false
  return true
end

local function rename_current_user(common, state, user_name)
  local safe = sanitize_user_name(common, user_name)
  if safe == "" then return false end
  local dir = common.DirName(state.current_path)
  if dir == "" then return false end
  local new_path = build_user_data_path(common, safe, dir)
  if new_path == "" then return false end
  local ok, err = common.SaveUserData(new_path, state.user_data)
  if not ok then
    if state._log then
      state._log("WARN", "Rename user failed: " .. tostring(err))
    end
    return false
  end
  state.user_data.user_name = user_name
  if state.current_path ~= new_path then
    common.SetExtState("current_user_data_path", new_path)
    state.current_path = new_path
  end
  if state._set_dirty then
    state._set_dirty(false)
  end
  return true
end

function M.StartNewUserFlow(common, state)
  if not reaper.JS_Dialog_BrowseForFolder then
    reaper.ShowMessageBox(
      "JS_ReaScriptAPI is required to create new user data.\n\nPlease install JS_ReaScriptAPI, then retry.",
      "LaoK Clipboard",
      0
    )
    return
  end
  local ok, folder = reaper.JS_Dialog_BrowseForFolder("Select User Data Folder", "")
  if not ok or folder == "" then return end
  state.pending_user_dir = folder
  state.user_name_prompt_text = ""
  state.user_name_prompt_mode = "new"
  state.user_name_prompt_open = true
  state.user_name_prompt_force = true
end

function M.StartRenameUserFlow(common, state)
  if state.current_path == "" then
    state.needs_user_setup = true
    return
  end
  state.user_name_prompt_text = state.user_data.user_name or ""
  state.user_name_prompt_mode = "rename"
  state.user_name_prompt_open = true
  state.user_name_prompt_force = false
end

function M.LoadUserData(common, state, path)
  local data, err = common.LoadUserData(path)
  if not data then
    reaper.ShowMessageBox("Load failed: " .. tostring(err), "LaoK Clipboard", 0)
    if state._log then
      state._log("WARN", "Load failed: " .. tostring(err))
    end
    return nil
  end
  data.pins = data.pins or {}
  data.settings = data.settings or common.DefaultSettings()
  common.EnsureTags(data)
  apply_loaded_data(common, state, data, path)
  if state._log then
    state._log("INFO", "Loaded user data: " .. path)
  end
  return data
end

function M.LoadLastUserData(common, state)
  local last_path = common.GetExtState("current_user_data_path")
  if last_path == "" then
    state.needs_user_setup = true
    return
  end
  local data, err = common.LoadUserData(last_path)
  if not data then
    if state._log then
      state._log("WARN", "Load failed: " .. tostring(err))
    end
    state.needs_user_setup = true
    return
  end

  local auto_load = true
  if data.settings and data.settings.auto_load_last_file == false then
    auto_load = false
  end
  if auto_load then
    data.pins = data.pins or {}
    data.settings = data.settings or common.DefaultSettings()
    common.EnsureTags(data)
    apply_loaded_data(common, state, data, last_path)
    if state._log then
      state._log("INFO", "Auto loaded: " .. last_path)
    end
  end
end

function M.SwitchUser(common, state)
  local ok, path = prompt_open_path("Open User Data", "json")
  if not ok or path == "" then return end
  M.LoadUserData(common, state, normalize_save_path(path, "json"))
end

function M.DrawUserSetup(ctx, common, state, style)
  if not state.needs_user_setup then return end
  style.PushStyle(ctx)
  reaper.ImGui_SetNextWindowSize(ctx, 480, 200, reaper.ImGui_Cond_FirstUseEver())
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
    local title_h = style.DrawSettingsTitleBar(ctx, "User Data Setup", false)
    reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)
    if reaper.ImGui_TextWrapped then
      reaper.ImGui_TextWrapped(ctx, "未找到用户数据，请先设定用户信息。")
    else
      reaper.ImGui_Text(ctx, "未找到用户数据，请先设定用户信息。")
    end
    reaper.ImGui_Dummy(ctx, 0, 12)
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local gap = 10
    local btn_w = math.max(100, math.floor((avail_w - gap) * 0.5))
    if style.ButtonCentered(ctx, "New", "user_setup_new", btn_w, 30, style.Colors.text_dark) then
      M.StartNewUserFlow(common, state)
    end
    reaper.ImGui_SameLine(ctx)
    if style.ButtonCentered(ctx, "Open", "user_setup_open", btn_w, 30, style.Colors.text_dark) then
      M.SwitchUser(common, state)
    end
  end
  reaper.ImGui_End(ctx)
  style.PopStyle(ctx)
end

function M.DrawUserNamePrompt(ctx, common, state, style)
  style.PushStyle(ctx)
  if state.user_name_prompt_open then
    reaper.ImGui_OpenPopup(ctx, "UserNamePrompt")
    state.user_name_prompt_open = false
  end
  reaper.ImGui_SetNextWindowSize(ctx, 320, 150, reaper.ImGui_Cond_FirstUseEver())
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
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local input_w = math.max(120, math.floor((avail_w or 0) * 0.5))
    reaper.ImGui_PushItemWidth(ctx, input_w)
    changed, state.user_name_prompt_text = reaper.ImGui_InputText(ctx, "Name", state.user_name_prompt_text)
    reaper.ImGui_PopItemWidth(ctx)
    local ok = style.ButtonCentered(ctx, "OK", "user_name_ok", 120, 30, style.Colors.text_dark)
    if ok then
      local name = common.Trim(state.user_name_prompt_text)
      if name ~= "" then
        local saved = false
        if state.user_name_prompt_mode == "new" then
          saved = create_new_user_data(common, state, name, state.pending_user_dir)
        elseif state.user_name_prompt_mode == "rename" then
          saved = rename_current_user(common, state, name)
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
      if style.ButtonCentered(ctx, "Cancel", "user_name_cancel", 120, 30, style.Colors.text_dark) then
        state.user_name_prompt_mode = ""
        state.pending_user_dir = ""
        state.user_name_prompt_force = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  style.PopStyle(ctx)
end

function M.DrawSettings(ctx, common, state, style)
  if not state.settings_open then return end
  style.PushStyle(ctx)

  local title_h_fixed = 26
  local frame_h = 26
  if reaper.ImGui_GetFrameHeight then
    frame_h = reaper.ImGui_GetFrameHeight(ctx)
  end
  local text_line_h = 18
  if reaper.ImGui_GetTextLineHeightWithSpacing then
    text_line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  end
  local btn_h = 30
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
    local title_h, close_clicked = style.DrawSettingsTitleBar(ctx, "Settings", true)
    if close_clicked then
      open = false
    end
    reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, user_pad_y)
    local user_visible, user_started = style.BeginChild(ctx, "SettingsUserData", -1, user_h, true)
    if user_visible then
      local user_name = state.user_data.user_name or "DefaultUser"
      reaper.ImGui_Text(ctx, "User: " .. user_name)

      local switch_label = "Switch User"
      local rename_label = "Rename"
      local switch_w = reaper.ImGui_CalcTextSize(ctx, switch_label) + 24
      local rename_w = reaper.ImGui_CalcTextSize(ctx, rename_label) + 24
      local total = switch_w + rename_w + 8
      local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
      local cursor_x = reaper.ImGui_GetCursorPosX(ctx)
      local region_max_x = cursor_x + (avail_w or 0)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, math.max(region_max_x - total, cursor_x))
      if style.ButtonCentered(ctx, switch_label, "settings_switch_user", switch_w, btn_h, style.Colors.text_dark) then
        M.SwitchUser(common, state)
      end
      reaper.ImGui_SameLine(ctx)
      if style.ButtonCentered(ctx, rename_label, "settings_rename_user", rename_w, btn_h, style.Colors.text_dark) then
        M.StartRenameUserFlow(common, state)
      end

      local path_text = state.current_path ~= "" and state.current_path or "<no user data>"
      reaper.ImGui_Text(ctx, "Path: " .. path_text)
    end
    if user_started then
      reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)

    reaper.ImGui_Dummy(ctx, 0, gap)

    local settings_visible, settings_started = style.BeginChild(ctx, "SettingsOptions", -1, settings_h, true)
    if settings_visible then
      local settings = state.user_data.settings
      if not settings then
        settings = common.DefaultSettings()
        state.user_data.settings = settings
      end

      local changed
      changed, settings.debounce_ms = reaper.ImGui_InputInt(ctx, "Debounce (ms)", settings.debounce_ms or 120)
      if changed and state._set_dirty then
        state._set_dirty(true)
        state.search_dirty = true
      end

      changed, settings.max_results = reaper.ImGui_InputInt(ctx, "Max results", settings.max_results or 80)
      if changed and state._set_dirty then
        state._set_dirty(true)
        state.search_dirty = true
      end

      changed, settings.disable_paste_console_logs = reaper.ImGui_Checkbox(ctx, "Disable paste console logs", settings.disable_paste_console_logs or false)
      if changed and state._set_dirty then
        state._set_dirty(true)
      end
    end
    if settings_started then
      reaper.ImGui_EndChild(ctx)
    end
  end
  reaper.ImGui_End(ctx)
  style.PopStyle(ctx)
  if not open then
    state.settings_open = false
  end
end

function M.AutoSaveIfNeeded(common, state, now)
  if not state.is_dirty or not state.auto_save_pending then return end
  if state.current_path == "" then return end
  if now - state.last_dirty_time < 0.8 then return end
  local ok, err = common.SaveUserData(state.current_path, state.user_data)
  if ok then
    if state._set_dirty then
      state._set_dirty(false)
    end
    if state._log then
      state._log("INFO", "Auto saved user data")
    end
  else
    if state._log then
      state._log("WARN", "Auto save failed: " .. tostring(err))
    end
    state.auto_save_pending = false
  end
end

function M.UpdateLastReport(common, state)
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

function M.MaybeAppendPinFromReport(common, state, report)
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

function M.RefreshIfChanged(common, state, now)
  if state.current_path == "" then return end
  if now - state.last_external_check < 1.0 then return end
  state.last_external_check = now
  local sig = get_user_data_signature(common, state.current_path)
  if sig == "" then return end
  if sig == state.last_user_data_sig then return end
  if state.is_dirty then
    if state.last_external_conflict_sig ~= sig then
      if state._log then
        state._log("WARN", "External user data changed; local changes not saved, auto reload skipped")
      end
      state.last_external_conflict_sig = sig
    end
    return
  end

  local data, err = common.LoadUserData(state.current_path)
  if not data then
    if state._log then
      state._log("WARN", "Failed to reload user data: " .. tostring(err))
    end
    return
  end
  apply_loaded_data(common, state, data, state.current_path)
  if state._log then
    state._log("INFO", "User data reloaded from disk")
  end
end

return M
