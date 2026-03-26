local M = {}

-- Run a shell command asynchronously.
-- cb(stdout_lines, exit_code)
function M.run_cmd(cmd_list, cb)
  local stdout_lines = {}
  vim.fn.jobstart(cmd_list, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout_lines, line)
        end
      end
    end,
    on_exit = function(_, code)
      cb(stdout_lines, code)
    end,
  })
end

-- Truncate string to max_len, appending "…" if needed.
function M.truncate(s, max_len)
  if #s <= max_len then return s end
  return s:sub(1, max_len - 1) .. "…"
end

-- Format an ISO 8601 timestamp as a relative time string (e.g. "2 days ago").
function M.relative_time(iso_str)
  if not iso_str then return "" end
  -- Parse: 2024-01-15T10:30:00Z
  local y, mo, d, h, mi, s =
    iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return iso_str end
  local t = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  })
  local diff = os.time() - t
  if diff < 60 then return "just now"
  elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
  elseif diff < 86400 * 30 then return math.floor(diff / 86400) .. "d ago"
  else return math.floor(diff / (86400 * 30)) .. "mo ago"
  end
end

-- Given a buffer name (full absolute path), return the path relative to cwd.
function M.relative_buf_path(bufname)
  if bufname == "" then return "" end
  local cwd = vim.fn.getcwd()
  if bufname:sub(1, #cwd) == cwd then
    local rel = bufname:sub(#cwd + 1)
    -- Strip leading slash
    return rel:gsub("^/", "")
  end
  return bufname
end

return M
