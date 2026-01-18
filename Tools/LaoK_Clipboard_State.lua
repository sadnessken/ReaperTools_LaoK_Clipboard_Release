-- @noindex
local M = {}

function M.InitState(common)
  local state = {
    user_data = common.NewUserData(),
    current_path = "",
    is_dirty = false,
    search_text = "",
    search_query = "",
    search_results = {},
    search_dirty = false,
    search_filter = nil,
    last_search_change = 0,
    project_index = {},
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
    move_pin_id = nil,
    move_pin_open = false,
    move_pin_target_tag_id = "",
    move_pin_new_tag = "",
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
    ui_visible = true,

    win_pos_apply = true,
    win_force_x = nil,
    win_force_y = nil,
    last_win_x = nil,
    last_win_y = nil,
    last_win_save_t = 0,
    win_dragging = false,
    drag_active = false,
    drag_start_mouse_x = nil,
    drag_start_mouse_y = nil,
    drag_start_win_x = nil,
    drag_start_win_y = nil,
    drag_last_gx = nil,
    drag_last_gy = nil,
    drag_last_ix = nil,
    drag_last_iy = nil,
    drag_scale_x = 1.0,
    drag_scale_y = ((reaper.GetOS and (reaper.GetOS():match("OSX") or reaper.GetOS():match("mac"))) and -1 or 1),
    drag_used_fallback = false,
    drag_use_js = false,
    drag_hwnd = nil,
    drag_hwnd_w = nil,
    drag_hwnd_h = nil,
    drag_offset_x = nil,
    drag_offset_y = nil,
  }

  state._set_dirty = function(flag)
    M.SetDirty(common, state, flag)
  end
  state._log = function(level, msg)
    M.Log(common, state, level, msg)
  end
  state.ensure_selected_tag = function(tags)
    return M.EnsureSelectedTag(common, state, tags)
  end

  return state
end

function M.LoadUIStateFromExt(common, state)
  state.ui_visible = common.GetExtState("ui_visible") ~= "0"
  state.selected_pin_id = common.GetExtState("selected_pin_id") or state.selected_pin_id or ""
  state.selected_tag_id = common.GetExtState("selected_tag_id") or state.selected_tag_id or ""
  local path = common.GetExtState("current_user_data_path")
  if path ~= "" then
    state.current_path = path
  end
end

function M.SaveUIStateToExt(common, state)
  common.SetExtState("ui_visible", state.ui_visible and "1" or "0", false)
end

function M.SetDirty(common, state, flag)
  state.is_dirty = flag
  if flag then
    state.last_dirty_time = reaper.time_precise()
    state.auto_save_pending = true
  else
    state.auto_save_pending = false
  end
  common.SetExtState("is_dirty", flag and "1" or "0")
end

function M.Log(common, state, level, msg)
  local line = string.format("[%s] %s", level, msg)
  local ok = common.AppendLog(state.current_path, line)
  if not ok then
    state.pending_logs[#state.pending_logs + 1] = line
  end
end

function M.EnsureSelectedTag(common, state, tags)
  local default_tag_id = "default"
  local found_default = false
  for _, tag in ipairs(tags) do
    if tag.tag_id == default_tag_id then
      found_default = true
      break
    end
  end
  if not found_default then
    table.insert(tags, 1, { tag_id = default_tag_id, name = "Default", order = 1 })
  end

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

return M
