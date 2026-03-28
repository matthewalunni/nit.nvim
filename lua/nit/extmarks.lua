local M = {}

local ns = vim.api.nvim_create_namespace("nit_comments")

-- Track which (bufnr:line) keys have expanded virt_lines extmark IDs
local expanded = {} -- key "bufnr:line" → extmark_id

-- Build virt_lines for an expanded thread view.
local function build_virt_lines(thread)
  local util = require("nit.util")
  local lines = {}

  local function push(text, hl)
    table.insert(lines, { { text, hl or "NitThreadLine" } })
  end

  local function push_multi(parts)
    table.insert(lines, parts)
  end

  -- Top divider
  push("  ┌─────────────────────────────────────────────────", "NitThreadBorder")
  -- First comment (the thread opener)
  push_multi({
    { "  │ ", "NitThreadBorder" },
    { thread.author, "NitAuthor" },
    { "  " .. util.relative_time(thread.created_at), "NitMeta" },
  })
  -- Body lines
  for _, body_line in ipairs(vim.split(thread.body, "\n", { plain = true })) do
    push_multi({
      { "  │ ", "NitThreadBorder" },
      { body_line, "NitBody" },
    })
  end
  -- Replies
  for _, reply in ipairs(thread.replies or {}) do
    push("  ├─────────────────────────────────────────────────", "NitThreadBorder")
    push_multi({
      { "  │ ", "NitThreadBorder" },
      { reply.author, "NitAuthor" },
      { "  " .. util.relative_time(reply.created_at), "NitMeta" },
    })
    for _, rline in ipairs(vim.split(reply.body, "\n", { plain = true })) do
      push_multi({
        { "  │ ", "NitThreadBorder" },
        { rline, "NitBody" },
      })
    end
  end
  push("  └─────────────────────────────────────────────────", "NitThreadBorder")

  return lines
end

-- Find the thread for a given file path and line number.
local function find_thread_at(path, line)
  local session = require("nit.session")
  for _, thread in ipairs(session.get_comments_for(path)) do
    if thread.line == line then
      return thread
    end
  end
  return nil
end

-- Render comment indicators for all threads in a file into a buffer.
---@param path string
---@param bufnr integer
function M.render_for_file(path, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  M.clear_for_buf(bufnr)
  local session = require("nit.session")
  local util = require("nit.util")
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, thread in ipairs(session.get_comments_for(path)) do
    local lnum = thread.line
    if lnum and lnum >= 1 and lnum <= line_count then
      local reply_info = #thread.replies > 0
        and (" (" .. #thread.replies .. " repl" .. (#thread.replies == 1 and "y" or "ies") .. ")")
        or ""
      local count = 1 + #thread.replies
      local sign_label = count >= 10 and "●+" or ("●" .. count) -- sign_text must be <=2 cells; "●" is 1, digits 1-9 are 1 each
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
        virt_text = {
          { " ", "NitSign" },
          { thread.author .. ": ", "NitAuthor" },
          { util.truncate(thread.body, 50), "NitBody" },
          { reply_info, "NitMeta" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
        sign_text = sign_label,
        sign_hl_group = "NitSign",
      })
    end
  end
end

-- Expand or collapse the thread at the current cursor line.
---@param bufnr integer
---@param path string
function M.toggle_thread_at_cursor(bufnr, path)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local thread = find_thread_at(path, line)
  if not thread then
    vim.notify("nit: no comment thread at this line", vim.log.levels.INFO)
    return
  end

  local key = tostring(bufnr) .. ":" .. tostring(line)
  if expanded[key] then
    -- Collapse: delete the expanded extmark
    vim.api.nvim_buf_del_extmark(bufnr, ns, expanded[key])
    expanded[key] = nil
  else
    -- Expand: add virt_lines below the indicator line
    local vl = build_virt_lines(thread)
    local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
      virt_lines = vl,
      virt_lines_above = false,
    })
    expanded[key] = mark_id
  end
end

-- Return the thread at a given path + line (for use by keymaps).
---@param path string
---@param line integer
---@return NitThread|nil
function M.thread_at(path, line)
  return find_thread_at(path, line)
end

-- Jump to the next comment extmark in the buffer.
---@param bufnr integer
---@param path string
function M.next_comment(bufnr, path)
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local session = require("nit.session")
  local threads = session.get_comments_for(path)
  -- Sort by line
  local sorted = vim.tbl_filter(function(t) return t.line ~= nil end, threads)
  table.sort(sorted, function(a, b) return a.line < b.line end)

  for _, thread in ipairs(sorted) do
    if thread.line > cur_line then
      vim.api.nvim_win_set_cursor(0, { thread.line, 0 })
      return
    end
  end
  -- Wrap around to first
  if sorted[1] then
    vim.api.nvim_win_set_cursor(0, { sorted[1].line, 0 })
  end
end

-- Jump to the previous comment extmark in the buffer.
---@param bufnr integer
---@param path string
function M.prev_comment(bufnr, path)
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local session = require("nit.session")
  local threads = session.get_comments_for(path)
  local sorted = vim.tbl_filter(function(t) return t.line ~= nil end, threads)
  table.sort(sorted, function(a, b) return a.line < b.line end)

  for i = #sorted, 1, -1 do
    if sorted[i].line < cur_line then
      vim.api.nvim_win_set_cursor(0, { sorted[i].line, 0 })
      return
    end
  end
  -- Wrap around to last
  if sorted[#sorted] then
    vim.api.nvim_win_set_cursor(0, { sorted[#sorted].line, 0 })
  end
end

-- Remove all nit extmarks from a buffer.
---@param bufnr integer
function M.clear_for_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  -- Clear expanded tracking for this buffer
  for key in pairs(expanded) do
    if key:match("^" .. tostring(bufnr) .. ":") then
      expanded[key] = nil
    end
  end
end

return M
