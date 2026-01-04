-- @noindex
local SECTION = "LaoK_Clipboard"
local KEY_TOGGLE = "toggle_request"

reaper.SetExtState(SECTION, KEY_TOGGLE, tostring(reaper.time_precise()), false)
reaper.UpdateArrange()
