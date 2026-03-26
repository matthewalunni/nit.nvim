-- nit.nvim plugin entrypoint
-- This file is sourced by Neovim on startup (or by lazy.nvim on demand).
-- It registers the :Nit user command and calls setup() with defaults.

if vim.g.loaded_nit then return end
vim.g.loaded_nit = true

-- Register :Nit command with subcommands
vim.api.nvim_create_user_command("Nit", function(args)
  local sub = args.args
  local nit = require("nit")

  if sub == "pr" or sub == "" then
    nit.open_pr_picker()
  elseif sub == "panel" then
    nit.toggle_panel()
  elseif sub == "review" then
    nit.start_review()
  elseif sub == "submit" then
    nit.submit_review()
  else
    vim.notify("nit: unknown subcommand '" .. sub .. "'. Use: pr, panel, review, submit", vim.log.levels.WARN)
  end
end, {
  nargs = "?",
  complete = function()
    return { "pr", "panel", "review", "submit" }
  end,
  desc = "nit.nvim — GitHub PR review",
})
