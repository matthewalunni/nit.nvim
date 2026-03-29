local M = {}

-- Optional render-markdown.nvim integration.
-- Cached once at module load: nil if not installed, module table if present.
local render_md = (function()
  local ok, m = pcall(require, "render-markdown")
  return ok and m or nil
end)()

-- Attach a markdown treesitter parser and enable render-markdown.nvim on
-- the given buffer. No-op when render-markdown is not installed.
local function maybe_enable_render_markdown(bufnr)
  if not render_md then return end
  pcall(vim.treesitter.start, bufnr, "markdown")
  pcall(render_md.enable, bufnr)
end

local state = {
  bufnr    = nil,
  winnr    = nil,
  line_map = {},  -- [1-based row] = { type, id, path? }
}

-- Compute float dimensions: 90% of editor size, centered.
local function float_dims()
  local w   = math.floor(vim.o.columns * 0.9)
  local h   = math.floor((vim.o.lines - 2) * 0.9)
  local row = math.floor((vim.o.lines - h) / 2)
  local col = math.floor((vim.o.columns - w) / 2)
  return w, h, row, col
end

function M.is_open()
  return state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr)
end

function M.close()
  if not M.is_open() then return end
  vim.api.nvim_win_close(state.winnr, true)
  state.winnr    = nil
  state.bufnr    = nil
  state.line_map = {}
end

-- Write lines to the buffer (handles modifiable toggle).
local function set_content(lines)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
end

-- Apply a list of highlight specs to the view buffer.
-- Each spec: { group, lnum (0-based), col_start, col_end }
local function apply_highlights(hls)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  local ns = vim.api.nvim_create_namespace("nit_view")
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(state.bufnr, ns, hl.group, hl.lnum, hl.col_start, hl.col_end)
  end
end

function M.open()
  local session = require("nit.session")
  if not session.is_active() then
    vim.notify("nit: no active review session", vim.log.levels.WARN)
    return
  end

  -- If already open, focus it.
  if M.is_open() then
    vim.api.nvim_set_current_win(state.winnr)
    return
  end

  local w, h, row, col = float_dims()

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype  = "nit-view"
  vim.bo[state.bufnr].buftype   = "nofile"
  vim.bo[state.bufnr].swapfile  = false
  vim.bo[state.bufnr].bufhidden = "wipe"

  local s = session.get()
  state.winnr = vim.api.nvim_open_win(state.bufnr, true, {
    relative = "editor",
    width    = w,
    height   = h,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = string.format(" PR #%d — %s ", s.pr_number, s.repo),
    title_pos = "center",
    footer    = " r reply · c comment · R refresh · gf open diff · q close ",
    footer_pos = "center",
  })

  vim.wo[state.winnr].wrap         = true
  vim.wo[state.winnr].linebreak    = true
  vim.wo[state.winnr].number       = false
  vim.wo[state.winnr].relativenumber = false
  vim.wo[state.winnr].signcolumn   = "no"
  vim.wo[state.winnr].cursorline   = true

  maybe_enable_render_markdown(state.bufnr)

  set_content({ "", "  Loading…", "" })
  require("nit.keymaps").setup_view_buf(state.bufnr)
  vim.schedule(function() M.refresh() end)

  -- Clean up state when the window is closed externally.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(state.winnr),
    once     = true,
    callback = function()
      state.winnr    = nil
      state.bufnr    = nil
      state.line_map = {}
    end,
  })
end

-- Format an ISO 8601 timestamp as a relative "Xm ago" / "Xh ago" / "Xd ago" string.
local function rel_time(iso_str)
  if not iso_str or iso_str == "" then return "" end
  local y, mo, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return iso_str end
  local t    = os.time({
    year  = tonumber(y), month = tonumber(mo), day  = tonumber(d),
    hour  = tonumber(h), min   = tonumber(mi), sec  = tonumber(s),
  })
  local diff = os.time() - t
  if diff < 60    then return "just now" end
  if diff < 3600  then return math.floor(diff / 60)    .. "m ago" end
  if diff < 86400 then return math.floor(diff / 3600)  .. "h ago" end
  return math.floor(diff / 86400) .. "d ago"
end

-- Format an ISO 8601 timestamp as "YYYY-MM-DD HH:MM".
local function fmt_datetime(iso_str)
  if not iso_str or iso_str == "" then return "" end
  local y, mo, d, h, mi = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then return "" end
  return string.format("%s-%s-%s %s:%s", y, mo, d, h, mi)
end

-- Word-wrap a string to fit within `width` columns.
-- Returns a list of strings (lines), each ≤ width characters.
local function wrap(text, width)
  local result = {}
  for _, raw_line in ipairs(vim.split(text, "\n", { plain = true })) do
    if vim.fn.strdisplaywidth(raw_line) <= width then
      table.insert(result, raw_line)
    else
      local current = ""
      for word in raw_line:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if vim.fn.strdisplaywidth(candidate) <= width then
          current = candidate
        else
          if current ~= "" then table.insert(result, current) end
          current = word
        end
      end
      if current ~= "" then table.insert(result, current) end
    end
  end
  return result
