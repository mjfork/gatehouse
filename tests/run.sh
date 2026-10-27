#!/usr/bin/env bash
# Tests for install.sh. Each test gets a throwaway HOME, stand-in repos whose install.sh only logs
# its arguments, and stub herdr/claude/uv on PATH, so nothing real is cloned or installed.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0 FAIL=0

setup() {
  T=$(mktemp -d)
  export HOME="$T/home" LOG="$T/log"
  mkdir -p "$HOME" "$T/bin" "$T/repos"
  : >"$LOG"
  for bin in herdr uv; do printf '#!/bin/sh\nexit 0\n' >"$T/bin/$bin"; done
  cat >"$T/bin/claude" <<'EOF'
#!/bin/sh
echo "claude $*" >>"$LOG"
[ "$1 $2 $3" = "plugin marketplace list" ] && [ -n "${MARKET_SOURCE:-}" ] && printf '  ❯ mjfork\n    Source: %s\n' "$MARKET_SOURCE"
[ "$1 $2" = "plugin list" ] && [ -n "${PLUGINS_INSTALLED:-}" ] && printf '  ❯ %s\n' $PLUGINS_INSTALLED
exit 0
EOF
  chmod +x "$T/bin"/*
  export PATH="$T/bin:$PATH"
  for name in trk hx workbench; do
    git init -q -b main "$T/repos/$name"
    printf '#!/bin/sh\necho "%s install.sh $*" >>"$LOG"\ncase " $* " in *" --dry-run "*) [ "${DIFFERS:-}" = %s ] && echo "skill x differs; [dry-run] a real run would refuse here";; esac\nexit 0\n' "$name" "$name" >"$T/repos/$name/install.sh"
    chmod +x "$T/repos/$name/install.sh"
    git -C "$T/repos/$name" add install.sh
    git -C "$T/repos/$name" -c user.name=t -c user.email=t@t commit -q -m one
    echo two >"$T/repos/$name/later"
    git -C "$T/repos/$name" add later
    git -C "$T/repos/$name" -c user.name=t -c user.email=t@t commit -q -m two
  done
  # a copy of gatehouse whose versions.toml pins each stand-in at its first commit
  mkdir -p "$T/gh"
  cp "$HERE/install.sh" "$T/gh/"
  sed -e "s#^commit = .*#commit = \"PIN\"#" "$HERE/versions.toml" >"$T/gh/versions.toml"
  for name in trk hx workbench; do
    first=$(git -C "$T/repos/$name" rev-list --max-parents=0 HEAD)
    python3 -I - "$T/gh/versions.toml" "$name" "$first" <<'PY'
import re, sys
path, name, sha = sys.argv[1:]
text = open(path).read()
text = re.sub(rf'(\[{name}\][^\[]*?commit = )"PIN"', rf'\g<1>"{sha}"', text, flags=re.S)
open(path, "w").write(text)
PY
  done
  export GATEHOUSE_REPO_BASE="$T/repos"
}

teardown() { rm -rf "${T:?}"; }

check() {
  local name=$1; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $name"; sed 's/^/    /' "$LOG"; fi
}

logged() { grep -qF -- "$1" "$LOG"; }
not_logged() { ! grep -qF -- "$1" "$LOG"; }
at_pin() { [ "$(git -C "$HOME/src/$1" rev-parse HEAD)" = "$(git -C "$T/repos/$1" rev-list --max-parents=0 HEAD)" ]; }

t_default_installs_trk_hx_and_plugins_at_the_pins() {
  setup; "$T/gh/install.sh" >/dev/null 2>&1
  check "default: trk previewed, then installed as a copy" logged "trk install.sh --force --no-editable"
  check "default: hx installed as a copy" logged "hx install.sh --force --no-editable"
  check "default: trk at its pin, not the newest commit" at_pin trk
  check "default: hx at its pin" at_pin hx
  check "default: workbench at its pin" at_pin workbench
  check "default: marketplace added from the pinned clone" logged "claude plugin marketplace add $HOME/src/workbench"
  check "default: plugins installed" logged "claude plugin install turn-mode@mjfork"
  teardown
}

t_our_marketplace_and_plugins_are_updated_not_added() {
  setup; MARKET_SOURCE="Directory ($HOME/src/workbench)" PLUGINS_INSTALLED="turn-mode@mjfork" "$T/gh/install.sh" >/dev/null 2>&1
  check "ours: marketplace updated" logged "claude plugin marketplace update mjfork"
  check "ours: not added again" not_logged "marketplace add"
  check "ours: installed plugin updated" logged "claude plugin update turn-mode@mjfork"
  check "ours: missing plugin installed" logged "claude plugin install cockpit@mjfork"
  teardown
}

t_a_marketplace_from_elsewhere_is_left_alone() {
  setup; out=$(MARKET_SOURCE="GitHub (mjfork/workbench)" "$T/gh/install.sh" 2>&1)
  check "elsewhere: not re-added" not_logged "marketplace add"
  check "elsewhere: not updated" not_logged "marketplace update"
  check "elsewhere: says plugins follow it" grep -q "not the pin" <<<"$out"
  teardown
}

t_options_choose_what_is_installed() {
  setup; "$T/gh/install.sh" --no-hx --plugins cockpit,vet >/dev/null 2>&1
  check "options: no hx" not_logged "hx install.sh"
  check "options: chosen plugins" logged "claude plugin install vet@mjfork"
  check "options: others not installed" not_logged "turn-mode@mjfork"
  teardown
}

t_options_after_dashes_reach_hx() {
  setup; "$T/gh/install.sh" --no-plugins -- --no-sidebar >/dev/null 2>&1
  check "dashes: hx gets them" logged "hx install.sh --force --no-editable --no-sidebar"
  check "dashes: no plugins" not_logged "claude plugin"
  teardown
}

t_me_reaches_trk_and_hx() {
  setup; "$T/gh/install.sh" --no-plugins --me alice >/dev/null 2>&1
  check "me: trk" logged "trk install.sh --force --no-editable --me alice"
  check "me: hx" logged "hx install.sh --force --no-editable --me alice"
  teardown
}

t_differing_skills_stop_the_install_without_force() {
  setup; out=$(DIFFERS=hx "$T/gh/install.sh" --no-plugins 2>&1); code=$?
  check "differs: refused" test "$code" = 1
  check "differs: hx not forced" not_logged "hx install.sh --force"
  check "differs: says --force" grep -q "Run again with --force" <<<"$out"
  : >"$LOG"; DIFFERS=hx "$T/gh/install.sh" --no-plugins --force >/dev/null 2>&1
  check "differs: --force replaces" logged "hx install.sh --force --no-editable"
  teardown
}

t_an_old_clone_is_fetched_from_the_pinned_url() {
  setup; git clone -q "$T/repos/trk" "$HOME/src/trk"
  git -C "$HOME/src/trk" remote set-url origin "$T/nowhere"
  "$T/gh/install.sh" --no-plugins --no-hx >/dev/null 2>&1
  check "old origin: still reaches the pin" at_pin trk
  teardown
}

t_dry_run_changes_nothing() {
  setup; out=$("$T/gh/install.sh" --dry-run 2>&1)
  check "dry run: nothing cloned" test ! -e "$HOME/src"
  check "dry run: no real install" not_logged "--force"
  check "dry run: no claude change" not_logged "plugin install"
  check "dry run: says what it would do" grep -q "would run: git clone" <<<"$out"
  teardown
}

t_a_dry_run_on_an_old_clone_says_the_preview_is_not_the_pin() {
  setup; git clone -q "$T/repos/trk" "$HOME/src/trk"
  out=$("$T/gh/install.sh" --dry-run --no-plugins --no-hx 2>&1)
  check "dry old: says so" grep -q "not on" <<<"$out"
  teardown
}

t_a_second_run_moves_an_existing_clone_to_the_pin() {
  setup; "$T/gh/install.sh" --no-plugins >/dev/null 2>&1
  git -C "$HOME/src/trk" -c advice.detachedHead=false checkout -q main
  "$T/gh/install.sh" --no-plugins >/dev/null 2>&1
  check "rerun: back at the pin" at_pin trk
  teardown
}

t_local_changes_stop_the_install() {
  setup; "$T/gh/install.sh" --no-plugins >/dev/null 2>&1
  echo mine >"$HOME/src/trk/mine"; : >"$LOG"
  "$T/gh/install.sh" --no-plugins >/dev/null 2>&1; code=$?
  check "dirty: refused" test "$code" = 1
  check "dirty: nothing installed" not_logged "install.sh"
  teardown
}

t_missing_herdr_is_named() {
  setup; rm "$T/bin/herdr"
  out=$(PATH="$T/bin:/usr/bin:/bin" "$T/gh/install.sh" 2>&1); code=$?
  check "no herdr: refused" test "$code" = 1
  check "no herdr: says --no-hx" grep -q -- "--no-hx" <<<"$out"
  teardown
}

t_uninstall_runs_each_installer() {
  setup; "$T/gh/install.sh" --no-plugins >/dev/null 2>&1; : >"$LOG"
  out=$("$T/gh/install.sh" --uninstall 2>&1)
  check "uninstall: trk" logged "trk install.sh --uninstall"
  check "uninstall: hx" logged "hx install.sh --uninstall"
  check "uninstall: clones kept" test -d "$HOME/src/trk"
  check "uninstall: says how to remove plugins" grep -q "claude plugin uninstall turn-mode@mjfork" <<<"$out"
  teardown
}

t_unknown_option_is_refused() {
  setup; "$T/gh/install.sh" --nod-agent >/dev/null 2>&1; code=$?
  check "unknown: exit 2" test "$code" = 2
  teardown
}

t_the_real_pins_are_full_commit_ids() {
  check "pins: 40 hex characters" test "$(grep -cE '^commit = "[0-9a-f]{40}"$' "$HERE/versions.toml")" = 3
}

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do "$t"; done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
