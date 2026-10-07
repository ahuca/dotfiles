-- Managed by chezmoi (home/.chezmoitemplates/nvim-chezmoi.lua).
-- The chezmoi extra assumes the source state is in ~/.local/share/chezmoi;
-- point chezmoi.vim at the real one so it highlights the templates there.
return {
  {
    "alker0/chezmoi.vim",
    init = function()
      vim.g["chezmoi#use_tmp_buffer"] = 1
      vim.g["chezmoi#source_dir_path"] = {{ .chezmoi.sourceDir | toJson }}
    end,
  },
}
