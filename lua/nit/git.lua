local M = {}

-- Run a git command asynchronously.
-- cb(stdout_lines, exit_code)
function M.run(args, cb)
  local cmd = vim.list_extend({ "git" }, args)
  local stdout_lines = {}
  local stderr_lines = {}
  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then table.insert(stdout_lines, line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then table.insert(stderr_lines, line) end
      end
    end,
    on_exit = function(_, code)
      cb(stdout_lines, code, stderr_lines)
    end,
  })
end

-- Compute the merge base between HEAD and origin/<base_ref>.
-- cb(sha_string, err)
function M.merge_base(base_ref, cb)
  M.run({ "merge-base", "HEAD", "origin/" .. base_ref }, function(lines, code, stderr)
    if code ~= 0 then
      -- Fallback: try without origin/ prefix (e.g. for local branches)
      M.run({ "merge-base", "HEAD", base_ref }, function(lines2, code2, stderr2)
        if code2 ~= 0 then
          cb(nil, table.concat(stderr2, "\n"))
        else
          cb(vim.trim(lines2[1] or ""), nil)
        end
      end)
      return
    end
    cb(vim.trim(lines[1] or ""), nil)
  end)
end

-- Get the content of a file at a specific commit as a list of lines.
-- cb(lines[], err)
function M.show(sha, path, cb)
  M.run({ "show", sha .. ":" .. path }, function(lines, code, stderr)
    if code ~= 0 then
      -- File didn't exist at that commit (new file) — return empty
      cb({}, nil)
      return
    end
    cb(lines, nil)
  end)
end

-- Get the current HEAD commit SHA.
-- cb(sha_string, err)
function M.head_sha(cb)
  M.run({ "rev-parse", "HEAD" }, function(lines, code, stderr)
    if code ~= 0 then
      cb(nil, table.concat(stderr, "\n"))
      return
    end
    cb(vim.trim(lines[1] or ""), nil)
  end)
end

return M
