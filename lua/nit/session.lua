---@class NitFile
---@field path string
---@field status "added"|"modified"|"deleted"|"renamed"
---@field comment_count number
---@field viewed boolean

---@class NitComment
---@field id number
---@field body string
---@field author string
---@field created_at string

---@class NitThread
---@field id number
---@field path string
---@field line number
---@field start_line number?
---@field body string
---@field author string
---@field replies NitComment[]

---@class NitSession
---@field pr_number number
---@field repo string
---@field base_ref string
---@field head_ref string
---@field head_oid string
---@field merge_base string
---@field files NitFile[]
---@field comments table<string, NitThread[]>
---@field comments_fetched_at number?

local M = {}

---@type NitSession|nil
local state = nil

function M.is_active()
  return state ~= nil
end

---@return NitSession
function M.get()
  return state
end

-- Initialize session from a PR JSON object (from gh pr list --json).
---@param pr table
function M.init(pr)
  state = {
    pr_number = pr.number,
    repo = pr.nameWithOwner or pr.repo,
    base_ref = pr.baseRefName,
    head_ref = pr.headRefName,
    head_oid = pr.headRefOid,
    merge_base = nil,
    files = {},
    comments = {},
    comments_fetched_at = nil,
  }
end

function M.clear()
  state = nil
end

---@param files NitFile[]
function M.set_files(files)
  if not state then return end
  state.files = files
  -- Initialize comment_count on each file
  for _, f in ipairs(files) do
    f.comment_count = f.comment_count or 0
    f.viewed = f.viewed or false
  end
end

---@param by_path table<string, NitThread[]>
function M.set_comments(by_path)
  if not state then return end
  state.comments = by_path
  state.comments_fetched_at = os.time()
  -- Update comment_count on files
  for _, f in ipairs(state.files) do
    local threads = by_path[f.path] or {}
    f.comment_count = #threads
  end
end

---@param path string
---@return NitThread[]
function M.get_comments_for(path)
  if not state then return {} end
  return state.comments[path] or {}
end

-- Find a NitFile by matching the end of its path against bufname.
---@param name string  -- may be absolute path or relative path
---@return NitFile|nil
function M.get_file_by_path(name)
  if not state or name == "" then return nil end
  for _, f in ipairs(state.files) do
    -- Exact match or suffix match
    if name == f.path or name:sub(-#f.path) == f.path then
      return f
    end
  end
  return nil
end

---@param path string
---@return number
function M.comment_count_for(path)
  if not state then return 0 end
  local threads = state.comments[path] or {}
  return #threads
end

---@param path string
function M.mark_viewed(path)
  if not state then return end
  for _, f in ipairs(state.files) do
    if f.path == path then
      f.viewed = true
      return
    end
  end
end

return M
