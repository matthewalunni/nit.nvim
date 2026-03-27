local M = {}

local DIFF_NS = vim.api.nvim_create_namespace("nit_diff")

vim.api.nvim_set_hl(0, "NitDiffAdd",    { bg = "#1a3a1a", fg = "#73c991", bold = false })
vim.api.nvim_set_hl(0, "NitDiffDelete", { bg = "#3a1a1a", fg = "#f48771", bold = false })
vim.api.nvim_set_hl(0, "NitDiffChange", { bg = "#2a2a10", fg = "#dcdcaa", bold = false })

local state = {
  base_win = nil,
  head_win = nil,
  hunks    = {},  -- list of { head_start, head_end } for ]c / [c navigation
}

-- Find the first non-panel, non-floating window to use as the diff content area.
local function find_content_win()
  local panel_win = require("nit.panel").get_winnr()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= panel_win and vim.api.nvim_win_get_config(w).relative == "" then
      return w
    end
  end
end

-- Compute and apply diff highlights between two buffers.
-- Returns a sorted list of { head_start, head_end } hunk records.
local function apply_diff_highlights(base_buf, head_buf)
  vim.api.nvim_buf_clear_namespace(base_buf, DIFF_NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(head_buf, DIFF_NS, 0, -1)

  local base_lines = vim.api.nvim_buf_get_lines(base_buf, 0, -1, false)
  local head_lines = vim.api.nvim_buf_get_lines(head_buf, 0, -1, false)
  local base_text  = #base_lines > 0 and (table.concat(base_lines, "\n") .. "\n") or ""
  local head_text  = #head_lines > 0 and (table.concat(head_lines, "\n") .. "\n") or ""

  local ok, hunks = pcall(vim.diff, base_text, head_text, {
    algorithm   = "myers",
    result_type = "indices",
  })
  if not ok or not hunks then return {} end

  local hunk_list = {}

  for _, h in ipairs(hunks) do
    local bs, bc, hs, hc = h[1], h[2], h[3], h[4]

    -- Base-side highlight
    if bc > 0 then
      local hl = hc > 0 and "NitDiffChange" or "NitDiffDelete"
      for i = 0, bc - 1 do
        vim.api.nvim_buf_set_extmark(base_buf, DIFF_NS, bs - 1 + i, 0, { line_hl_group = hl })
      end
    end

    -- Head-side highlight
    if hc > 0 then
      local hl = bc > 0 and "NitDiffChange" or "NitDiffAdd"
      for i = 0, hc - 1 do
        vim.api.nvim_buf_set_extmark(head_buf, DIFF_NS, hs - 1 + i, 0, { line_hl_group = hl })
      end
      table.insert(hunk_list, { head_start = hs, head_end = hs + hc - 1 })
    else
      -- Pure deletion: record the adjacent head line so ]c / [c still moves there.
      table.insert(hunk_list, { head_start = math.max(hs, 1), head_end = math.max(hs, 1) })
    end
  end

  return hunk_list
end

local function close_diff()
  for _, w in ipairs({ state.base_win, state.head_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(function()
        vim.wo[w].scrollbind = false
        vim.wo[w].cursorbind = false
      end)
    end
  end
  if state.base_win and vim.api.nvim_win_is_valid(state.base_win) then
    vim.api.nvim_win_close(state.base_win, true)
  end
  state.base_win = nil
  state.head_win = nil
  state.hunks    = {}
end

local function setup_diff(base_buf, file)
  local session = require("nit.session")

  -- Tear down previous base_win; reset head_win options but keep it open.
  if state.base_win and vim.api.nvim_win_is_valid(state.base_win) then
    pcall(function() vim.wo[state.base_win].scrollbind = false end)
    pcall(function() vim.wo[state.base_win].cursorbind = false end)
    vim.api.nvim_win_close(state.base_win, true)
    state.base_win = nil
  end
  if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
    pcall(function() vim.wo[state.head_win].scrollbind = false end)
    pcall(function() vim.wo[state.head_win].cursorbind = false end)
  end

  -- Locate or create the content window (right of the panel).
  if not state.head_win or not vim.api.nvim_win_is_valid(state.head_win) then
    local cw = find_content_win()
    if cw then
      state.head_win = cw
    else
      vim.cmd("vsplit")
      state.head_win = vim.api.nvim_get_current_win()
    end
  end

  -- Load the file (or an empty placeholder for deleted files) into head_win.
  vim.api.nvim_set_current_win(state.head_win)
  if file.status == "deleted" then
    local del_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[del_buf].buftype   = "nofile"
    vim.bo[del_buf].modifiable = false
    vim.api.nvim_buf_set_name(del_buf, "[deleted] " .. file.path)
    vim.api.nvim_win_set_buf(state.head_win, del_buf)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(file.path))
    state.head_win = vim.api.nvim_get_current_win()
  end
  local head_buf = vim.api.nvim_win_get_buf(state.head_win)

  -- Split left of head_win for the base version.
  vim.cmd("leftabove vsplit")
  state.base_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.base_win, base_buf)
  vim.wo[state.base_win].statusline = " [base] " .. file.path
  vim.bo[base_buf].modifiable = false

  -- Apply diff highlights (no diff=true — avoids E96 with cursor-animation plugins).
  state.hunks = apply_diff_highlights(base_buf, head_buf)

  -- Sync scrolling when base has content; skip for added files (empty base).
  if vim.api.nvim_buf_line_count(base_buf) > 0 then
    vim.wo[state.base_win].scrollbind = true
    vim.wo[state.head_win].scrollbind = true
    vim.wo[state.base_win].cursorbind = true
    vim.wo[state.head_win].cursorbind = true
    vim.cmd("syncbind")
  end

  vim.api.nvim_set_current_win(state.head_win)
  session.mark_viewed(file.path)
  require("nit.keymaps").setup_diff_buf(head_buf, file.path)
  require("nit.extmarks").render_for_file(file.path, head_buf)
  require("nit.panel").refresh()

  -- Clean up when base_win is closed.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.base_win),
    once    = true,
    callback = function()
      if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
        pcall(function() vim.wo[state.head_win].scrollbind = false end)
        pcall(function() vim.wo[state.head_win].cursorbind = false end)
      end
      state.base_win = nil
      state.head_win = nil
      state.hunks    = {}
    end,
  })
