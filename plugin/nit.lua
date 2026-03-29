-- nit.nvim plugin entrypoint
-- This file is sourced by Neovim on startup (or by lazy.nvim on demand).
-- It registers the :Nit user command and calls setup() with defaults.

if vim.g.loaded_nit then return end
vim.g.loaded_nit = true

-- Register :Nit command with subcommands
vim.api.nvim_create_user_command("Nit", function(args)
  local fargs = args.fargs
  local sub = fargs[1] or ""
  -- Accept a bare PR number: :Nit 1  →  treated as :Nit pr 1
  local pr_number = tonumber(sub) and tonumber(sub) or (fargs[2] and tonumber(fargs[2]) or nil)
  if tonumber(sub) then sub = "pr" end

  local nit = require("nit")

  if sub == "pr" or sub == "" then
    nit.open_pr_picker(pr_number)
  elseif sub == "panel" then
    nit.toggle_panel(pr_number)
  elseif sub == "review" or sub == "start" then
    nit.start_review(pr_number)
  elseif sub == "submit" then
    nit.submit_review()
  elseif sub == "view" then
    nit.open_pr_view(pr_number)
  else
    vim.notify("nit: unknown subcommand '" .. sub .. "'. Use: pr, panel, start, submit, review, view", vim.log.levels.WARN)
  end
end, {
  nargs = "*",
  complete = function()
    return { "pr", "panel", "start", "review", "submit", "view" }
  end,
  desc = "nit.nvim — GitHub PR review",
})
