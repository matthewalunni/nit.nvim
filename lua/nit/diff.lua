local M = {}

-- Track diff tabs opened by nit: tab_id → path
local diff_tabs = {}

-- Open a two-buffer native vim diff for a file.
-- Left: base version (merge_base:path) — read-only scratch buffer
-- Right: HEAD version (actual file on disk) — editable
---@param file NitFile
function M.open_for_file(file)
  local session = require("nit.session")
  local git = require("nit.git")

  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end

  local s = session.get()
  if not s.merge_base then
    vim.notify("nit: merge base not yet computed, please wait…", vim.log.levels.WARN)
    return
  end

  -- Handle new files (no base content)
  if file.status == "added" then
    -- For added files, just open the file and show it without a diff
    vim.cmd("tabnew " .. vim.fn.fnameescape(file.path))
    local head_buf = vim.api.nvim_get_current_buf()
    local tab_id = vim.api.nvim_get_current_tabpage()
    diff_tabs[tab_id] = file.path
    session.mark_viewed(file.path)
    require("nit.keymaps").setup_diff_buf(head_buf, file.path)
    require("nit.extmarks").render_for_file(file.path, head_buf)
    require("nit.panel").refresh()
    return
  end

  -- Handle deleted files (no head content)
  if file.status == "deleted" then
    git.show(s.merge_base, file.path, function(base_lines)
      vim.schedule(function()
        local base_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, base_lines)
        local ft = vim.filetype.match({ filename = file.path }) or ""
        vim.bo[base_buf].filetype = ft
        vim.bo[base_buf].modifiable = false
        vim.bo[base_buf].buftype = "nofile"
        vim.api.nvim_buf_set_name(base_buf, "[base] " .. file.path)

        vim.cmd("tabnew")
        local tab_id = vim.api.nvim_get_current_tabpage()
        diff_tabs[tab_id] = file.path
        vim.api.nvim_win_set_buf(0, base_buf)
        vim.wo[0].diff = true
        vim.wo[0].statusline = " [deleted] " .. file.path

        session.mark_viewed(file.path)
        require("nit.panel").refresh()
      end)
    end)
    return
  end

  -- Modified/renamed: show base on left, HEAD on right
  git.show(s.merge_base, file.path, function(base_lines)
    vim.schedule(function()
      -- Create base buffer
      local base_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, base_lines)
      local ft = vim.filetype.match({ filename = file.path }) or ""
      vim.bo[base_buf].filetype = ft
      vim.bo[base_buf].modifiable = false
      vim.bo[base_buf].buftype = "nofile"
      vim.api.nvim_buf_set_name(base_buf, "[base] " .. file.path)

      -- Open HEAD file in a new tab
      vim.cmd("tabnew " .. vim.fn.fnameescape(file.path))
      local tab_id = vim.api.nvim_get_current_tabpage()
      diff_tabs[tab_id] = file.path
      local head_win = vim.api.nvim_get_current_win()
      local head_buf = vim.api.nvim_get_current_buf()

      -- Open left split for base
      vim.cmd("leftabove vsplit")
      local base_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(base_win, base_buf)
      vim.wo[base_win].statusline = " [base] " .. file.path

      -- Enable diff mode on both windows
      vim.wo[base_win].diff = true
      vim.wo[head_win].diff = true

      -- Sync scrolling
      vim.wo[base_win].scrollbind = true
      vim.wo[head_win].scrollbind = true
      vim.wo[base_win].cursorbind = true
      vim.wo[head_win].cursorbind = true

      -- Focus the editable (HEAD) side
      vim.api.nvim_set_current_win(head_win)

      -- Set up diff buffer keymaps and render inline comments
      session.mark_viewed(file.path)
      require("nit.keymaps").setup_diff_buf(head_buf, file.path)
      require("nit.extmarks").render_for_file(file.path, head_buf)
      require("nit.panel").refresh()

      -- Close diff mode when tab is closed
      vim.api.nvim_create_autocmd("TabClosed", {
        once = true,
        callback = function(ev)
          -- Try to clean up diff_tabs entry
          for tid in pairs(diff_tabs) do
            if not vim.api.nvim_tabpage_is_valid(tid) then
              diff_tabs[tid] = nil
            end
          end
        end,
      })
    end)
  end)
end

-- Close the current nit diff tab (if any).
function M.close()
  local tab_id = vim.api.nvim_get_current_tabpage()
  if diff_tabs[tab_id] then
    diff_tabs[tab_id] = nil
    vim.cmd("tabclose")
  end
end

return M
