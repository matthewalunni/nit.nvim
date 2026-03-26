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

## Requirements

- Neovim 0.9+
- [`gh`](https://cli.github.com/) CLI — installed and authenticated (`gh auth login`)
- `git`

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
  },
})
```

## Usage

| Command       | Description                          |
|---------------|--------------------------------------|
| `:Nit`        | Open PR picker (same as `:Nit pr`)   |
| `:Nit pr`     | Select and checkout a PR             |
| `:Nit panel`  | Toggle the changed-files panel       |
| `:Nit submit` | Submit your review                   |

**Typical workflow:**

1. Run `:Nit pr` and select a PR — the branch is checked out automatically.
2. The file panel opens showing every changed file with its status.
3. Press `<CR>` on a file to open a side-by-side diff.
4. Use `<leader>grs` to start a review; add inline comments directly in the diff.
5. Run `:Nit submit` (or `<leader>grS`) to submit as Comment, Approve, or Request changes.
