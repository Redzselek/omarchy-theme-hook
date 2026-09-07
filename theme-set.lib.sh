#!/bin/bash

# Shared library for the Omarchy theme hook.
#
# Both the theme-set hook and every hooklette in theme-set.d source this file,
# because Omarchy 4's omarchy-hook runs each hooklette as its own process
# instead of as a child of theme-set, so exported functions and colors are not
# in scope there.

[[ -n "${THEME_HOOK_LIB_SOURCED:-}" ]] && return 0
THEME_HOOK_LIB_SOURCED=1

success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

skipped() {
    echo -e "\033[0;34m[SKIPPED]\e[0m $1 not found. Skipping.."
    exit 0
}

warning() {
    echo -e "\033[0;33m[WARNING]\e[0m $1"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
    exit 1
}

# omarchy-hook executes every file in theme-set.d regardless of its permissions,
# so hooklettes disabled through `thctl disable` (chmod -x) have to bail here.
hooklette="${BASH_SOURCE[1]:-}"
if [[ $hooklette == */theme-set.d/* && -f $hooklette && ! -x $hooklette ]]; then
    exit 0
fi
unset hooklette

# Omarchy 4 moved the current theme pointer to ~/.local/state, Omarchy 3 keeps
# it in ~/.config. The stale ~/.config directory survives the upgrade, so the
# theme directory is resolved by looking for colors.toml rather than by testing
# whether the directory exists.
resolve_theme_dir() {
    local dir
    for dir in "$HOME/.local/state/omarchy/current/theme" "$HOME/.config/omarchy/current/theme"; do
        if [[ -f "$dir/colors.toml" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

if [[ -z "${omarchy_theme_dir:-}" ]]; then
    omarchy_theme_dir=$(resolve_theme_dir) ||
        error "colors.toml not found in ~/.local/state/omarchy/current/theme or ~/.config/omarchy/current/theme. Ensure your theme is compatible with Omarchy 3.3+ and includes colors.toml."
fi
colors_file="$omarchy_theme_dir/colors.toml"
export omarchy_theme_dir colors_file

hex2rgb() {
    local hex_input="${1#\#}"
    [[ $hex_input =~ ^[0-9a-fA-F]{6}$ ]] || error "Invalid hex color \"$1\" read from $colors_file."
    printf '%d, %d, %d\n' "$((16#${hex_input:0:2}))" "$((16#${hex_input:2:2}))" "$((16#${hex_input:4:2}))"
}

rgb2hex() {
    printf "%02x%02x%02x" "$1" "$2" "$3"
}

change_shade() {
    local hex_input="${1#\#}"
    local shade=$2
    [[ $hex_input =~ ^[0-9a-fA-F]{6}$ ]] || error "Invalid hex color \"$1\" read from $colors_file."

    local channel value shifted=()
    for channel in "${hex_input:0:2}" "${hex_input:2:2}" "${hex_input:4:2}"; do
        value=$((16#$channel + shade))
        ((value < 0)) && value=0
        ((value > 255)) && value=255
        shifted+=("$value")
    done

    rgb2hex "${shifted[@]}"
}

restart_file="${THEME_HOOK_RESTART_FILE:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-theme-hook.restart}"
export restart_file

require_restart() {
    echo "$1" >> "$restart_file"
}

# Read every color in a single pass; each hooklette runs in its own process and
# would otherwise spawn an awk per color.
load_theme_colors() {
    local key hex
    while IFS='=' read -r key hex; do
        case "$key" in
            foreground) primary_foreground=$hex ;;
            background) primary_background=$hex ;;
            cursor) cursor_color=$hex ;;
            selection_foreground) selection_foreground=$hex ;;
            selection_background) selection_background=$hex ;;
            color0) normal_black=$hex ;;
            color1) normal_red=$hex ;;
            color2) normal_green=$hex ;;
            color3) normal_yellow=$hex ;;
            color4) normal_blue=$hex ;;
            color5) normal_magenta=$hex ;;
            color6) normal_cyan=$hex ;;
            color7) normal_white=$hex ;;
            color8) bright_black=$hex ;;
            color9) bright_red=$hex ;;
            color10) bright_green=$hex ;;
            color11) bright_yellow=$hex ;;
            color12) bright_blue=$hex ;;
            color13) bright_magenta=$hex ;;
            color14) bright_cyan=$hex ;;
            color15) bright_white=$hex ;;
        esac
    done < <(awk '
        /=/ && match($0, /#[0-9a-fA-F]{6}/) && seen[$1]++ == 0 {
            print $1 "=" substr($0, RSTART + 1, 6)
        }
    ' "$colors_file")

    local missing=()
    local name
    for name in primary_foreground primary_background \
        normal_black normal_red normal_green normal_yellow \
        normal_blue normal_magenta normal_cyan normal_white \
        bright_black bright_red bright_green bright_yellow \
        bright_blue bright_magenta bright_cyan bright_white; do
        [[ -n ${!name} ]] || missing+=("$name")
    done

    if ((${#missing[@]} > 0)); then
        error "No color found for ${missing[*]} in $colors_file. Ensure your theme is compatible with Omarchy 3.3+."
    fi

    # Optional keys fall back to the primary colors, as themes may omit them.
    : "${cursor_color:=$primary_foreground}"
    : "${selection_foreground:=$primary_background}"
    : "${selection_background:=$primary_foreground}"

    rgb_primary_foreground=$(hex2rgb "$primary_foreground")
    rgb_primary_background=$(hex2rgb "$primary_background")
    rgb_normal_black=$(hex2rgb "$normal_black")
    rgb_normal_red=$(hex2rgb "$normal_red")
    rgb_normal_green=$(hex2rgb "$normal_green")
    rgb_normal_yellow=$(hex2rgb "$normal_yellow")
    rgb_normal_blue=$(hex2rgb "$normal_blue")
    rgb_normal_magenta=$(hex2rgb "$normal_magenta")
    rgb_normal_cyan=$(hex2rgb "$normal_cyan")
    rgb_normal_white=$(hex2rgb "$normal_white")
    rgb_bright_black=$(hex2rgb "$bright_black")
    rgb_bright_red=$(hex2rgb "$bright_red")
    rgb_bright_green=$(hex2rgb "$bright_green")
    rgb_bright_yellow=$(hex2rgb "$bright_yellow")
    rgb_bright_blue=$(hex2rgb "$bright_blue")
    rgb_bright_magenta=$(hex2rgb "$bright_magenta")
    rgb_bright_cyan=$(hex2rgb "$bright_cyan")
    rgb_bright_white=$(hex2rgb "$bright_white")
}

load_theme_colors
