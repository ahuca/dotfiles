-- The explorer hides dotfiles until toggled with `H`; folders listed in
-- `include` stay visible regardless.
-- File search can't whitelist single dotfiles (fd/rg only take --hidden), so
-- it searches them all; gitignored files and .git stay out.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            include = { ".github" },
          },
          files = {
            hidden = true,
          },
        },
      },
    },
  },
}
