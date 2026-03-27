local M = {}

local state = {
  bufnr = nil,
  winnr = nil,
}

local function is_valid_win()
  return state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr)
end

function M.is_open()
  return is_valid_win()
end

function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.winnr)
    return
  end

  local config = require("nit.config")
  local session = require("nit.session")

  -- Create scratch buffer
  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype = "nit-panel"
  vim.bo[state.bufnr].buftype = "nofile"
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].bufhidden = "hide"

  -- Open left vertical split
  local width = config.get("panel_width")
  vim.cmd("topleft " .. width .. "vsplit")
  state.winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winnr, state.bufnr)

  -- Window appearance
  vim.wo[state.winnr].number = false
  vim.wo[state.winnr].relativenumber = false
  vim.wo[state.winnr].signcolumn = "no"
  vim.wo[state.winnr].wrap = false
  vim.wo[state.winnr].cursorline = true
  vim.wo[state.winnr].winfixwidth = true

  -- Set window title via statusline
  vim.wo[state.winnr].statusline = " PR #" .. (session.is_active() and session.get().pr_number or "?") .. " — Changed Files"

  M.refresh()
  require("nit.keymaps").setup_panel_buf(state.bufnr)

  -- Clean up state when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.winnr),
    once = true,
    callback = function()
      state.winnr = nil
      state.bufnr = nil
    end,
  })
end

function M.close()
  if not is_valid_win() then return end
  vim.api.nvim_win_close(state.winnr, true)
  state.winnr = nil
  state.bufnr = nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.get_winnr()
  return is_valid_win() and state.winnr or nil
end

function M.focus()
  if is_valid_win() then
    vim.api.nvim_set_current_win(state.winnr)
  end
end

function M.refresh()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end

  local session = require("nit.session")
  local config = require("nit.config")
  local icons = config.get("icons")

  local files = session.is_active() and (session.get().files or {}) or {}
  local lines = {}
  local hls = {} -- { {lnum, col_start, col_end, hl_group} }

  for i, f in ipairs(files) do
    local icon = icons[f.status] or " "
    local count = session.comment_count_for(f.path)
    local badge = count > 0 and ("  " .. icons.comment .. count) or ""
    local viewed_prefix = f.viewed and "  " or "  "
    local line_text = viewed_prefix .. icon .. " " .. f.path .. badge

    table.insert(lines, line_text)

    -- Track highlight positions (for colorizing)
    if count > 0 then
      table.insert(hls, {
        lnum = i - 1,
        col_start = #viewed_prefix + #icon + 1 + #f.path + 1,
        col_end = -1,
        hl = "NitCommentBadge",
      })
    end
    if f.viewed then
      table.insert(hls, { lnum = i - 1, col_start = 0, col_end = -1, hl = "NitViewedFile" })
    end
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("nit_panel")
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(state.bufnr, ns, hl.hl, hl.lnum, hl.col_start, hl.col_end)
  end

  -- Update header
  if is_valid_win() and session.is_active() then
    vim.wo[state.winnr].statusline =
      " PR #" .. session.get().pr_number .. " — Changed Files (" .. #files .. ")"
  end
end

-- Return the NitFile under the cursor in the panel.
---@return NitFile|nil
function M.get_selected_file()
  if not is_valid_win() then return nil end
  local session = require("nit.session")
  if not session.is_active() then return nil end
  local row = vim.api.nvim_win_get_cursor(state.winnr)[1]
  local files = session.get().files or {}
  return files[row]
end

return M
