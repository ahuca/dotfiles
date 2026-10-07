-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- WinGet configuration files are YAML; yamlls takes the schema from their modeline.
vim.filetype.add({ extension = { winget = "yaml" } })
