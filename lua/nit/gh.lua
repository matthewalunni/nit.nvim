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
-- Uses the GitHub API to get file list with status info.
-- cb(NitFile[], err)
function M.pr_files(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d/files?per_page=100", repo, number),
    "--jq", "[.[] | {filename: .filename, status: .status}]",
  }, function(data, err)
    if err then return cb(nil, err) end
    local raw_files = data

    local status_map = {
      added    = "added",
      removed  = "deleted",
      modified = "modified",
      renamed  = "renamed",
      copied   = "added",
      changed  = "modified",
    }

    local files = {}
    for _, f in ipairs(raw_files) do
      table.insert(files, {
        path         = f.filename,
        status       = status_map[f.status] or "modified",
        comment_count = 0,
        viewed       = false,
      })
    end
    cb(files, nil)
  end)
end

-- Get all inline review comments for a PR (paginated).
-- cb(comment_list, err)
function M.pr_comments(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d/comments?per_page=100", repo, number),
  }, function(data, err)
    if err then return cb(nil, err) end
    cb(data, nil)
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

-- Run a gh CLI command with data written to its stdin.
-- cb(stdout_lines, exit_code, stderr_lines)
function M.run_with_stdin(args, stdin_data, cb)
  local cmd = vim.list_extend({ GH }, args)
  local stdout_lines = {}
  local stderr_lines = {}
  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
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
  if job_id > 0 then
    vim.fn.chansend(job_id, stdin_data)
    vim.fn.chanclose(job_id, "stdin")
  end
end

-- Create and submit a review, including any staged inline comments.
-- opts: { commit_id, body, event, comments[] }
-- event: "APPROVE" | "REQUEST_CHANGES" | "COMMENT"
-- cb(result, err)
function M.create_review(repo, number, opts, cb)
  local payload = {
    commit_id = opts.commit_id,
    body = opts.body or "",
    event = opts.event,
    comments = opts.comments or {},
  }
  local json_str = vim.json.encode(payload)
  M.run_with_stdin({
    "api", string.format("/repos/%s/pulls/%d/reviews", repo, number),
    "--method", "POST",
    "--input", "-",
  }, json_str, function(lines, code, stderr)
    if code ~= 0 then
      local raw = table.concat(lines, "\n")
      local ok, parsed = pcall(vim.json.decode, raw)
      if ok and parsed then
        if type(parsed.errors) == "table" and #parsed.errors > 0 then
          cb(nil, tostring(parsed.errors[1]))
          return
        elseif type(parsed.message) == "string" then
          cb(nil, parsed.message)
          return
        end
      end
      cb(nil, table.concat(stderr, "\n"))
      return
    end
    local raw = table.concat(lines, "\n")
    if raw == "" then
      cb({}, nil)
      return
    end
    local ok, parsed = pcall(vim.json.decode, raw)
    if not ok then
      cb(nil, "JSON parse error: " .. tostring(parsed))
      return
    end
    cb(parsed, nil)
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

-- Fetch PR metadata (title, body, state, author, base/head refs).
-- cb(data, err)
function M.pr_details(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d", repo, number),
  }, cb)
end

-- Fetch commits on a PR (up to 100).
-- cb(commit_list, err)
function M.pr_commits(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d/commits?per_page=100", repo, number),
  }, cb)
end

-- Fetch submitted reviews on a PR.
-- cb(review_list, err)
function M.pr_reviews(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/pulls/%d/reviews?per_page=100", repo, number),
  }, cb)
end

-- Fetch general issue/PR comments (the conversation at the bottom of a PR).
-- cb(comment_list, err)
function M.pr_issue_comments(repo, number, cb)
  M.json({
    "api",
    string.format("/repos/%s/issues/%d/comments?per_page=100", repo, number),
  }, cb)
end

-- Post a new general PR comment (issue comment).
-- cb(result, err)
function M.post_issue_comment(repo, number, body, cb)
  M.json({
    "api",
    string.format("/repos/%s/issues/%d/comments", repo, number),
    "--method", "POST",
    "-f", "body=" .. body,
  }, cb)
end

return M
