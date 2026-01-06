-- @description LaoK Clipboard (Main + Actions)
-- @version 0.1.3
-- @author sadnessken
-- @about
--   LaoK_Clipboard：REAPER 常驻窗口工具（Pin/Paste/Toolbar Toggle 等脚本打包安装）。
-- @provides
--   [main] LaoK_Clipboard_Action_Pin.lua
--   [main] LaoK_Clipboard_Action_Paste.lua
--   [main] LaoK_Clipboard_Toolbar_Toggle.lua
--   LaoK_Clipboard_Shared.lua
--   LaoK_Clipboard_Indexer.lua 
--   LaoK_Clipboard_State.lua
--   LaoK_Clipboard_UI_Pins.lua
--   LaoK_Clipboard_UI_Search.lua  
--   LaoK_Clipboard_UI_Style.lua 
--   LaoK_Clipboard_UserData.lua
--   LaoK_Clipboard_Window.lua
-- @changelog
--   + Initial release
local info = debug.getinfo(1, "S")
local script_path = info and info.source and info.source:sub(2) or ""
local script_dir = script_path:match("^(.*)[/\\]") or "."

local common = dofile(script_dir .. "/LaoK_Clipboard_Shared.lua")
local State = dofile(script_dir .. "/LaoK_Clipboard_State.lua")
local Window = dofile(script_dir .. "/LaoK_Clipboard_Window.lua")
local Indexer = dofile(script_dir .. "/LaoK_Clipboard_Indexer.lua")
local UserData = dofile(script_dir .. "/LaoK_Clipboard_UserData.lua")
local Style = dofile(script_dir .. "/LaoK_Clipboard_UI_Style.lua")
local UISearch = dofile(script_dir .. "/LaoK_Clipboard_UI_Search.lua")
local UIPins = dofile(script_dir .. "/LaoK_Clipboard_UI_Pins.lua")

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

if not reaper.JS_Window_GetRect then
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 0)
    reaper.RefreshToolbar2(0, cmdID)
  end
  set_main_running(false)
  reaper.ShowMessageBox("JS_ReaScriptAPI is required.", "LaoK Clipboard", 0)
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

Style.Init(ctx)

local state = State.InitState(common)
State.LoadUIStateFromExt(common, state)
Indexer.InitIndexer(state)
UserData.LoadLastUserData(common, state)

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
  Style.Init(ctx)
  return is_context_valid()
end

local function set_ui_visible(v)
  local was = state.ui_visible
  state.ui_visible = v
  State.SaveUIStateToExt(common, state)
  if (not was) and v then
    state.win_pos_apply = true
  end
end

local function consume_toggle_request()
  local val = reaper.GetExtState(SECTION, "toggle_request")
  if val ~= "" and val ~= "0" then
    reaper.SetExtState(SECTION, "toggle_request", "0", false)
    set_ui_visible(not state.ui_visible)
  end
end

local function loop()
  local now = reaper.time_precise()
  consume_toggle_request()
  reaper.gmem_write(1, now)
  if cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(0, cmdID, 1)
    reaper.RefreshToolbar2(0, cmdID)
  end

  local is_typing = (now - state.last_search_change) < 0.4 and state.search_dirty
  Indexer.UpdateIndexes(common, state, now, reaper.GetPlayState(), is_typing)
  UserData.RefreshIfChanged(common, state, now)

  local report = UserData.UpdateLastReport(common, state)
  if report then
    UserData.MaybeAppendPinFromReport(common, state, report)
  end

  if state.search_dirty then
    local debounce = (state.user_data.settings and state.user_data.settings.debounce_ms or 120) / 1000
    if now - state.last_search_change >= debounce then
      Indexer.RunSearch(common, state, state.search_query or state.search_text)
      state.search_dirty = false
    end
  end

  local should_draw = state.ui_visible or state.settings_open or state.needs_user_setup or state.user_name_prompt_open
  if should_draw then
    if not ensure_context() then
      reaper.ShowMessageBox("ImGui context invalid.", "LaoK Clipboard", 0)
      return
    end
  end

  local open = true
  if state.ui_visible then
    Style.PushStyle(ctx)

    local layout = UIPins.GetLayout(state)
    local frame_h = 26
    if reaper.ImGui_GetFrameHeight then
      frame_h = reaper.ImGui_GetFrameHeight(ctx)
    end
    local dropdown_h = UISearch.GetDropdownHeight(common, state)
    local desired_h = Style.GetTitleBarHeight() + 12 + frame_h + dropdown_h + 8 + layout.pins_area_h + 8 + 10
    local desired_w = 12 + layout.pins_area_w + 12
    reaper.ImGui_SetNextWindowSize(ctx, desired_w, desired_h, reaper.ImGui_Cond_Always())
    local flags = reaper.ImGui_WindowFlags_NoTitleBar() |
      reaper.ImGui_WindowFlags_NoResize() |
      reaper.ImGui_WindowFlags_NoCollapse() |
      reaper.ImGui_WindowFlags_NoScrollbar() |
      reaper.ImGui_WindowFlags_NoScrollWithMouse()
    if reaper.ImGui_WindowFlags_NoDocking then
      flags = flags | reaper.ImGui_WindowFlags_NoDocking()
    end
    if reaper.ImGui_WindowFlags_NoSavedSettings then
      flags = flags | reaper.ImGui_WindowFlags_NoSavedSettings()
    end

    Window.ApplyNextWindowPos(ctx, common, state, desired_w, desired_h)

    local visible
    visible, open = reaper.ImGui_Begin(ctx, "LaoK Clipboard", true, flags)
    if visible then
      if state.win_pos_apply then
        state.win_pos_apply = false
        state.win_force_x, state.win_force_y = nil, nil
      end

      local title_h, hide_clicked, settings_clicked = Style.DrawTitleBar(ctx)
      if settings_clicked then
        state.settings_open = true
      end
      if hide_clicked then
        set_ui_visible(false)
      end
      reaper.ImGui_SetCursorPos(ctx, 12, title_h + 12)

      UISearch.DrawSearchArea(ctx, common, state, Style, Indexer)
      reaper.ImGui_Dummy(ctx, 0, 8)
      UIPins.DrawPinsArea(ctx, common, state, Style, layout)
      reaper.ImGui_Dummy(ctx, 0, 8)

      Window.UpdateAndPersistWindowPos(ctx, common, state, desired_w, desired_h, now)
      reaper.ImGui_End(ctx)
    end
    Style.PopStyle(ctx)
  end

  UserData.DrawSettings(ctx, common, state, Style)
  UserData.DrawUserSetup(ctx, common, state, Style)
  UserData.DrawUserNamePrompt(ctx, common, state, Style)

  UserData.AutoSaveIfNeeded(common, state, now)

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
