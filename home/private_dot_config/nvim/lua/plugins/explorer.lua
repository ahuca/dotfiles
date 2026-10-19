-- The explorer hides dotfiles until toggled with `H`; folders listed in
-- `include` stay visible regardless.
-- File search can't whitelist single dotfiles (fd/rg only take --hidden), so
-- it searches them all; .git stays out.
-- Gitignored files are shown in every picker that supports it. It has to be
-- set per source: the built-in source defaults override top-level picker opts.
-- Toggle with `I` in the explorer or `<A-i>` in pickers.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            include = { ".github" },
            ignored = true,
          },
          files = {
            hidden = true,
            ignored = true,
          },
          grep = {
            hidden = true,
            ignored = true,
          },
          grep_word = {
            hidden = true,
            ignored = true,
          },
          git_status = {
            ignored = true,
          },
        },
      },
    },
  },
}
