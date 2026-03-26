local M = {}

local function get_deps()
  return {
    gh = require("nit.gh"),
    git = require("nit.git"),
    session = require("nit.session"),
    config = require("nit.config"),
  }
end

local function fetch_comments_bg(pr)
  require("nit.comments").fetch(function()
    -- Refresh panel once comments are loaded (updates count badges)
    local panel = require("nit.panel")
    if panel.is_open() then
      vim.schedule(function() panel.refresh() end)
    end
  end)
end

local function on_pr_selected(pr)
  local d = get_deps()
  vim.notify("nit: checking out PR #" .. pr.number .. " (" .. pr.headRefName .. ")…")

  d.gh.checkout(pr.number, function(_, code)
    if code ~= 0 then
      vim.schedule(function()
        vim.notify("nit: checkout failed", vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      d.session.init(pr)

      -- Track readiness: need both files + merge_base before opening panel
      local ready = { files = false, merge_base = false }
      local function maybe_open()
        if not (ready.files and ready.merge_base) then return end
        if d.config.get("auto_open_panel") then
          require("nit.panel").open()
        end
        if d.config.get("auto_fetch_comments") then
          fetch_comments_bg(pr)
        end
      end

      -- Fetch changed files
      d.gh.pr_files(pr.number, function(files, err)
        vim.schedule(function()
          if err then
            vim.notify("nit: failed to get PR files: " .. err, vim.log.levels.WARN)
          else
            d.session.set_files(files or {})
          end
          ready.files = true
          maybe_open()
        end)
      end)

      -- Compute merge base
      d.git.merge_base(pr.baseRefName, function(sha, err)
        vim.schedule(function()
          if err then
            vim.notify("nit: failed to get merge base: " .. err, vim.log.levels.WARN)
          else
            d.session.get().merge_base = sha
          end
          ready.merge_base = true
          maybe_open()
        end)
      end)
    end)
  end)
end

function M.open()
  local d = get_deps()
  vim.notify("nit: loading PRs…")

  d.gh.list_prs(function(prs, err)
    vim.schedule(function()
      if err then
        vim.notify("nit: failed to list PRs: " .. err, vim.log.levels.ERROR)
        return
      end
      if not prs or #prs == 0 then
        vim.notify("nit: no open PRs found")
        return
      end

      vim.ui.select(prs, {
        prompt = "Select PR to review",
        format_item = function(pr)
          local draft = pr.isDraft and " [draft]" or ""
          return string.format("#%-4d %s%s  (%s → %s)",
            pr.number, pr.title, draft, pr.headRefName, pr.baseRefName)
        end,
      }, function(pr)
        if not pr then return end
        on_pr_selected(pr)
      end)
    end)
  end)
end

return M
