local M = {}

local state = {
  bufnr    = nil,
  winnr    = nil,
  line_map = {},  -- [1-based row] = { type, id, path? }
}

-- Compute float dimensions: 90% of editor size, centered.
local function float_dims()
  local w   = math.floor(vim.o.columns * 0.9)
  local h   = math.floor((vim.o.lines - 2) * 0.9)
  local row = math.floor((vim.o.lines - h) / 2)
  local col = math.floor((vim.o.columns - w) / 2)
  return w, h, row, col
end

function M.is_open()
  return state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr)
end

function M.close()
  if not M.is_open() then return end
  vim.api.nvim_win_close(state.winnr, true)
  state.winnr    = nil
  state.bufnr    = nil
  state.line_map = {}
end

-- Write lines to the buffer (handles modifiable toggle).
local function set_content(lines)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
end

-- Apply a list of highlight specs to the view buffer.
-- Each spec: { group, lnum (0-based), col_start, col_end }
local function apply_highlights(hls)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  local ns = vim.api.nvim_create_namespace("nit_view")
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(state.bufnr, ns, hl.group, hl.lnum, hl.col_start, hl.col_end)
  end
end

function M.open()
  local session = require("nit.session")
  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end

  -- If already open, focus it.
  if M.is_open() then
    vim.api.nvim_set_current_win(state.winnr)
    return
  end

  local w, h, row, col = float_dims()

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype  = "nit-view"
  vim.bo[state.bufnr].buftype   = "nofile"
  vim.bo[state.bufnr].swapfile  = false
  vim.bo[state.bufnr].bufhidden = "wipe"

  local s = session.get()
  state.winnr = vim.api.nvim_open_win(state.bufnr, true, {
    relative = "editor",
    width    = w,
    height   = h,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = string.format(" PR #%d — %s ", s.pr_number, s.repo),
    title_pos = "center",
    footer    = " r reply · c comment · R refresh · gf open diff · q close ",
    footer_pos = "center",
  })

  vim.wo[state.winnr].wrap         = true
  vim.wo[state.winnr].linebreak    = true
  vim.wo[state.winnr].number       = false
  vim.wo[state.winnr].relativenumber = false
  vim.wo[state.winnr].signcolumn   = "no"
  vim.wo[state.winnr].cursorline   = true

  set_content({ "", "  Loading…", "" })

  -- Clean up state when the window is closed externally.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(state.winnr),
    once     = true,
    callback = function()
      state.winnr    = nil
      state.bufnr    = nil
      state.line_map = {}
    end,
  })
end

return M
