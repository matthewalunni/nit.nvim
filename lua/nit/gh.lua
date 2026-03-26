local M = {}

local GH = "gh"

-- Run a gh CLI command asynchronously.
-- cb(stdout_lines, exit_code)
function M.run(args, cb)
  local cmd = vim.list_extend({ GH }, args)
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

-- Run gh and parse combined stdout as JSON.
-- cb(parsed_table, err_string|nil)
function M.json(args, cb)
  M.run(args, function(lines, code, stderr)
    if code ~= 0 then
      cb(nil, table.concat(stderr, "\n"))
      return
    end
    local raw = table.concat(lines, "\n")
    local ok, parsed = pcall(vim.json.decode, raw)
    if not ok then
      cb(nil, "JSON parse error: " .. tostring(parsed))
      return
    end
    cb(parsed, nil)
  end)
end

-- List open PRs for the current repo.
-- cb(pr_list, err)
function M.list_prs(cb)
  M.json({
    "pr", "list",
    "--json", "number,title,author,headRefName,baseRefName,headRefOid,state,isDraft,updatedAt",
    "--limit", "50",
  }, function(data, err)
    if err then return cb(nil, err) end
    -- Inject repo name into each PR object so session.init() can read it
    M.current_repo(function(repo, repo_err)
      if repo_err then return cb(nil, repo_err) end
      for _, pr in ipairs(data) do
        pr.nameWithOwner = repo
      end
      cb(data, nil)
    end)
  end)
end

-- Checkout a PR branch.
-- cb(nil, exit_code)
function M.checkout(number, cb)
  M.run({ "pr", "checkout", tostring(number) }, function(_, code)
    cb(nil, code)
  end)
end

-- Get changed files for a PR as NitFile[].
-- Parses `gh pr diff <N> --name-status` output.
-- cb(NitFile[], err)
function M.pr_files(number, cb)
  M.run({ "pr", "diff", tostring(number), "--name-status" }, function(lines, code, stderr)
    if code ~= 0 then
      return cb(nil, table.concat(stderr, "\n"))
    end
    local files = {}
    local status_map = {
      A = "added", M = "modified", D = "deleted", R = "renamed",
    }
    for _, line in ipairs(lines) do
      -- Format: "M\tpath/to/file.go"
      -- Renamed: "R100\told/path\tnew/path"
      local parts = vim.split(line, "\t", { plain = true })
      if #parts >= 2 then
        local raw_status = parts[1]:sub(1, 1)
        local status = status_map[raw_status] or "modified"
        local path = #parts >= 3 and parts[3] or parts[2]
        table.insert(files, {
          path = path,
          status = status,
          comment_count = 0,
          viewed = false,
        })
      end
    end
    cb(files, nil)
  end)
end

-- Get all inline review comments for a PR (paginated).
-- cb(comment_list, err)
function M.pr_comments(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d/comments", repo, number),
    "--paginate",
  }, function(data, err)
    if err then return cb(nil, err) end
    -- --paginate with JSON returns an array (or nested arrays for multiple pages)
    -- Flatten if needed
    if type(data) == "table" and #data > 0 and type(data[1]) == "table" and data[1][1] then
      local flat = {}
      for _, page in ipairs(data) do
        for _, item in ipairs(page) do
          table.insert(flat, item)
        end
      end
      cb(flat, nil)
    else
      cb(data, nil)
    end
  end)
end

-- Post a new inline review comment.
-- opts: { commit_id, path, line, start_line?, side, body }
-- cb(result, err)
function M.post_comment(repo, number, opts, cb)
  local args = {
    "api", string.format("/repos/%s/pulls/%d/comments", repo, number),
    "-f", "commit_id=" .. opts.commit_id,
    "-f", "path=" .. opts.path,
    "-f", "side=" .. (opts.side or "RIGHT"),
    "-F", "line=" .. opts.line,
    "-f", "body=" .. opts.body,
  }
  if opts.start_line and opts.start_line ~= opts.line then
    table.insert(args, "-F")
    table.insert(args, "start_line=" .. opts.start_line)
    table.insert(args, "-f")
    table.insert(args, "start_side=RIGHT")
  end
  M.json(args, cb)
end

-- Reply to an existing review comment.
-- cb(result, err)
function M.reply_comment(repo, number, reply_to_id, body, cb)
  M.json({
    "api", string.format("/repos/%s/pulls/%d/comments", repo, number),
    "-F", "in_reply_to=" .. reply_to_id,
    "-f", "body=" .. body,
  }, cb)
end

-- Submit a review.
-- event: "approve" | "request-changes" | "comment"
-- cb(nil, exit_code)
function M.submit_review(number, event, body, cb)
  local args = { "pr", "review", tostring(number), "--" .. event }
  if body and body ~= "" then
    table.insert(args, "--body")
    table.insert(args, body)
  end
  M.run(args, function(_, code)
    cb(nil, code)
  end)
end

-- Get the current repo's owner/name.
-- cb(repo_string, err)
function M.current_repo(cb)
  M.json({ "repo", "view", "--json", "nameWithOwner" }, function(data, err)
    if err then return cb(nil, err) end
    cb(data.nameWithOwner, nil)
  end)
end

return M