end

-- Build the full document from fetched data + session inline comments.
-- Returns lines (string[]), hls ({group,lnum,col_start,col_end}[]), line_map ([row]=entry).
local function build_document(data)
  local lines    = {}
  local hls      = {}
  local line_map = {}
  local w        = state.winnr and vim.api.nvim_win_get_width(state.winnr) or 80
  local indent   = "  "

  -- add(): append a line, optionally highlight the whole line, return its 0-based index.
  local function add(text, hl_group)
    local lnum = #lines
    table.insert(lines, text)
    if hl_group then
      table.insert(hls, { group = hl_group, lnum = lnum, col_start = 0, col_end = -1 })
    end
    return lnum
  end

  local function blank() table.insert(lines, "") end

  local function section_header(title)
    local fill = string.rep("━", math.max(0, w - vim.fn.strdisplaywidth(title) - 5))
    add("━━━ " .. title .. " " .. fill, "NitViewHeader")
  end

  -- ── PR Header ──────────────────────────────────────────────────────────
  local pr       = data.pr or {}
  local pr_num   = pr.number or require("nit.session").get().pr_number
  local pr_title = (type(pr.title) == "string") and pr.title or "(unknown)"
  section_header("PR #" .. pr_num .. ": " .. pr_title)

  if data.pr_err then
    add(indent .. "[Error loading PR details: " .. data.pr_err .. "]", "NitMeta")
  else
    local author    = (pr.user and pr.user.login) or "?"
    local pr_state  = pr.state or "?"
    local base_ref  = (pr.base and pr.base.ref) or "?"
    local head_ref  = (pr.head and pr.head.ref) or "?"

    -- Collect reviewer states for the header line
    local review_parts = {}
    for _, rev in ipairs(data.reviews or {}) do
      if rev.state == "APPROVED" then
        table.insert(review_parts, (rev.user and rev.user.login or "?") .. " ✓")
      elseif rev.state == "CHANGES_REQUESTED" then
        table.insert(review_parts, (rev.user and rev.user.login or "?") .. " ✗")
      end
    end
    local reviews_str = #review_parts > 0 and ("  " .. table.concat(review_parts, "  ")) or ""

    add(indent .. "@" .. author .. " · " .. pr_state .. " · " .. base_ref .. " ← " .. head_ref .. reviews_str, "NitMeta")
    blank()

    -- PR body (word-wrapped)
    local body = (type(pr.body) == "string") and pr.body or ""
    if body ~= "" then
      for _, line in ipairs(wrap(body, w - #indent)) do
        add(indent .. line, "NitBody")
      end
    else
      add(indent .. "(no description)", "NitMeta")
    end
  end

  blank()

  -- ── Commits ────────────────────────────────────────────────────────────
  local commits = data.commits or {}
  section_header("Commits (" .. #commits .. ")")

  if data.commits_err then
    add(indent .. "[Error loading commits: " .. data.commits_err .. "]", "NitMeta")
  elseif #commits == 0 then
    add(indent .. "(no commits)", "NitMeta")
  else
    for _, c in ipairs(commits) do
      local sha      = vim.fn.strcharpart(c.sha or "", 0, 7)
      local msg      = (c.commit and c.commit.message) or ""
      msg = vim.split(msg, "\n", { plain = true })[1] or ""
      local au       = (c.commit and c.commit.author and c.commit.author.name) or "?"
      local dt       = fmt_datetime((c.commit and c.commit.author and c.commit.author.date) or "")
      local dt_str   = dt ~= "" and ("  " .. dt) or ""
      -- Budget: w minus indent(2), sha(7), 2 spaces, 2 spaces, author, datetime suffix
      local budget   = w - 2 - 7 - 2 - 2 - vim.fn.strdisplaywidth(au) - vim.fn.strdisplaywidth(dt_str)
      if vim.fn.strdisplaywidth(msg) > budget then
        msg = vim.fn.strcharpart(msg, 0, math.max(0, budget - 1)) .. "…"
      end
      local pad = string.rep(" ", math.max(1, budget - vim.fn.strdisplaywidth(msg) + 1))
      add(indent .. sha .. "  " .. msg .. pad .. au .. dt_str, "NitBody")
    end
  end

  blank()

  -- ── Comments ───────────────────────────────────────────────────────────
  section_header("Comments")

  -- Build a single unified list of all comments sorted chronologically.
  local all_comments = {}

  -- PR-level reviews with non-empty body
  for _, rev in ipairs(data.reviews or {}) do
    if type(rev.body) == "string" and vim.trim(rev.body) ~= "" then
      table.insert(all_comments, {
        type       = "review",
        id         = rev.id,
        author     = (rev.user and rev.user.login) or "?",
        body       = rev.body,
        created_at = rev.submitted_at or "",
      })
    end
  end

  -- General issue/PR comments
  for _, ic in ipairs(data.issue_comments or {}) do
    if type(ic.body) == "string" and vim.trim(ic.body) ~= "" then
      table.insert(all_comments, {
        type       = "issue_comment",
        id         = ic.id,
        author     = (ic.user and ic.user.login) or "?",
        body       = ic.body,
        created_at = ic.created_at or "",
      })
    end
  end

  -- Inline threads from session
  local session  = require("nit.session")
  local by_path  = session.is_active() and (session.get().comments or {}) or {}
  for path, threads in pairs(by_path) do
    for _, thread in ipairs(threads) do
      table.insert(all_comments, {
        type       = "inline",
        id         = thread.id,
        path       = path,
        line       = thread.line,
        author     = thread.author,
        body       = thread.body,
        created_at = thread.created_at or "",
        replies    = thread.replies or {},
      })
    end
  end

  -- Sort everything chronologically by created_at.
  table.sort(all_comments, function(a, b) return a.created_at < b.created_at end)

  -- Error banners
  if data.reviews_err then
    add(indent .. "[Error loading reviews: " .. data.reviews_err .. "]", "NitMeta")
  end
  if data.issue_comments_err then
    add(indent .. "[Error loading issue comments: " .. data.issue_comments_err .. "]", "NitMeta")
  end

  -- Render unified comment list
  for _, c in ipairs(all_comments) do
    local dt      = fmt_datetime(c.created_at)
    local ts      = dt ~= "" and (" · " .. dt) or ""

    if c.type == "inline" then
      -- Inline thread: show file + line context in the header
      local meta_lnum = add(indent .. "@" .. c.author .. " · " .. c.path .. ":" .. c.line .. ts, "NitMeta")
      line_map[meta_lnum + 1] = { type = "inline", id = c.id, path = c.path }

      for _, line in ipairs(wrap(c.body, w - #indent)) do
        local lnum = add(indent .. line, "NitBody")
        line_map[lnum + 1] = { type = "inline", id = c.id, path = c.path }
      end

      for _, reply in ipairs(c.replies) do
        local preview  = vim.fn.strcharpart(reply.body, 0, 60)
        if vim.fn.strcharlen(reply.body) > 60 then preview = preview .. "…" end
        local reply_dt = fmt_datetime(reply.created_at or "")
        local reply_ts = reply_dt ~= "" and (reply_dt .. ": ") or ""
        local reply_line = indent .. "  └ @" .. reply.author .. " · " .. reply_ts .. preview
        local lnum = add(reply_line, "NitMeta")
        line_map[lnum + 1] = { type = "inline", id = c.id, path = c.path }
      end
    else
      local meta_lnum = add(indent .. "@" .. c.author .. ts, "NitMeta")
      line_map[meta_lnum + 1] = { type = c.type, id = c.id }

      for _, line in ipairs(wrap(c.body, w - #indent)) do
        local lnum = add(indent .. line, "NitBody")
        line_map[lnum + 1] = { type = c.type, id = c.id }
      end
    end

    blank()
  end

  if #all_comments == 0 then
    add(indent .. "(no comments yet)", "NitMeta")
    blank()
  end

  return lines, hls, line_map
end

-- Fire four parallel gh fetches. Calls on_done(data) once all complete.
-- data fields: pr, pr_err, commits, commits_err, reviews, reviews_err,
--              issue_comments, issue_comments_err
local function fetch_all(s, on_done)
  local data      = {}
  local remaining = 4
  local gh        = require("nit.gh")

  local function done()
    remaining = remaining - 1
    if remaining == 0 then
      vim.schedule(function() on_done(data) end)
    end
  end

  gh.pr_details(s.repo, s.pr_number, function(result, err)
    data.pr     = result
    data.pr_err = err
    done()
  end)

  gh.pr_commits(s.repo, s.pr_number, function(result, err)
    data.commits     = result or {}
    data.commits_err = err
    done()
  end)

  gh.pr_reviews(s.repo, s.pr_number, function(result, err)
    data.reviews     = result or {}
    data.reviews_err = err
    done()
  end)

  gh.pr_issue_comments(s.repo, s.pr_number, function(result, err)
    data.issue_comments     = result or {}
    data.issue_comments_err = err
    done()
  end)
end

function M.refresh()
  if not M.is_open() then return end
  local session = require("nit.session")
  if not session.is_active() then return end
  local s = session.get()
  set_content({ "", "  Loading…", "" })
  fetch_all(s, function(data)
    local lines, hls, lmap = build_document(data)
    state.line_map = lmap
    set_content(lines)
    apply_highlights(hls)
  end)
end

-- Called after a reply or post succeeds: re-fetch inline comments then refresh the view.
local function after_view_action(err)
  if err then
    vim.schedule(function()
      vim.notify("nit: post failed — " .. tostring(err), vim.log.levels.ERROR)
    end)
    return
  end
  vim.schedule(function()
    vim.notify("nit: comment posted")
    require("nit.comments").fetch(function()
      M.refresh()
    end)
  end)
end

-- Return the line_map entry for the current cursor row, or nil.
function M.entry_at_cursor()
  if not M.is_open() then return nil end
  local row = vim.api.nvim_win_get_cursor(state.winnr)[1]
  return state.line_map[row]
end

-- Public alias used by keymaps (avoids capturing the local closure).
M._after_action = after_view_action

return M
