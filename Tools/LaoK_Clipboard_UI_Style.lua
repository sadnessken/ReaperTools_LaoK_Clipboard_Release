-- @noindex
local M = {}

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
  badge_idle = hex_color(0x3D5AFE),
  badge_active = hex_color(0x00695C),
  text = hex_color(0xD1E6F2),
  text_soft = hex_color(0xD1E6F2, 0.7),
  text_dark = hex_color(0x000000),
  text_white = hex_color(0xFFFFFF),
  border_big = hex_color(0x29405C),
  border_card = hex_color(0x334E77),
  title_bg = hex_color(0x1A2E47),
  title_border = hex_color(0x2E4D6B),
  title_icon = hex_color(0xCCE6F5),
  title_icon_hover = hex_color(0xF2FAFF),
}

local font_ui = nil
local font_ui_size = 15
local font_ui_pushed = false
local font_badge = nil
local font_badge_size = 12

function M.Init(ctx)
  if reaper.ImGui_CreateFont and reaper.ImGui_Attach then
    local os = reaper.GetOS and reaper.GetOS() or ""
    local font_name = "sans-serif"
    local font_size = 15
    if os:match("Win") then
      font_name = "Segoe UI"
      font_size = 16
    end
    local ok_font, f = pcall(function()
      return reaper.ImGui_CreateFont(font_name, font_size)
    end)
    if ok_font and f then
      font_ui = f
      font_ui_size = font_size
      reaper.ImGui_Attach(ctx, font_ui)
    end

    local badge_size = math.max(10, math.floor(font_size * 0.8))
    local ok_badge, fb = pcall(function()
      return reaper.ImGui_CreateFont(font_name, badge_size)
    end)
    if ok_badge and fb then
      font_badge = fb
      font_badge_size = badge_size
      reaper.ImGui_Attach(ctx, font_badge)
    end
  end
end

local function push_font_ui(ctx)
  if not (font_ui and reaper.ImGui_PushFont) then return false end
  local ok = pcall(reaper.ImGui_PushFont, ctx, font_ui, font_ui_size)
  if ok then return true end
  ok = pcall(reaper.ImGui_PushFont, ctx, font_ui)
  return ok and true or false
end

local function pop_font_ui(ctx)
  if not reaper.ImGui_PopFont then return end
  pcall(reaper.ImGui_PopFont, ctx)
end

function M.PushFontBadge(ctx)
  if not (font_badge and reaper.ImGui_PushFont) then return false end
  local ok = pcall(reaper.ImGui_PushFont, ctx, font_badge, font_badge_size)
  if ok then return true end
  ok = pcall(reaper.ImGui_PushFont, ctx, font_badge)
  return ok and true or false
end

function M.PopFontBadge(ctx)
  if not reaper.ImGui_PopFont then return end
  pcall(reaper.ImGui_PopFont, ctx)
end

function M.PushStyle(ctx)
  font_ui_pushed = push_font_ui(ctx)
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

function M.PopStyle(ctx)
  reaper.ImGui_PopStyleColor(ctx, 11)
  reaper.ImGui_PopStyleVar(ctx, 5)
  if font_ui_pushed then
    pop_font_ui(ctx)
    font_ui_pushed = false
  end
end

function M.PushButtonColors(ctx, bg, hover, active, text)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active)
  if text then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text)
    return 4
  end
  return 3
end

function M.ButtonCentered(ctx, text, id, w, h, text_color)
  local clicked = reaper.ImGui_Button(ctx, "##" .. id, w, h)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
  local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, text)
  local x = min_x + (max_x - min_x - text_w) / 2
  local y = min_y + (max_y - min_y - text_h) / 2
  reaper.ImGui_DrawList_AddText(draw_list, x, y, text_color or COLORS.text, text)
  return clicked
end

local begin_child_signature = nil

function M.BeginChild(ctx, id, w, h, border)
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

local function draw_icon_button(ctx, label, x, y, size)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, label, size, size)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  return hovered, clicked
end

function M.DrawTitleBar(ctx)
  local title_h = 26
  local pos_x, pos_y = reaper.ImGui_GetWindowPos(ctx)
  local width = reaper.ImGui_GetWindowWidth(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

  reaper.ImGui_DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_bg, 0)
  reaper.ImGui_DrawList_AddRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + title_h, COLORS.title_border, 0, 0, 1.2)
  reaper.ImGui_DrawList_AddText(draw_list, pos_x + 12, pos_y + 6, COLORS.text, "LaoK Clipboard v0.1.3.2")

  local icon_size = 14
  local pad = 12
  local icon_y = pos_y + (title_h - icon_size) / 2
  local cy = icon_y + icon_size / 2
  local x_hide = pos_x + width - pad - icon_size
  local x_settings = x_hide - 10 - icon_size

  local hovered, clicked = draw_icon_button(ctx, "##hide", x_hide, icon_y, icon_size)
  local color = hovered and COLORS.title_icon_hover or COLORS.title_icon
  reaper.ImGui_DrawList_AddLine(draw_list, x_hide, cy, x_hide + icon_size, cy, color, 1.6)
  local hide_clicked = clicked

  hovered, clicked = draw_icon_button(ctx, "##settings", x_settings, icon_y, icon_size)
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

function M.DrawSettingsTitleBar(ctx, title, show_close)
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
    local hovered, clicked = draw_icon_button(ctx, "##settings_close", x_close, icon_y, icon_size)
    local color = hovered and COLORS.title_icon_hover or COLORS.title_icon
    reaper.ImGui_DrawList_AddLine(draw_list, x_close, icon_y, x_close + icon_size, icon_y + icon_size, color, 1.6)
    reaper.ImGui_DrawList_AddLine(draw_list, x_close + icon_size, icon_y, x_close, icon_y + icon_size, color, 1.6)
    close_clicked = clicked
  end

  return title_h, close_clicked
end

function M.GetTitleBarHeight()
  return 26
end

M.Colors = COLORS

return M
