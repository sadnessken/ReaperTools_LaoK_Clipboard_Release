-- @noindex
local M = {}

M.SECTION = "LaoK_Clipboard"

local function is_windows()
  local osname = reaper.GetOS() or ""
  return osname:match("Win") ~= nil
end

local function path_sep()
  if is_windows() then return "\\" end
  return "/"
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_path(path)
  path = path or ""
  local sep = path_sep()
  local last = path:match(".*()" .. sep)
  if not last then return "", path end
  return path:sub(1, last - 1), path:sub(last + 1)
end

function M.JoinPath(a, b)
  a = a or ""
  b = b or ""
  if a == "" then return b end
  local sep = path_sep()
  if a:sub(-1) == sep then
    return a .. b
  end
  return a .. sep .. b
end

function M.DirName(path)
  if not path or path == "" then return "" end
  local dir, _ = split_path(path)
  return dir
end

function M.BaseName(path)
  if not path or path == "" then return "" end
  local _, name = split_path(path)
  return name
end

function M.ShellQuoteUnix(value)
  value = tostring(value or "")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.GetMediaSourceFileNameSafe(src)
  if not src then return "" end
  if not reaper.GetMediaSourceFileName then return "" end
  local ok, path = reaper.GetMediaSourceFileName(src, "")
  if type(ok) == "string" and path == nil then
    return ok
  end
  if ok and type(path) == "string" then
    return path
  end
  if type(ok) == "string" then
    return ok
  end
  return ""
end

function M.ResolveMaybeRelativePath(path, project_path)
  if not path or path == "" then return "" end
  if path:sub(1, 1) == "/" then return path end
  if path:match("^%a:[/\\]") then return path end
  local proj_dir = M.DirName(project_path or "")
  if proj_dir == "" then
    return path
  end
  return M.JoinPath(proj_dir, path)
end

function M.SplitExt(name)
  local base, ext = name:match("^(.*)%.([^%.]+)$")
  if not base then return name, "" end
  return base, ext
end

function M.FileExists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function M.DirExists(path)
  if not path or path == "" then return false end
  if reaper.EnumerateSubdirectories and reaper.EnumerateSubdirectories(path, 0) then
    return true
  end
  if reaper.EnumerateFiles and reaper.EnumerateFiles(path, 0) then
    return true
  end
  local ok = os.rename(path, path)
  return ok == true
end

