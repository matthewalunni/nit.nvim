local M = {}

-- After a comment is posted: invalidate cache, re-fetch, re-render.
local function after_comment(err)
  if err then
    vim.schedule(function()
      vim.notify("nit: comment failed — " .. tostring(err), vim.log.levels.ERROR)
    end)
    return
  end
  vim.schedule(function()
    vim.notify("nit: comment posted")
    require("nit.comments").fetch(function()
      -- Re-render extmarks in all session diff buffers
      local session = require("nit.session")
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
  end)
end

-- Open the comment form and route submission to gh API.
local function open_comment_form(form_opts)
  local session = require("nit.session")
  local gh = require("nit.gh")
  if not session.is_active() then return end
  local s = session.get()

  require("nit.input").open(vim.tbl_extend("keep", form_opts, {
    on_submit = function(body)
      if session.is_review_active() and not form_opts.reply_to_id then
        local c = {
          path = form_opts.path,
          side = "RIGHT",
          line = form_opts.line,
          body = body,
        }
        if form_opts.start_line and form_opts.start_line ~= form_opts.line then
          c.start_line = form_opts.start_line
          c.start_side = "RIGHT"
        end
        session.add_pending_comment(c)
        local count = #session.get_pending_comments()
        vim.notify("nit: comment staged (" .. count .. " pending)")
      else
        if form_opts.reply_to_id then
          gh.reply_comment(s.repo, s.pr_number, form_opts.reply_to_id, body,
            function(_, err) after_comment(err) end)
        else
          gh.post_comment(s.repo, s.pr_number, {
            commit_id  = s.head_oid,
            path       = form_opts.path,
            side       = "RIGHT",
            line       = form_opts.line,
            start_line = form_opts.start_line,
            body       = body,
          }, function(_, err) after_comment(err) end)
        end
      end
    end,
  }))
end

-- Register global keymaps (called once from nit.setup).
function M.setup_global()
  local config = require("nit.config")
  local keys = config.get("keys")
  local nit = require("nit")
  local map = vim.keymap.set

  map("n", keys.open_pr_picker, nit.open_pr_picker, { desc = "Review: Open PR picker" })
  map("n", keys.toggle_panel,   nit.toggle_panel,   { desc = "Review: Toggle file panel" })
  map("n", keys.start_review,   nit.start_review,   { desc = "Review: Start review" })
  map("n", keys.submit_review,  nit.submit_review,  { desc = "Review: Submit review" })
  map("n", keys.open_pr_view,   nit.open_pr_view,   { desc = "Review: Open PR view" })
end

-- Register buffer-local keymaps for the nit-panel buffer.
function M.setup_panel_buf(bufnr)
  local o = { buffer = bufnr, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", function()
    local file = require("nit.panel").get_selected_file()
    if file then require("nit.diff").open_for_file(file) end
  end, vim.tbl_extend("force", o, { desc = "Open diff" }))

  vim.keymap.set("n", "R", function()
    require("nit.comments").fetch(function()
      require("nit.panel").refresh()
    end)
  end, vim.tbl_extend("force", o, { desc = "Refresh" }))

  vim.keymap.set("n", "q", function()
    require("nit.panel").close()
  end, vim.tbl_extend("force", o, { desc = "Close panel" }))

  vim.keymap.set("n", "]f", function()
    local panel = require("nit.panel")
    local files = require("nit.session").get().files or {}
    if #files == 0 then return end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local next_row = (row % #files) + 1
    vim.api.nvim_win_set_cursor(0, { next_row, 0 })
  end, vim.tbl_extend("force", o, { desc = "Next file" }))

  vim.keymap.set("n", "[f", function()
    local files = require("nit.session").get().files or {}
    if #files == 0 then return end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local prev_row = ((row - 2 + #files) % #files) + 1
    vim.api.nvim_win_set_cursor(0, { prev_row, 0 })
  end, vim.tbl_extend("force", o, { desc = "Previous file" }))
end

-- Register buffer-local keymaps for a diff buffer (right/HEAD side).
---@param bufnr integer
---@param path string  relative path of the file
function M.setup_diff_buf(bufnr, path)
  local o = { buffer = bufnr, silent = true }

  -- Comment on current line (normal mode)
  vim.keymap.set("n", "<leader>grc", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    open_comment_form({ mode = "comment", line = line, path = path })
  end, vim.tbl_extend("force", o, { desc = "Add review comment" }))

  -- Comment on visual selection
  vim.keymap.set("v", "<leader>grc", function()
    -- Exit visual mode first so '< '> marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    local s = vim.fn.line("'<")
    local e = vim.fn.line("'>")
    open_comment_form({ mode = "comment", line = e, start_line = s ~= e and s or nil, path = path })
  end, vim.tbl_extend("force", o, { desc = "Add review comment (selection)" }))

  -- Suggest edit from visual selection
  vim.keymap.set("v", "<leader>grg", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    local s = vim.fn.line("'<")
    local e = vim.fn.line("'>")
    local sel_lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
    open_comment_form({
      mode = "suggestion",
      line = e,
      start_line = s ~= e and s or nil,
      path = path,
      visual_lines = sel_lines,
    })
  end, vim.tbl_extend("force", o, { desc = "Suggest edit" }))

  -- Reply to thread at cursor
  vim.keymap.set("n", "<leader>grr", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local threads = require("nit.extmarks").threads_at(path, line)
    if #threads == 0 then
      vim.notify("nit: no comment thread at this line", vim.log.levels.INFO)
      return
    end
    local function reply_to(thread)
      open_comment_form({
        mode = "reply",
        line = line,
        path = path,
        reply_to_id = thread.id,
      })
    end
    if #threads == 1 then
      reply_to(threads[1])
    else
      vim.ui.select(threads, {
        prompt = "Reply to thread:",
        format_item = function(t)
          local last = (t.replies and #t.replies > 0) and t.replies[#t.replies] or t
          local preview = vim.fn.strcharpart(last.body, 0, 50)
          if vim.fn.strcharlen(last.body) > 50 then preview = preview .. "…" end
          return "@" .. last.author .. ": " .. preview
        end,
      }, function(choice)
        if choice then reply_to(choice) end
      end)
    end
  end, vim.tbl_extend("force", o, { desc = "Reply to comment thread" }))

  -- Toggle thread expand/collapse
  vim.keymap.set("n", "<leader>grx", function()
    require("nit.extmarks").toggle_thread_at_cursor(bufnr, path)
  end, vim.tbl_extend("force", o, { desc = "Toggle comment thread" }))

  -- Navigate to next/prev comment
  vim.keymap.set("n", "]r", function()
    require("nit.extmarks").next_comment(bufnr, path)
  end, vim.tbl_extend("force", o, { desc = "Next review comment" }))

  vim.keymap.set("n", "[r", function()
    require("nit.extmarks").prev_comment(bufnr, path)
  end, vim.tbl_extend("force", o, { desc = "Previous review comment" }))

  vim.keymap.set("n", "]c", function()
    require("nit.diff").next_hunk()
  end, vim.tbl_extend("force", o, { desc = "Next diff hunk" }))

  vim.keymap.set("n", "[c", function()
    require("nit.diff").prev_hunk()
  end, vim.tbl_extend("force", o, { desc = "Previous diff hunk" }))
end

-- Register buffer-local keymaps for the nit-view float buffer.
function M.setup_view_buf(bufnr)
  local o = { buffer = bufnr, silent = true, nowait = true }

  -- Close the view
  vim.keymap.set("n", "q",   function() require("nit.view").close() end,
    vim.tbl_extend("force", o, { desc = "Close PR view" }))
  vim.keymap.set("n", "<Esc>", function() require("nit.view").close() end,
    vim.tbl_extend("force", o, { desc = "Close PR view" }))

  -- Refresh
  vim.keymap.set("n", "R", function() require("nit.view").refresh() end,
    vim.tbl_extend("force", o, { desc = "Refresh PR view" }))

  -- Reply to comment under cursor
  vim.keymap.set("n", "r", function()
    local view    = require("nit.view")
    local entry   = view.entry_at_cursor()
    if not entry then
      vim.notify("nit: no comment at cursor", vim.log.levels.INFO)
      return
    end
    local session = require("nit.session")
    local gh      = require("nit.gh")
    if not session.is_active() then return end
    local s = session.get()

    require("nit.input").open({
      mode  = "reply",
      line  = 0,
      title = " Reply ",
      on_submit = function(body)
        if entry.type == "inline" then
          gh.reply_comment(s.repo, s.pr_number, entry.id, body,
            function(_, err) require("nit.view")._after_action(err) end)
        else
          -- For reviews and issue comments: post a new general PR comment
          gh.post_issue_comment(s.repo, s.pr_number, body,
            function(_, err) require("nit.view")._after_action(err) end)
        end
      end,
    })
  end, vim.tbl_extend("force", o, { desc = "Reply to comment" }))

  -- Post a new general PR comment
  vim.keymap.set("n", "c", function()
    local session = require("nit.session")
    local gh      = require("nit.gh")
    if not session.is_active() then return end
    local s = session.get()

    require("nit.input").open({
      mode  = "comment",
      line  = 0,
      title = " New PR Comment ",
      on_submit = function(body)
        gh.post_issue_comment(s.repo, s.pr_number, body,
          function(_, err) require("nit.view")._after_action(err) end)
      end,
    })
  end, vim.tbl_extend("force", o, { desc = "Post new PR comment" }))

  -- Jump to diff for inline thread under cursor
  vim.keymap.set("n", "gf", function()
    local view  = require("nit.view")
    local entry = view.entry_at_cursor()
    if not entry or entry.type ~= "inline" then return end
    local session = require("nit.session")
    if not session.is_active() then return end
    local file = session.get_file_by_path(entry.path)
    if not file then return end
    view.close()
    require("nit.diff").open_for_file(file)
  end, vim.tbl_extend("force", o, { desc = "Open diff for inline thread" }))
end

return M
