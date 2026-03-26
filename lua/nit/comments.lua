local M = {}

-- Parse raw API comment list into table<path, NitThread[]>.
-- Replies are grouped under their top-level thread.
local function parse(raw)
  local by_path = {}
  local top_level = {} -- id → NitThread
  local pending_replies = {} -- in_reply_to_id → NitComment[]

  for _, c in ipairs(raw) do
    if c.in_reply_to_id then
      pending_replies[c.in_reply_to_id] = pending_replies[c.in_reply_to_id] or {}
      table.insert(pending_replies[c.in_reply_to_id], {
        id = c.id,
        body = c.body,
        author = c.user and c.user.login or "?",
        created_at = c.created_at or c.createdAt or "",
      })
    else
      local thread = {
        id = c.id,
        path = c.path,
        line = c.line or c.original_line,
        start_line = c.start_line or c.original_start_line,
        body = c.body,
        author = c.user and c.user.login or "?",
        replies = {},
      }
      top_level[c.id] = thread
      by_path[c.path] = by_path[c.path] or {}
      table.insert(by_path[c.path], thread)
    end
  end

  -- Attach replies to their parent thread
  for id, replies in pairs(pending_replies) do
    if top_level[id] then
      top_level[id].replies = replies
    end
  end

  return by_path
end

-- Fetch all inline review comments for the current PR session.
-- cb() called on completion (with or without error).
function M.fetch(cb)
  local session = require("nit.session")
  local gh = require("nit.gh")
  local config = require("nit.config")

  if not session.is_active() then
    if cb then cb() end
    return
  end

  local s = session.get()
  if not s.repo then
    if cb then cb() end
    return
  end

  gh.pr_comments(s.repo, s.pr_number, function(raw, err)
    if err then
      vim.schedule(function()
        vim.notify("nit: failed to load comments: " .. err, vim.log.levels.WARN)
      end)
      if cb then cb() end
      return
    end

    local by_path = parse(raw or {})
    vim.schedule(function()
      session.set_comments(by_path)
      if cb then cb() end
    end)
  end)
end

function M.invalidate()
  local session = require("nit.session")
  if session.is_active() then
    local s = session.get()
    s.comments = {}
    s.comments_fetched_at = nil
  end
end

function M.is_stale()
  local session = require("nit.session")
  local config = require("nit.config")
  if not session.is_active() then return false end
  local s = session.get()
  if not s.comments_fetched_at then return true end
  return (os.time() - s.comments_fetched_at) > config.get("comment_cache_ttl")
end

return M