function M.ReadFile(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

function M.WriteFileAtomic(path, content)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  f:write(content)
  f:close()
  local ok, ren_err = os.rename(tmp, path)
  if not ok then
    if M.FileExists(path) then
      local backup = path .. ".bak"
      os.remove(backup)
      local ok_backup = os.rename(path, backup)
      if ok_backup then
        ok, ren_err = os.rename(tmp, path)
        if not ok then
          os.rename(backup, path)
        end
      end
    end
  end
  if not ok then
    return nil, ren_err or "rename failed"
  end
  return true
end

function M.EnsureDir(path)
  local ok = reaper.RecursiveCreateDirectory(path, 0)
  if ok == 1 then
    return true, ok
  end
  if M.DirExists(path) then
    return true, ok
  end
  return false, ok
end

function M.IsoNowUtc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.GetExtState(key)
  return reaper.GetExtState(M.SECTION, key)
end

function M.SetExtState(key, value, persist)
  reaper.SetExtState(M.SECTION, key, value or "", persist ~= false)
end

function M.GetUserLogPath(user_data_path)
  if not user_data_path or user_data_path == "" then return "" end
  local dir = M.DirName(user_data_path)
  if dir == "" then return "userdata.log" end
  return M.JoinPath(dir, "userdata.log")
end

function M.AppendLog(user_data_path, line)
  local path = M.GetUserLogPath(user_data_path)
  if path == "" then return false end
  local f = io.open(path, "a")
  if not f then return false end
  f:write(line .. "\n")
  f:close()
  return true
end

local function encode_string(str)
  local replacements = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }
  return '"' .. str:gsub("[\\\"%z\1-\31]", function(c)
    return replacements[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function is_array(tbl)
  local n = 0
  for k, _ in pairs(tbl) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  for i = 1, n do
    if tbl[i] == nil then return false end
  end
  return true
end

function M.JsonEncode(value)
  local t = type(value)
  if t == "nil" then return "null" end
  if t == "boolean" then return value and "true" or "false" end
  if t == "number" then return tostring(value) end
  if t == "string" then return encode_string(value) end
  if t == "table" then
    local parts = {}
    if is_array(value) then
      for i = 1, #value do
        parts[#parts + 1] = M.JsonEncode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(value) do
        parts[#parts + 1] = encode_string(tostring(k)) .. ":" .. M.JsonEncode(v)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

local function decode_error(idx, msg)
  return nil, string.format("JSON decode error at %d: %s", idx, msg)
end

function M.JsonDecode(str)
  local idx = 1
  local len = #str

  local function skip_ws()
    while idx <= len do
      local c = str:sub(idx, idx)
      if c == " " or c == "\n" or c == "\r" or c == "\t" then
        idx = idx + 1
      else
        break
      end
    end
  end

  local function parse_string()
    idx = idx + 1
    local out = {}
    while idx <= len do
      local c = str:sub(idx, idx)
      if c == '"' then
        idx = idx + 1
        return table.concat(out)
      elseif c == "\\" then
        local esc = str:sub(idx + 1, idx + 1)
        if esc == '"' or esc == "\\" or esc == "/" then
          out[#out + 1] = esc
          idx = idx + 2
        elseif esc == "b" then out[#out + 1] = "\b"; idx = idx + 2
        elseif esc == "f" then out[#out + 1] = "\f"; idx = idx + 2
        elseif esc == "n" then out[#out + 1] = "\n"; idx = idx + 2
        elseif esc == "r" then out[#out + 1] = "\r"; idx = idx + 2
        elseif esc == "t" then out[#out + 1] = "\t"; idx = idx + 2
        elseif esc == "u" then
          local hex = str:sub(idx + 2, idx + 5)
          if not hex:match("%x%x%x%x") then
            return decode_error(idx, "invalid unicode escape")
          end
          local code = tonumber(hex, 16)
          if code < 128 then
            out[#out + 1] = string.char(code)
          else
            -- Preserve as UTF-8 by packing the codepoint.
            if code < 2048 then
              out[#out + 1] = string.char(192 + math.floor(code / 64))
              out[#out + 1] = string.char(128 + (code % 64))
            else
              out[#out + 1] = string.char(224 + math.floor(code / 4096))
              out[#out + 1] = string.char(128 + (math.floor(code / 64) % 64))
              out[#out + 1] = string.char(128 + (code % 64))
            end
          end
          idx = idx + 6
        else
          return decode_error(idx, "invalid escape")
        end
      else
        out[#out + 1] = c
        idx = idx + 1
      end
    end
    return decode_error(idx, "unterminated string")
  end

  local function parse_number()
    local start = idx
    local c = str:sub(idx, idx)
    if c == "-" then idx = idx + 1 end
    while idx <= len and str:sub(idx, idx):match("%d") do idx = idx + 1 end
    if str:sub(idx, idx) == "." then
      idx = idx + 1
      while idx <= len and str:sub(idx, idx):match("%d") do idx = idx + 1 end
    end
    local e = str:sub(idx, idx)
    if e == "e" or e == "E" then
      idx = idx + 1
      local sign = str:sub(idx, idx)
      if sign == "+" or sign == "-" then idx = idx + 1 end
      while idx <= len and str:sub(idx, idx):match("%d") do idx = idx + 1 end
    end
    local num = tonumber(str:sub(start, idx - 1))
    if num == nil then return decode_error(start, "invalid number") end
    return num
  end

  local function parse_literal(lit, val)
    if str:sub(idx, idx + #lit - 1) == lit then
      idx = idx + #lit
      return val
    end
    return decode_error(idx, "invalid literal")
  end

  local parse_value

  local function parse_array()
    idx = idx + 1
    local out = {}
    skip_ws()
    if str:sub(idx, idx) == "]" then idx = idx + 1 return out end
    while idx <= len do
      local val, err = parse_value()
      if err then return nil, err end
      out[#out + 1] = val
      skip_ws()
      local c = str:sub(idx, idx)
      if c == "," then
        idx = idx + 1
      elseif c == "]" then
        idx = idx + 1
        return out
      else
        return decode_error(idx, "expected , or ]")
      end
      skip_ws()
    end
    return decode_error(idx, "unterminated array")
  end

  local function parse_object()
    idx = idx + 1
    local out = {}
    skip_ws()
    if str:sub(idx, idx) == "}" then idx = idx + 1 return out end
    while idx <= len do
      if str:sub(idx, idx) ~= '"' then
        return decode_error(idx, "expected string key")
      end
      local key, err = parse_string()
      if err then return nil, err end
      skip_ws()
      if str:sub(idx, idx) ~= ":" then
        return decode_error(idx, "expected :")
      end
      idx = idx + 1
      skip_ws()
      local val
      val, err = parse_value()
      if err then return nil, err end
      out[key] = val
      skip_ws()
      local c = str:sub(idx, idx)
      if c == "," then
        idx = idx + 1
      elseif c == "}" then
        idx = idx + 1
        return out
      else
        return decode_error(idx, "expected , or }")
      end
      skip_ws()
    end
    return decode_error(idx, "unterminated object")
  end

  parse_value = function()
    skip_ws()
    if idx > len then return decode_error(idx, "unexpected end") end
    local c = str:sub(idx, idx)
    if c == '"' then return parse_string()
    elseif c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == "t" then return parse_literal("true", true)
    elseif c == "f" then return parse_literal("false", false)
    elseif c == "n" then return parse_literal("null", nil)
    else
      return parse_number()
    end
  end

  local val, err = parse_value()
  if err then return nil, err end
  return val
end

function M.DefaultSettings()
  return {
    debounce_ms = 120,
    max_results = 80,
    fuzzy_enabled = true,
    auto_load_last_file = true,
    hash_algo = "SHA1",
    media_root_mode = "PROJECT_MEDIA_PATH_ELSE_PROJECTDIR_MEDIA",
    log_level = "INFO",
    search_dropdown_max_h = 260,
    hash_dedupe_enabled = true,
    disable_paste_console_logs = false,
    hash_failure_mode = "FALLBACK",
    peaks_refresh_after_paste = false,
  }
end

function M.EnsureTags(data)
  data.tags = data.tags or {}
  if #data.tags == 0 then
    data.tags[1] = { tag_id = "default", name = "Default", order = 1 }
  end
  for i, tag in ipairs(data.tags) do
    if not tag.tag_id or tag.tag_id == "" then
      tag.tag_id = "tag_" .. tostring(i)
    end
    if not tag.name or tag.name == "" then
      tag.name = "Tag " .. tostring(i)
    end
    tag.order = tag.order or i
  end
  local default_id = data.tags[1].tag_id or "default"
  for _, pin in ipairs(data.pins or {}) do
    if not pin.tag_id or pin.tag_id == "" then
      pin.tag_id = default_id
    end
  end
end

function M.EnsureUserName(data)
  data.user_name = data.user_name or ""
  if data.user_name == "" then
    data.user_name = "DefaultUser"
  end
end

function M.NewUserData()
  local now = M.IsoNowUtc()
  local data = {
    schema_version = 1,
    meta = {
      created_at = now,
      last_modified_at = now,
      tool_version = "0.1",
    },
    user_name = "DefaultUser",
    settings = M.DefaultSettings(),
    tags = {
      { tag_id = "default", name = "Default", order = 1 },
    },
    pins = {},
  }
  return data
end

function M.LoadUserData(path)
  local content, err = M.ReadFile(path)
  if not content then return nil, err end
  local data, decode_err = M.JsonDecode(content)
  if not data then return nil, decode_err end
  data.settings = data.settings or M.DefaultSettings()
  M.EnsureTags(data)
  M.EnsureUserName(data)
  return data
end

function M.SaveUserData(path, data)
  data.meta = data.meta or {}
  data.meta.last_modified_at = M.IsoNowUtc()
  local json = M.JsonEncode(data)
  return M.WriteFileAtomic(path, json)
end

function M.GenerateId()
  if reaper.genGuid then
    local guid = reaper.genGuid()
    return guid:gsub("[{}]", "")
  end
  return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

function M.GetCurrentProject()
  local proj, proj_path = reaper.EnumProjects(-1, "")
  local proj_name = ""
  if proj then
    local ok, name = reaper.GetProjectName(proj, "")
    if ok then proj_name = name end
  end
  return proj, proj_path or "", proj_name or ""
end

function M.GetProjectDir(project_path)
  return M.DirName(project_path or "")
end

function M.GetTrackByGUID(proj, guid)
  if reaper.BR_GetTrackByGUID then
    return reaper.BR_GetTrackByGUID(proj, guid)
  end
  local count = reaper.CountTracks(proj)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(proj, i)
    if track then
      local tg = reaper.GetTrackGUID(track)
      if tg == guid then return track end
    end
  end
  return nil
end

function M.GetItemByGUID(proj, guid)
  if reaper.BR_GetMediaItemByGUID then
    return reaper.BR_GetMediaItemByGUID(proj, guid)
  end
  local tracks = reaper.CountTracks(proj)
  for i = 0, tracks - 1 do
    local track = reaper.GetTrack(proj, i)
    local items = reaper.CountTrackMediaItems(track)
    for j = 0, items - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local ok, ig = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      if ok and ig == guid then return item end
    end
  end
  return nil
end

function M.GetItemGUID(item)
  if not item then return nil end
  if reaper.ValidatePtr2 then
    if not reaper.ValidatePtr2(0, item, "MediaItem*") then return nil end
  else
    if type(item) ~= "userdata" then return nil end
  end
  if reaper.BR_GetMediaItemGUID then
    return reaper.BR_GetMediaItemGUID(item)
  end
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if ok then return guid end
  return nil
end

function M.ExtractFilePathsFromChunk(chunk)
  local paths = {}
  local seen = {}
  for path in chunk:gmatch('FILE%s+"(.-)"') do
    if not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end
  return paths
end

function M.ExtractFilePathsFromChunkOrdered(chunk)
  local paths = {}
  for path in chunk:gmatch('FILE%s+"(.-)"') do
    paths[#paths + 1] = path
  end
  return paths
end

function M.StripItemBlocksFromTrackChunk(chunk)
  local lines = {}
  for line in chunk:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line:gsub("\r", "")
  end
  if chunk:sub(-1) ~= "\n" then
    local last = chunk:match("([^\n]*)$") or ""
    lines[#lines + 1] = last:gsub("\r", "")
  end

  local out = {}
  local depth = 0
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if depth == 0 then
      if trimmed:match("^<ITEM") then
        depth = 1
      else
        out[#out + 1] = line
      end
    else
      if trimmed:sub(1, 1) == "<" then
        depth = depth + 1
      end
      if trimmed == ">" then
        depth = depth - 1
      end
    end
  end
  return table.concat(out, "\n")
end

function M.ReplaceChunkFilePaths(chunk, map, missing)
  missing = missing or {}
  local replaced = chunk:gsub('FILE%s+"(.-)"', function(src)
    local dest = map[src]
    if not dest then
      missing[src] = true
      return 'FILE "' .. src .. '"'
    end
    return 'FILE "' .. dest .. '"'
  end)
  return replaced, missing
end

function M.GetFileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

function M.GetFileModTime(path)
  if reaper.CF_GetFileModTime then
    return reaper.CF_GetFileModTime(path)
  end
  return 0
end

local hash_cache = {}

function M.FallbackHashFromStat(path)
  local size = M.GetFileSize(path) or 0
  local mtime = M.GetFileModTime(path) or 0
  local a = size % 4294967296
  local b = mtime % 4294967296
  local val = (a + (b * 31)) % 4294967296
  return string.format("%08x", val)
end

function M.ComputeHash(path)
  local size = M.GetFileSize(path) or 0
  local mtime = M.GetFileModTime(path) or 0
  local key = path .. ":" .. tostring(size) .. ":" .. tostring(mtime)
  if hash_cache[key] then return hash_cache[key] end

  local osname = reaper.GetOS() or ""
  local cmd
  if osname:match("Win") then
    cmd = string.format('certutil -hashfile "%s" SHA1', path)
  elseif osname:match("OSX") or osname:match("mac") or osname:match("Darwin") then
    cmd = string.format("/usr/bin/shasum -a 1 %s", M.ShellQuoteUnix(path))
  else
    cmd = string.format("/usr/bin/sha1sum %s", M.ShellQuoteUnix(path))
  end
  local rv, output = reaper.ExecProcess(cmd, 10000)
  if rv ~= 0 then
    local out = tostring(output or "")
    if #out > 200 then
      out = out:sub(1, 200)
    end
    return nil, string.format("hash command failed rv=%s cmd=%s out=%s", tostring(rv), cmd, out)
  end
  local hash = output:match("^([0-9a-fA-F]+)")
  if not hash then
    hash = output:match("\n([0-9a-fA-F]+)\n")
  end
  if not hash then return nil, "hash parse failed" end
  hash = hash:lower()
  hash_cache[key] = hash
  return hash
end

function M.CopyFile(src, dest)
  local in_f, err = io.open(src, "rb")
  if not in_f then return nil, err end
  local out_f, err2 = io.open(dest, "wb")
  if not out_f then in_f:close() return nil, err2 end
  while true do
    local chunk = in_f:read(65536)
    if not chunk then break end
    out_f:write(chunk)
  end
  in_f:close()
  out_f:close()
  return true
end

function M.SplitTokens(text)
  local tokens = {}
  for token in tostring(text):gmatch("%S+") do
    tokens[#tokens + 1] = token:lower()
  end
  return tokens
end

function M.Trim(text)
  return trim(text or "")
end

return M
