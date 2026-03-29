local M = {}

local _setup_done = false

-- Define highlight groups used by nit.nvim.
local function setup_highlights()
  local function hl(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hl("NitSign",        { fg = "#61afef", default = true })
  hl("NitAuthor",      { fg = "#c678dd", bold = true, default = true })
  hl("NitBody",        { fg = "#abb2bf", default = true })
  hl("NitMeta",        { fg = "#5c6370", italic = true, default = true })
  hl("NitThreadBorder",{ fg = "#3e4451", default = true })
  hl("NitThreadLine",  { fg = "#abb2bf", default = true })
  hl("NitCommentBadge",{ fg = "#61afef", default = true })
  hl("NitViewedFile",  { fg = "#5c6370", default = true })
  -- Collapsed inline comment indicator (pill with background)
  hl("NitInlineIcon",  { fg = "#61afef", bg = "#2c313a", default = true })
  hl("NitInlineAuthor",{ fg = "#c678dd", bg = "#2c313a", bold = true, default = true })
  hl("NitInlineBody",  { fg = "#abb2bf", bg = "#2c313a", default = true })
  hl("NitInlineMeta",  { fg = "#5c6370", bg = "#2c313a", italic = true, default = true })
  hl("NitViewHeader",    { fg = "#61afef", bold = true, default = true })
  hl("NitViewSubheader", { fg = "#5c6370", italic = true, default = true })
end

-- Set up an autocmd that attaches keymaps + extmarks when a diff buffer
-- belonging to the current review session is entered.
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("NitSession", { clear = true })

  -- Re-apply highlights on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = setup_highlights,
  })

  -- When any buffer window is entered, check if it's a session file
  -- and attach diff-buffer keymaps + extmarks if not already done.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      local session = require("nit.session")
      if not session.is_active() then return end

      local bufnr = ev.buf
      -- Skip non-file buffers
      if vim.bo[bufnr].buftype ~= "" then return end

      local name = require("nit.util").relative_buf_path(vim.api.nvim_buf_get_name(bufnr))
      if name == "" then return end

      local file = session.get_file_by_path(name)
      if not file then return end

      -- Avoid setting up keymaps multiple times on the same buffer
      local already_setup = vim.b[bufnr]._nit_setup
      if already_setup then
        -- Re-render extmarks and reapply any expanded threads
        require("nit.extmarks").render_and_reapply(file.path, bufnr)
        return
      end

      vim.b[bufnr]._nit_setup = true
      require("nit.keymaps").setup_diff_buf(bufnr, file.path)
      require("nit.extmarks").render_for_file(file.path, bufnr)
    end,
  })
end

-- Initialize nit.nvim.
---@param opts table?
function M.setup(opts)
  if _setup_done then return end
  _setup_done = true

  require("nit.config").setup(opts)
  setup_highlights()
  setup_autocmds()
  require("nit.keymaps").setup_global()
end

-- Open the PR picker.
function M.open_pr_picker()
  require("nit.picker").open()
end

-- Toggle the file panel (open if closed, close if open).
function M.toggle_panel()
  require("nit.panel").toggle()
end

-- Start a review — subsequent comments are staged locally until submit.
function M.start_review()
  local session = require("nit.session")
  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end
  session.start_review()
  vim.notify("nit: review started — comments will be staged until you submit")
end

-- Submit a review with a chosen event type, posting all staged comments.
function M.submit_review()
  local session = require("nit.session")
  local gh = require("nit.gh")

  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end

  local s = session.get()
  local pending = session.get_pending_comments()
  local count = #pending

  local choices = {
    { label = "Comment",         event = "COMMENT" },
    { label = "Approve",         event = "APPROVE" },
    { label = "Request changes", event = "REQUEST_CHANGES" },
  }

  local prompt = count > 0
    and string.format("Submit review as: (%d comment%s pending)", count, count == 1 and "" or "s")
    or "Submit review as:"

  vim.ui.select(choices, {
    prompt = prompt,
    format_item = function(c) return c.label end,
  }, function(choice)
    if not choice then return end

    local form_title = count > 0
      and string.format(" %s (%d pending) ", choice.label, count)
      or string.format(" %s ", choice.label)
    require("nit.input").open({
      mode = "comment",
      line = 0,
      title = form_title,
      allow_empty = choice.event == "APPROVE" or count > 0,
      on_submit = function(body)
        vim.notify("nit: submitting review…")
        gh.create_review(s.repo, s.pr_number, {
          commit_id = s.head_oid,
          body = body,
          event = choice.event,
          comments = pending,
        }, function(_, err)
          vim.schedule(function()
            if err then
              vim.notify("nit: review submission failed — " .. tostring(err), vim.log.levels.ERROR)
            else
              session.clear_pending_comments()
              vim.notify("nit: review submitted (" .. choice.label .. ")")
              require("nit.comments").fetch(function()
                local extmarks = require("nit.extmarks")
                local util = require("nit.util")
                for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                  if vim.api.nvim_buf_is_valid(bufnr) then
                    local name = util.relative_buf_path(vim.api.nvim_buf_get_name(bufnr))
                    local file = session.get_file_by_path(name)
                    if file then
                      extmarks.render_and_reapply(file.path, bufnr)
                    end
                  end
                end
                local panel = require("nit.panel")
                if panel.is_open() then panel.refresh() end
              end)
            end
          end)
        end)
      end,
    })
  end)
end

-- Open the full PR view float.
function M.open_pr_view()
  require("nit.view").open()
end

return M
