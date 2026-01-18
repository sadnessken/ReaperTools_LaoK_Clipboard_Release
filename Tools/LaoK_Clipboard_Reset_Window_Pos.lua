-- @noindex
local info = debug.getinfo(1, "S")
local script_path = info and info.source and info.source:sub(2) or ""
local script_dir = script_path:match("^(.*)[/\\]") or "."

local common = dofile(script_dir .. "/LaoK_Clipboard_Shared.lua")

local function get_main_window_rect()
  if not (reaper.GetMainHwnd and reaper.JS_Window_GetRect) then return nil end
  local hwnd = reaper.GetMainHwnd()
  if not hwnd then return nil end
  local ok, v1, v2, v3, v4, v5 = pcall(reaper.JS_Window_GetRect, hwnd)
  if not ok then return nil end
  local l, t, r, b
  if type(v1) == "boolean" then
    if not v1 then return nil end
    l, t, r, b = v2, v3, v4, v5
  else
    l, t, r, b = v1, v2, v3, v4
  end
  if type(l) ~= "number" or type(t) ~= "number" or type(r) ~= "number" or type(b) ~= "number" then
    return nil
  end
  return l, t, r, b
end

local function get_safe_pos()
  local l, t = get_main_window_rect()
  if l and t then
    return l + 60, t + 60
  end
  return 120, 120
end

local function move_running_window()
  if not (reaper.JS_Window_Find and reaper.JS_Window_GetRect and reaper.JS_Window_SetPosition) then
    return false
  end
  local hwnd = reaper.JS_Window_Find("LaoK Clipboard", true) or reaper.JS_Window_Find("LaoK Clipboard", false)
  if not hwnd then
    hwnd = reaper.JS_Window_Find("LaoK Clipboard v0.1.4.1", true) or reaper.JS_Window_Find("LaoK Clipboard v0.1.4.1", false)
  end
  if not hwnd then
    return false
  end
  local ok, v1, v2, v3, v4, v5 = pcall(reaper.JS_Window_GetRect, hwnd)
  if not ok then return false end
  local l, t, r, b
  if type(v1) == "boolean" then
    if not v1 then return false end
    l, t, r, b = v2, v3, v4, v5
  else
    l, t, r, b = v1, v2, v3, v4
  end
  if type(l) ~= "number" or type(t) ~= "number" or type(r) ~= "number" or type(b) ~= "number" then
    return false
  end
  local w = r - l
  local h = b - t
  local x, y = get_safe_pos()
  pcall(reaper.JS_Window_SetPosition, hwnd, x, y, w, h)
  return true
end

local function reset_extstate()
  common.SetExtState("win_x", "", false)
  common.SetExtState("win_y", "", false)
  common.SetExtState("reset_window_pos", tostring(reaper.time_precise()), true)
end

local function reset_user_data(path)
  if not path or path == "" then
    return false, "no user data path"
  end
  local data, err = common.LoadUserData(path)
  if not data then
    return false, err or "failed to load user data"
  end
  if data.settings then
    data.settings.win_x = nil
    data.settings.win_y = nil
  end
  local ok, save_err = common.SaveUserData(path, data)
  if not ok then
    return false, save_err or "failed to save user data"
  end
  return true
end

reset_extstate()
local moved = move_running_window()

local path = common.GetExtState("current_user_data_path")
local ok, err = reset_user_data(path)
if not ok then
  local msg = "Window position reset (ExtState)."
  if err and err ~= "" and err ~= "no user data path" then
    msg = msg .. "\nUser data not updated: " .. err
  elseif err == "no user data path" then
    msg = msg .. "\nUser data not loaded (no path)."
  end
  reaper.ShowMessageBox(msg, "LaoK Clipboard", 0)
  return
end

local msg = "Window position reset."
if moved then
  msg = msg .. "\nWindow moved to a safe position."
else
  msg = msg .. "\nReopen LaoK Clipboard to apply the reset."
end
reaper.ShowMessageBox(msg, "LaoK Clipboard", 0)
