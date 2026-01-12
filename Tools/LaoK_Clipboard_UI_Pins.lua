-- @noindex
local M = {}

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
  local tag_spacing = 6
  local tag_rows = math.max(2, math.min(#tags + 1, 5))
  local tag_row_h = tag_btn_h + tag_spacing
  local tag_child_h = math.max(0, tag_rows * tag_row_h - 5)

  local spacing_x = 8
  local spacing_y = 6
  local grid_btn_h = math.max(24, (5 * tag_row_h) / 3 - spacing_y)
  local pin_btn_w = 180
  local cols = math.min(math.max(pins_count, 1), 3)
  local pin_rows = math.max(math.ceil(pins_count / cols), 1)
  local visible_rows = math.min(pin_rows, 3)
  local grid_h = math.max(0, visible_rows * (grid_btn_h + spacing_y) - 5)
  local pins_area_h = math.max(tag_child_h, grid_h)
  local grid_w = cols * pin_btn_w + (cols - 1) * spacing_x
  local tag_w = 120
  local min_cols = 3
  local min_grid_w = min_cols * pin_btn_w + (min_cols - 1) * spacing_x
  local pins_area_w = tag_w + spacing_x + math.max(grid_w, min_grid_w)

  return {
    tag_w = tag_w,
    tag_btn_h = tag_btn_h,
    tag_child_h = tag_child_h,
    spacing = spacing_x,
    spacing_y = spacing_y,
    grid_btn_h = grid_btn_h,
    grid_h = grid_h,
    pin_btn_w = pin_btn_w,
    cols = cols,
    pins_area_h = pins_area_h,
    pins_area_w = pins_area_w,
  }
end

function M.GetLayout(state)
  local tags = state.user_data.tags or {}
  local pins = state.user_data.pins or {}
  local default_tag_id = state.ensure_selected_tag and state.ensure_selected_tag(tags) or "default"
  local pins_count = count_pins_for_tag(pins, state.selected_tag_id)
  local layout = compute_pins_layout(tags, pins_count)
  layout.pins_count = pins_count
  layout.default_tag_id = default_tag_id
  return layout
end

function M.DrawPinsArea(ctx, common, state, style, layout)
  local tags = state.user_data.tags or {}
  local pins = state.user_data.pins or {}
  local default_tag_id = layout.default_tag_id or "default"
  local max_pin_label_len = #"0123456789012"
  local max_tag_label_len = #"everything"

  local tag_w = layout.tag_w
  local tag_btn_h = layout.tag_btn_h
  local tag_child_h = layout.tag_child_h
  local cols = layout.cols
  local spacing_x = layout.spacing
  local spacing_y = layout.spacing_y or 0
  local grid_btn_h = layout.grid_btn_h
  local grid_h = layout.grid_h
  local pins_area_h = layout.pins_area_h

  local spacing_pushed = false
  if reaper.ImGui_StyleVar_ItemSpacing then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), spacing_x, spacing_y)
    spacing_pushed = true
  end

  local pins_area_ok = style.BeginChild(ctx, "PinsArea", -1, pins_area_h, false)
  if not pins_area_ok then
    if spacing_pushed then reaper.ImGui_PopStyleVar(ctx) end
    return
  end

  reaper.ImGui_BeginGroup(ctx)
  local tag_child_ok = style.BeginChild(ctx, "TagList", tag_w, tag_child_h, true)
  if tag_child_ok then
    for i, tag in ipairs(tags) do
      local is_active = tag.tag_id == state.selected_tag_id
      local text_color = is_active and style.Colors.text_dark or style.Colors.text
      local pop_colors
      if is_active then
        pop_colors = style.PushButtonColors(ctx, style.Colors.teal, style.Colors.teal_hover, style.Colors.teal_active)
      else
        pop_colors = style.PushButtonColors(ctx, style.Colors.tag_idle, style.Colors.tag_hover, style.Colors.tag_active)
      end
      local tag_label = tag.name or ""
      if #tag_label > max_tag_label_len then
        tag_label = tag_label:sub(1, max_tag_label_len)
      end
      if style.ButtonCentered(ctx, tag_label, "tag_btn_" .. tag.tag_id, -1, tag_btn_h, text_color) then
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
          if state._set_dirty then
            state._set_dirty(true)
          end
        end
        reaper.ImGui_EndPopup(ctx)
      end
    end
    local pop_colors = style.PushButtonColors(ctx, style.Colors.tag_idle, style.Colors.tag_hover, style.Colors.tag_active)
    if style.ButtonCentered(ctx, "+ Add Tag", "tag_add", -1, tag_btn_h, style.Colors.text) then
      state.add_tag_open = true
      state.add_tag_text = ""
    end
    reaper.ImGui_PopStyleColor(ctx, pop_colors)
    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_EndGroup(ctx)

  reaper.ImGui_SameLine(ctx)

  local avail = reaper.ImGui_GetContentRegionAvail(ctx)
  local grid_ok = style.BeginChild(ctx, "PinsGrid", avail, grid_h, true)
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
        local text_color = is_selected and style.Colors.text_dark or style.Colors.text
        local pop_colors
        if is_selected then
          pop_colors = style.PushButtonColors(ctx, style.Colors.teal, style.Colors.teal_hover, style.Colors.teal_active)
        else
          pop_colors = style.PushButtonColors(ctx, style.Colors.pin_idle, style.Colors.pin_hover, style.Colors.pin_active)
        end
        local pin_label = pin.pin_name or ""
        if #pin_label > max_pin_label_len then
          pin_label = pin_label:sub(1, max_pin_label_len)
        end
        if style.ButtonCentered(ctx, pin_label, "pin_btn_" .. pin.pin_id, btn_w, grid_btn_h, text_color) then
          state.selected_pin_id = pin.pin_id
          common.SetExtState("selected_pin_id", state.selected_pin_id)
        end
        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local badge_r = 8
        local pad = 6
        local badge_x = min_x + pad + badge_r
        local badge_y = min_y + pad + badge_r
        local badge_color = is_selected and style.Colors.badge_active or style.Colors.badge_idle
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, badge_x, badge_y, badge_r, badge_color)
        local badge_text = pin.pin_type == "TRACKS" and "T" or "I"
        local pushed = style.PushFontBadge(ctx)
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, badge_text)
        reaper.ImGui_DrawList_AddText(
          draw_list,
          badge_x - text_w * 0.5,
          badge_y - text_h * 0.5,
          style.Colors.text_white,
          badge_text
        )
        if pushed then
          style.PopFontBadge(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx, pop_colors)
        if reaper.ImGui_BeginPopupContextItem(ctx) then
          if reaper.ImGui_MenuItem(ctx, "Rename") then
            state.rename_pin_id = pin.pin_id
            state.rename_text = pin.pin_name
            state.rename_pin_open = true
          end
          if reaper.ImGui_MenuItem(ctx, "Move...") then
            state.move_pin_id = pin.pin_id
            state.move_pin_target_tag_id = pin.tag_id or ""
            state.move_pin_new_tag = ""
            state.move_pin_open = true
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
        if state._set_dirty then
          state._set_dirty(true)
        end
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
  if state.move_pin_open then
    reaper.ImGui_OpenPopup(ctx, "Move Pin")
    state.move_pin_open = false
  end

  reaper.ImGui_SetNextWindowSize(ctx, 360, 160, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_BeginPopupModal(ctx, "Add Tag", true) then
    local changed
    changed, state.add_tag_text = reaper.ImGui_InputText(ctx, "Name", state.add_tag_text)
    local name = common.Trim(state.add_tag_text or "")
    local too_long = #name > max_tag_label_len
    if too_long then
      if reaper.ImGui_TextColored then
        reaper.ImGui_TextColored(ctx, style.Colors.text_soft, "文本过长，不能保存")
      else
        reaper.ImGui_Text(ctx, "文本过长，不能保存")
      end
    end
    if style.ButtonCentered(ctx, "Create", "add_tag_create", 110, 30, style.Colors.text_dark) then
      if name ~= "" and not too_long then
        local tag_id = "tag_" .. common.GenerateId()
        tags[#tags + 1] = { tag_id = tag_id, name = name, order = #tags + 1 }
        state.selected_tag_id = tag_id
        common.SetExtState("selected_tag_id", state.selected_tag_id)
        if state._set_dirty then
          state._set_dirty(true)
        end
      end
      if not too_long then
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
    end
    reaper.ImGui_SameLine(ctx)
    if style.ButtonCentered(ctx, "Cancel", "add_tag_cancel", 110, 30, style.Colors.text_dark) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SetNextWindowSize(ctx, 320, 150, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_BeginPopupModal(ctx, "Rename Pin", true) then
    local changed
    changed, state.rename_text = reaper.ImGui_InputText(ctx, "Name", state.rename_text)
    if style.ButtonCentered(ctx, "OK", "rename_pin_ok", 110, 30, style.Colors.text_dark) then
      for _, pin in ipairs(pins) do
        if pin.pin_id == state.rename_pin_id then
          pin.pin_name = state.rename_text
          if state._set_dirty then
            state._set_dirty(true)
          end
          break
        end
      end
      state.rename_pin_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if style.ButtonCentered(ctx, "Cancel", "rename_pin_cancel", 110, 30, style.Colors.text_dark) then
      state.rename_pin_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SetNextWindowSize(ctx, 360, 150, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_BeginPopupModal(ctx, "Rename Tag", true) then
    local changed
    changed, state.rename_tag_text = reaper.ImGui_InputText(ctx, "Name", state.rename_tag_text)
    local trimmed = common.Trim(state.rename_tag_text or "")
    local too_long = #trimmed > max_tag_label_len
    if too_long then
      if reaper.ImGui_TextColored then
        reaper.ImGui_TextColored(ctx, style.Colors.text_soft, "文本过长，不能保存")
      else
        reaper.ImGui_Text(ctx, "文本过长，不能保存")
      end
    end
    if style.ButtonCentered(ctx, "OK", "rename_tag_ok", 110, 30, style.Colors.text_dark) then
      if not too_long then
        for _, tag in ipairs(tags) do
          if tag.tag_id == state.rename_tag_id then
            tag.name = trimmed
            if state._set_dirty then
              state._set_dirty(true)
            end
            break
          end
        end
        state.rename_tag_id = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
    end
    reaper.ImGui_SameLine(ctx)
    if style.ButtonCentered(ctx, "Cancel", "rename_tag_cancel", 110, 30, style.Colors.text_dark) then
      state.rename_tag_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_SetNextWindowSize(ctx, 360, 150, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_BeginPopupModal(ctx, "Move Pin", true) then
    if state.move_pin_target_tag_id == "" then
      state.move_pin_target_tag_id = default_tag_id
    end
    local current_name = "Select..."
    for _, tag in ipairs(tags) do
      if tag.tag_id == state.move_pin_target_tag_id then
        current_name = tag.name
        break
      end
    end
    if reaper.ImGui_BeginCombo(ctx, "Target Tag", current_name) then
      for _, tag in ipairs(tags) do
        local selected = tag.tag_id == state.move_pin_target_tag_id
        if reaper.ImGui_Selectable(ctx, tag.name, selected) then
          state.move_pin_target_tag_id = tag.tag_id
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_Dummy(ctx, 0, 6)
    local btn_h = 28
    if style.ButtonCentered(ctx, "Move", "move_pin_move", 80, btn_h, style.Colors.text_dark) then
      if state.move_pin_id and state.move_pin_target_tag_id ~= "" then
        for _, pin in ipairs(pins) do
          if pin.pin_id == state.move_pin_id then
            pin.tag_id = state.move_pin_target_tag_id
            if state._set_dirty then
              state._set_dirty(true)
            end
            break
          end
        end
        state.selected_tag_id = state.move_pin_target_tag_id
        common.SetExtState("selected_tag_id", state.selected_tag_id)
      end
      state.move_pin_id = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if style.ButtonCentered(ctx, "NewTag", "move_pin_new_tag", 80, btn_h, style.Colors.text_dark) then
      local base = "NewTag"
      local name = base
      local idx = 0
      local exists = true
      while exists do
        exists = false
        for _, tag in ipairs(tags) do
          if tag.name == name then
            exists = true
            break
          end
        end
        if exists then
          idx = idx + 1
          name = base .. tostring(idx)
        end
      end
      local tag_id = "tag_" .. common.GenerateId()
      tags[#tags + 1] = { tag_id = tag_id, name = name, order = #tags + 1 }
      if state.move_pin_id then
        for _, pin in ipairs(pins) do
          if pin.pin_id == state.move_pin_id then
            pin.tag_id = tag_id
            break
          end
        end
        state.selected_tag_id = tag_id
        common.SetExtState("selected_tag_id", state.selected_tag_id)
      end
      if state._set_dirty then
        state._set_dirty(true)
      end
      state.move_pin_id = nil
      state.move_pin_target_tag_id = ""
      state.move_pin_new_tag = ""
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  if spacing_pushed then
    reaper.ImGui_PopStyleVar(ctx)
  end
end

return M