end

---@param file NitFile
function M.open_for_file(file)
  local session = require("nit.session")
  local git     = require("nit.git")

  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end

  local s = session.get()
  if not s.merge_base then
    vim.notify("nit: merge base not yet computed, please wait…", vim.log.levels.WARN)
    return
  end

  -- If this file is already showing, just focus head_win.
  if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
    local cur = require("nit.util").relative_buf_path(
      vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(state.head_win))
    )
    if cur == file.path then
      vim.api.nvim_set_current_win(state.head_win)
      return
    end
  end

  -- Added files: diff against an empty buffer.
  if file.status == "added" then
    local base_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[base_buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(base_buf, "[base] " .. file.path)
    vim.schedule(function() setup_diff(base_buf, file) end)
    return
  end

  -- Deleted or modified/renamed: fetch base content from git.
  git.show(s.merge_base, file.path, function(base_lines)
    local base_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, base_lines)
    local ft = vim.filetype.match({ filename = file.path }) or ""
    vim.bo[base_buf].filetype = ft
    vim.bo[base_buf].buftype  = "nofile"
    vim.api.nvim_buf_set_name(base_buf, "[base] " .. file.path)
    vim.schedule(function() setup_diff(base_buf, file) end)
  end)
end

-- Jump to the next diff hunk in head_win.
function M.next_hunk()
  if #state.hunks == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  for _, h in ipairs(state.hunks) do
    if h.head_start > cur then
      vim.api.nvim_win_set_cursor(0, { h.head_start, 0 })
      return
    end
  end
  vim.api.nvim_win_set_cursor(0, { state.hunks[1].head_start, 0 })
end

-- Jump to the previous diff hunk in head_win.
function M.prev_hunk()
  if #state.hunks == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  for i = #state.hunks, 1, -1 do
    if state.hunks[i].head_start < cur then
      vim.api.nvim_win_set_cursor(0, { state.hunks[i].head_start, 0 })
      return
    end
  end
  vim.api.nvim_win_set_cursor(0, { state.hunks[#state.hunks].head_start, 0 })
end

function M.close()
  close_diff()
end

return M
