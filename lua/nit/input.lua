local M = {}

local WIDTH = 72
local HEIGHT = 14

-- Open a floating comment/reply/suggestion input form.
--
-- opts:
--   mode: "comment" | "reply" | "suggestion"
--   line: number
--   start_line: number? (for multi-line)
--   reply_to_id: number? (for reply mode)
--   visual_lines: string[]? (for suggestion mode)
--   on_submit: fun(body: string)
function M.open(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  -- Pre-populate buffer for suggestion mode
  if opts.mode == "suggestion" and opts.visual_lines and #opts.visual_lines > 0 then
    local pre = { "" }
    table.insert(pre, "```suggestion")
    for _, l in ipairs(opts.visual_lines) do
      table.insert(pre, l)
    end
    table.insert(pre, "```")
    table.insert(pre, "")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, pre)
  end

  local title
  if opts.mode == "reply" then
    title = " Reply to comment "
  elseif opts.mode == "suggestion" then
    title = " Suggest edit "
  else
    local range = opts.start_line and opts.start_line ~= opts.line
      and (" L" .. opts.start_line .. "–" .. opts.line)
      or (" L" .. (opts.line or "?"))
    title = " Comment on" .. range .. " "
  end

  local row = math.max(0, math.floor((vim.o.lines - HEIGHT) / 2))
  local col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = WIDTH,
    height = HEIGHT,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = " <C-s> submit · <Esc> cancel ",
    footer_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = vim.trim(table.concat(lines, "\n"))
    if body == "" then
      vim.notify("nit: comment body is empty", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_win_close(win, true)
    opts.on_submit(body)
  end

  local function cancel()
    vim.api.nvim_win_close(win, true)
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, silent = true })

  -- Place cursor at top of buffer and enter insert mode
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("startinsert")
end

return M
