-- @noindex
local M = {}

local function clamp_to_viewport(x, y, w, h)
  if not x or not y or not w or not h then return x, y end
  if not reaper.my_getViewport then return x, y end
  local ok, v1, v2, v3, v4, v5 =
  pcall(reaper.my_getViewport, 0, 0, 0, 0, x, y, x + w, y + h, true)
if not ok then return x, y end

local l, t, r, b
if type(v1) == "boolean" then
  -- 某些环境返回：retval, l, t, r, b
  if not v1 then return x, y end
  l, t, r, b = v2, v3, v4, v5
else
  -- 常规返回：l, t, r, b
  l, t, r, b = v1, v2, v3, v4
end

if type(l) ~= "number" or type(t) ~= "number" or type(r) ~= "number" or type(b) ~= "number" then
  return x, y
end


  local pad = 20
  local min_x = l + pad
  local min_y = t + pad
  local max_x = (r - w) - pad
  local max_y = (b - h) - pad

  if max_x < min_x then
    x = l + math.max(0, (r - l - w) * 0.5)
  else
    x = math.max(min_x, math.min(x, max_x))
  end

  if max_y < min_y then
    y = t + math.max(0, (b - t - h) * 0.5)
  else
    y = math.max(min_y, math.min(y, max_y))
  end

  return x, y
end

local function get_main_window_rect()
  if not (reaper.GetMainHwnd and reaper.JS_Window_GetRect) then return nil end
  local hwnd = reaper.GetMainHwnd()
  if not hwnd then return nil end

  local ok, v1, v2, v3, v4, v5 = pcall(reaper.JS_Window_GetRect, hwnd)
  if not ok then return nil end

  local l, t, r, b
  if type(v1) == "boolean" then
    -- 某些环境：retval, l, t, r, b
    if not v1 then return nil end
    l, t, r, b = v2, v3, v4, v5
  else
    -- 常规：l, t, r, b
    l, t, r, b = v1, v2, v3, v4
  end

  if type(l) ~= "number" or type(t) ~= "number" or type(r) ~= "number" or type(b) ~= "number" then
    return nil
  end

  return l, t, r, b
end

local function ensure_settings_table(state, common)
  if not state.user_data.settings then
    state.user_data.settings = common.DefaultSettings()
  end
  return state.user_data.settings
end

local function get_saved_main_window_pos(state, common)
  local s = ensure_settings_table(state, common)
  local x = tonumber(s.win_x)
  local y = tonumber(s.win_y)
  if not x or not y then
    x = tonumber(common.GetExtState("win_x"))
    y = tonumber(common.GetExtState("win_y"))
  end
  return x, y
end

local function save_main_window_pos(state, common, x, y)
  local s = ensure_settings_table(state, common)
  s.win_x, s.win_y = x, y
  common.SetExtState("win_x", tostring(x))
  common.SetExtState("win_y", tostring(y))
  if state.current_path ~= "" and state._set_dirty then
    state._set_dirty(true)
  end
end

local function get_first_run_window_pos(w, h)
  local l, t, r, b = get_main_window_rect()
  if l and t and r and b then
    local x = l + 60
    local y = t + 60
    return clamp_to_viewport(x, y, w, h)
  end
  return 120, 120
end

function M.ApplyNextWindowPos(ctx, common, state, desired_w, desired_h)
  if state.win_pos_apply then
    local x, y = state.win_force_x, state.win_force_y
    if not x or not y then
      x, y = get_saved_main_window_pos(state, common)
    end
    if not x or not y then
      x, y = get_first_run_window_pos(desired_w, desired_h)
    end
    x, y = clamp_to_viewport(x, y, desired_w, desired_h)
    reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_Always())
  end
end

function M.UpdateAndPersistWindowPos(ctx, common, state, desired_w, desired_h, now)
  local wx, wy = reaper.ImGui_GetWindowPos(ctx)
  if wx and wy then
    local cx, cy = clamp_to_viewport(wx, wy, desired_w, desired_h)
    if (math.abs(cx - wx) > 1) or (math.abs(cy - wy) > 1) then
      state.win_force_x, state.win_force_y = cx, cy
      state.win_pos_apply = true
    end

    local moved = (not state.last_win_x) or (math.abs(wx - state.last_win_x) > 0.5) or (math.abs(wy - state.last_win_y) > 0.5)
    if moved and (now - (state.last_win_save_t or 0)) > 0.25 then
      state.last_win_x, state.last_win_y = wx, wy
      state.last_win_save_t = now
      save_main_window_pos(state, common, wx, wy)
    end
  end
end

M.ClampToViewport = clamp_to_viewport

return M
