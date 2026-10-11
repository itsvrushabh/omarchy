#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

uwsm_default="$ROOT/default/uwsm/default"
uwsm_env="$ROOT/default/uwsm/env.d/10-omarchy"
hypr_envs="$ROOT/default/hypr/envs.lua"

# 1. uwsm session default exports XCURSOR_THEME, XCURSOR_SIZE, and HYPRCURSOR_SIZE
theme=$(env -u XCURSOR_THEME bash -c 'source "$1"; printf "%s" "${XCURSOR_THEME:-}"' bash "$uwsm_default")
[[ $theme == "default" ]] || fail "uwsm session env defaults XCURSOR_THEME to 'default'" "actual: $theme"
pass "uwsm session env defaults XCURSOR_THEME to 'default'"

xsize=$(env -u XCURSOR_SIZE bash -c 'source "$1"; printf "%s" "${XCURSOR_SIZE:-}"' bash "$uwsm_default")
[[ $xsize == "24" ]] || fail "uwsm session env defaults XCURSOR_SIZE to '24'" "actual: $xsize"
pass "uwsm session env defaults XCURSOR_SIZE to '24'"

hsize=$(env -u HYPRCURSOR_SIZE bash -c 'source "$1"; printf "%s" "${HYPRCURSOR_SIZE:-}"' bash "$uwsm_default")
[[ $hsize == "24" ]] || fail "uwsm session env defaults HYPRCURSOR_SIZE to '24'" "actual: $hsize"
pass "uwsm session env defaults HYPRCURSOR_SIZE to '24'"

# 2. uwsm session default preserves inherited user cursor settings
custom_theme=$(XCURSOR_THEME="Bibata-Modern-Ice" bash -c 'source "$1"; printf "%s" "$XCURSOR_THEME"' bash "$uwsm_default")
[[ $custom_theme == "Bibata-Modern-Ice" ]] || fail "uwsm session env preserves user XCURSOR_THEME" "actual: $custom_theme"
pass "uwsm session env preserves user XCURSOR_THEME"

custom_size=$(XCURSOR_SIZE="32" bash -c 'source "$1"; printf "%s" "$XCURSOR_SIZE"' bash "$uwsm_default")
[[ $custom_size == "32" ]] || fail "uwsm session env preserves user XCURSOR_SIZE" "actual: $custom_size"
pass "uwsm session env preserves user XCURSOR_SIZE"

# 3. uwsm env.d fallback exports cursor settings when default file is absent
run_uwsm_fallback() {
  local home_dir="${1:-/nonexistent}"
  HOME="$home_dir" env -u XCURSOR_THEME -u XCURSOR_SIZE -u HYPRCURSOR_SIZE bash -c '
    [() {
      if builtin [ "$1" = "-r" ] && builtin [ "$2" = "/usr/share/omarchy/default/bash/env-bootstrap" ]; then
        return 1
      fi
      builtin [ "$@"
    }
    OMARCHY_PATH="/nonexistent"
    source "$1" || true
    printf "%s %s %s\n" "${XCURSOR_THEME:-}" "${XCURSOR_SIZE:-}" "${HYPRCURSOR_SIZE:-}"
  ' bash "$uwsm_env"
}

read -r fallback_theme fallback_xsize fallback_hsize < <(run_uwsm_fallback)
[[ $fallback_theme == "default" ]] || fail "uwsm env.d fallback defaults XCURSOR_THEME to 'default'" "actual: $fallback_theme"
pass "uwsm env.d fallback defaults XCURSOR_THEME to 'default'"
[[ $fallback_xsize == "24" ]] || fail "uwsm env.d fallback defaults XCURSOR_SIZE to '24'" "actual: $fallback_xsize"
pass "uwsm env.d fallback defaults XCURSOR_SIZE to '24'"
[[ $fallback_hsize == "24" ]] || fail "uwsm env.d fallback defaults HYPRCURSOR_SIZE to '24'" "actual: $fallback_hsize"
pass "uwsm env.d fallback defaults HYPRCURSOR_SIZE to '24'"

tmp_home=$(mktemp -d)
mkdir -p "$tmp_home/.config/uwsm"
cat <<'EOF' > "$tmp_home/.config/uwsm/default"
export XCURSOR_THEME="overridden-theme"
export XCURSOR_SIZE="32"
export HYPRCURSOR_SIZE="32"
EOF

read -r override_theme override_size override_hsize < <(run_uwsm_fallback "$tmp_home")
rm -rf "$tmp_home"
[[ $override_theme == "overridden-theme" ]] || fail "uwsm env.d fallback preserves user override XCURSOR_THEME" "actual: $override_theme"
pass "uwsm env.d fallback preserves user override XCURSOR_THEME"
[[ $override_size == "32" ]] || fail "uwsm env.d fallback preserves user override XCURSOR_SIZE" "actual: $override_size"
pass "uwsm env.d fallback preserves user override XCURSOR_SIZE"
[[ $override_hsize == "32" ]] || fail "uwsm env.d fallback preserves user override HYPRCURSOR_SIZE" "actual: $override_hsize"
pass "uwsm env.d fallback preserves user override HYPRCURSOR_SIZE"

# 4. default/hypr/envs.lua exports XCURSOR_THEME and sizes to Hyprland
require_command lua
env -u XCURSOR_THEME -u HYPRCURSOR_THEME -u XCURSOR_SIZE -u HYPRCURSOR_SIZE lua <<LUA
package.path = "$ROOT/?.lua;" .. package.path
local env = {}
o = {
  shell_succeeds = function() return false end,
  shell_quote = function(s) return "'" .. s .. "'" end,
}
hl = {
  env = function(k, v) env[k] = v end,
  config = function() end,
}
package.loaded["default.hypr.require_optional"] = {
  module = function() end,
}
require("default.hypr.envs")
assert(env.XCURSOR_THEME == "default", "default/hypr/envs.lua defaults XCURSOR_THEME to 'default'")
assert(env.XCURSOR_SIZE == "24", "default/hypr/envs.lua defaults XCURSOR_SIZE to '24'")
assert(env.HYPRCURSOR_SIZE == "24", "default/hypr/envs.lua defaults HYPRCURSOR_SIZE to '24'")
assert(env.HYPRCURSOR_THEME == nil, "default/hypr/envs.lua leaves HYPRCURSOR_THEME unset when omitted")
LUA
pass "default/hypr/envs.lua sets default cursor theme and sizes"

XCURSOR_THEME="custom-xcursor" HYPRCURSOR_THEME="custom-hyprcursor" XCURSOR_SIZE="36" HYPRCURSOR_SIZE="36" lua <<LUA
package.path = "$ROOT/?.lua;" .. package.path
local env = {}
o = {
  shell_succeeds = function() return false end,
  shell_quote = function(s) return "'" .. s .. "'" end,
}
hl = {
  env = function(k, v) env[k] = v end,
  config = function() end,
}
package.loaded["default.hypr.require_optional"] = {
  module = function() end,
}
require("default.hypr.envs")
assert(env.XCURSOR_THEME == "custom-xcursor", "default/hypr/envs.lua preserves custom XCURSOR_THEME")
assert(env.HYPRCURSOR_THEME == "custom-hyprcursor", "default/hypr/envs.lua preserves custom HYPRCURSOR_THEME")
assert(env.XCURSOR_SIZE == "36", "default/hypr/envs.lua preserves custom XCURSOR_SIZE")
assert(env.HYPRCURSOR_SIZE == "36", "default/hypr/envs.lua preserves custom HYPRCURSOR_SIZE")
LUA
pass "default/hypr/envs.lua preserves environment overrides"

