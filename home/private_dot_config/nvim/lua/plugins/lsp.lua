-- LSP servers on top of LazyVim's defaults; mason installs any that are
-- missing when Neovim starts.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        -- Runs under pwsh, which both platforms install.
        powershell_es = {},
      },
    },
  },
}
