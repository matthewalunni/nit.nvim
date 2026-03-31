local M = {}

-- Build the shell command from the configured tool and prompt.
-- tool may be a string ("claude") or a table ({ "claude", "--model", "sonnet" }).
-- The prompt is always appended as the final argument.
local function build_cmd(tool, prompt)
  if type(tool) == "table" then
    local cmd = vim.deepcopy(tool)
    table.insert(cmd, prompt)
    return cmd
  end
  return { tool, prompt }
end

-- Build the prompt string from selected lines and buffer filetype.
local function build_prompt(lines, filetype)
  local ft = (filetype and filetype ~= "") and filetype or "text"
  local code = table.concat(lines, "\n")
  return "Review this code:\n\n```" .. ft .. "\n" .. code .. "\n```"
end

-- Send the visual selection in bufnr to the configured AI tool.
-- Called from keymaps after exiting visual mode so '< '> marks are set.
function M.review_selection(bufnr)
  local config = require("nit.config")
  local ai_cfg = config.get("ai") or {}
  local tool = ai_cfg.tool or "claude"
  local keep_open = ai_cfg.keep_open or false

  local s = vim.api.nvim_buf_get_mark(bufnr, "<")[1]
  local e = vim.api.nvim_buf_get_mark(bufnr, ">")[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)

  if #lines == 0 then
    vim.notify("nit: no lines selected", vim.log.levels.WARN)
    return
  end

  local ft = vim.bo[bufnr].filetype
  local prompt = build_prompt(lines, ft)
  local cmd = build_cmd(tool, prompt)

  -- Open a 20-line horizontal split at the bottom and launch the AI TUI.
  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(win, 20)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  local job_id = vim.api.nvim_buf_call(buf, function()
    return vim.fn.termopen(cmd, {
      on_exit = function()
        if keep_open then return end
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end)
      end,
    })
  end)
  if job_id < 1 then
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    vim.notify("nit: failed to launch AI tool — is '" .. tostring(type(tool) == "table" and tool[1] or tool) .. "' installed?", vim.log.levels.ERROR)
    return
  end
  vim.cmd("startinsert")
end

return M
