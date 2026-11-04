# Ryoku palette for fish and fzf. Rendered by the theme daemon; do not edit.
#
# Dropped straight into conf.d, which fish sources on its own, so nothing in the
# shipped config has to include it. Your ~/.config/fish/user.fish loads last and
# still wins.

# Syntax highlighting.
set -g fish_color_normal e1e1e1
set -g fish_color_command c3c3c3
set -g fish_color_keyword c4c4c4
set -g fish_color_quote c2c2c2
set -g fish_color_redirection c2c2c2
set -g fish_color_end c4c4c4
set -g fish_color_error c3c3c3
set -g fish_color_param e1e1e1
set -g fish_color_comment c2c2c2
set -g fish_color_selection --background=3d3d3d
set -g fish_color_operator c4c4c4
set -g fish_color_escape c2c2c2
set -g fish_color_autosuggestion c2c2c2
set -g fish_color_cancel c3c3c3
set -g fish_color_search_match --background=3d3d3d
set -g fish_color_valid_path --underline

# Completion pager.
set -g fish_pager_color_progress c2c2c2
set -g fish_pager_color_prefix c3c3c3
set -g fish_pager_color_completion e1e1e1
set -g fish_pager_color_description c2c2c2
set -g fish_pager_color_selected_background --background=3d3d3d

# fzf takes the same palette, so Ctrl-R and Ctrl-T match the terminal they open
# in. Appended to whatever options are already set rather than replacing them.
set -gx FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS \
--color=fg:#e1e1e1,bg:-1,hl:#c3c3c3 \
--color=fg+:#e1e1e1,bg+:#3d3d3d,hl+:#c3c3c3 \
--color=info:#c2c2c2,prompt:#c3c3c3,pointer:#c4c4c4 \
--color=marker:#c4c4c4,spinner:#c2c2c2,header:#c2c2c2 \
--color=border:#3c3c3c"
