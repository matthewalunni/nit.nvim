local M = {}

local defaults = {
  panel_width = 40,
  auto_open_panel = true,
  auto_fetch_comments = true,
  comment_cache_ttl = 120, -- seconds
  icons = {
    added = " ",
    modified = " ",
    deleted = " ",
    renamed = " ",
    comment = " ",
  },
  keys = {
    open_pr_picker = "<leader>grp",
    toggle_panel = "<leader>grf",
    start_review = "<leader>grs",
    submit_review = "<leader>grS",
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get(key)
  return M.options[key]
end

return M
