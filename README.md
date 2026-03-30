# nit.nvim

A Neovim plugin for reviewing GitHub Pull Requests without leaving your editor.

## Features

- Browse and select open PRs with `:Nit pr`
- Auto-checkout the PR branch on selection
- Sidebar panel showing changed files with status badges
- Side-by-side diffs comparing merge-base to HEAD
- Inline comment threads with author, timestamp, and replies
- Post comments, reply to threads, and suggest code changes
- Submit reviews (Comment / Approve / Request changes)
- Full PR overview: description, commits, and all comments in a single float

## Requirements

- Neovim 0.9+
- [`gh`](https://cli.github.com/) CLI — installed and authenticated (`gh auth login`)
- `git`
- A [Nerd Font](https://www.nerdfonts.com/) — required for icons in the inline comment indicator

## Optional dependencies

| Plugin | Effect |
|--------|--------|
| [`render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) | Renders markdown in the PR view float — bold, italic, inline code, code blocks, lists, and more. Install and configure it normally; nit.nvim detects it automatically. No extra configuration needed. |

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "matthewalunni/nit.nvim",
  config = function()
    require("nit").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "matthewalunni/nit.nvim",
  config = function()
    require("nit").setup()
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'matthewalunni/nit.nvim'
```

Then call `require("nit").setup()` in your config.

## Configuration

`setup()` is optional — the plugin works with defaults out of the box. Pass a table to override:

```lua
require("nit").setup({
  panel_width = 40,
  auto_open_panel = true,
  auto_fetch_comments = true,
  comment_cache_ttl = 120, -- seconds
  icons = {
    added    = " ",
    modified = " ",
    deleted  = " ",
    renamed  = " ",
    comment  = " ",
  },
  keys = {
    open_pr_picker = "<leader>grp",
    toggle_panel   = "<leader>grf",
    start_review   = "<leader>grs",
    submit_review  = "<leader>grS",
    open_pr_view   = "<leader>grv",
  },
})
```

## Usage

| Command          | Description                                        |
|------------------|----------------------------------------------------|
| `:Nit`           | Open PR picker (same as `:Nit pr`)                 |
| `:Nit pr`        | Select and checkout a PR                           |
| `:Nit pr 123`    | Load PR #123 directly (skip the picker)            |
| `:Nit 123`       | Shorthand for `:Nit pr 123`                        |
| `:Nit panel`     | Toggle the changed-files panel                     |
| `:Nit panel 123` | Toggle the panel, loading PR #123 if not active    |
| `:Nit view`      | Open the full PR overview float                    |
| `:Nit view 123`  | Open the PR overview float for PR #123             |
| `:Nit start`     | Start a review                                     |
| `:Nit submit`    | Submit your review                                 |

**Typical workflow:**

1. Run `:Nit pr` and select a PR — the branch is checked out automatically.
2. The file panel opens showing every changed file with its status.
3. Press `<CR>` on a file to open a side-by-side diff.
4. Run `:Nit start` (or `<leader>grs`) to start a review; add inline comments directly in the diff.
5. Run `:Nit submit` (or `<leader>grS`) to submit as Comment, Approve, or Request changes.

### Keymaps

**Diff buffer** (available after opening a file from the panel):

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>grc` | Normal | Comment on current line |
| `<leader>grc` | Visual | Comment on selected lines |
| `<leader>grg` | Visual | Suggest a code change |
| `<leader>grr` | Normal | Reply to thread at cursor |
| `<leader>grx` | Normal | Toggle comment thread expand/collapse |
| `]r` / `[r` | Normal | Next / previous comment |
| `]c` / `[c` | Normal | Next / previous diff hunk |

**File panel:**

| Key | Description |
|-----|-------------|
| `<CR>` | Open diff for selected file |
| `R` | Refresh comments |
| `]f` / `[f` | Next / previous file |
| `q` | Close panel |

**PR view** (open with `<leader>grv` or `:Nit view`):

| Key | Description |
|-----|-------------|
| `r` | Reply to inline thread, or post a new PR comment for review/issue comments |
| `c` | Post a new general PR comment |
| `R` | Refresh |
| `gf` | Open diff for inline thread under cursor |
| `q` / `<Esc>` | Close |
