#!/usr/bin/env bash
# Tests for install.sh. Each test gets a throwaway HOME, stand-in repos whose install.sh only logs
# its arguments, and stub herdr/claude/uv/gh on PATH, so nothing real is cloned or installed.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0 FAIL=0

setup() {
  T=$(mktemp -d)
  export HOME="$T/home" TEST_LOG="$T/log" GATEHOUSE_TTY="$T/no-terminal/tty"
  unset XDG_DATA_HOME XDG_STATE_HOME
  mkdir -p "$HOME/.local/bin" "$T/bin" "$T/repos"
  : >"$TEST_LOG"
  for bin in herdr uv gh; do printf '#!/bin/sh\nexit 0\n' >"$T/bin/$bin"; done
  for bin in launchctl systemctl; do printf '#!/bin/sh\nexit 1\n' >"$T/bin/$bin"; done  # no watcher running
  cat >"$T/bin/claude" <<'EOF'
#!/bin/sh
echo "claude $*" >>"$TEST_LOG"
[ "$1 $2 $3" = "plugin marketplace list" ] && [ -n "${MARKET_SOURCE:-}" ] && printf '  ❯ mjfork\n    Source: %s\n' "$MARKET_SOURCE"
[ "$1 $2" = "plugin list" ] && [ -n "${PLUGINS_INSTALLED:-}" ] && printf '  ❯ %s\n' $PLUGINS_INSTALLED
if [ "$1 $2" = "plugin configure" ]; then
  case " $* " in
    *" --json "*) # COCKPIT_STACK: unset or set gives cockpit a stack option; empty, no option
      case "${COCKPIT_STACK:-}" in
        unset) echo '{"schema": {"stack": {}}, "unconfigured": ["stack"]}' ;;
        set) echo '{"schema": {"stack": {}}, "unconfigured": []}' ;;
        *) echo '{"schema": {}, "unconfigured": []}' ;;
      esac ;;
    *" --values-stdin "*) echo "claude $* $(cat)" >>"$TEST_LOG" ;;
  esac
fi
exit 0
EOF
  chmod +x "$T/bin"/*
  export PATH="$T/bin:$HOME/.local/bin:$PATH"
  for name in trk hx workbench; do
    git init -q -b main "$T/repos/$name"
    printf '#!/bin/sh\necho "%s install.sh $*" >>"$TEST_LOG"\ncase " $* " in *" --dry-run "*) [ "${DIFFERS:-}" = %s ] && echo "skill x differs; [dry-run] a real run would refuse here";; esac\n[ "${FAILS:-}" = %s ] && case " $* " in *" --force "*) echo "boom from %s"; exit 3;; esac\nexit 0\n' "$name" "$name" "$name" "$name" >"$T/repos/$name/install.sh"
    chmod +x "$T/repos/$name/install.sh"
    git -C "$T/repos/$name" add install.sh
    git -C "$T/repos/$name" -c user.name=t -c user.email=t@t commit -q -m one
    echo two >"$T/repos/$name/later"
    git -C "$T/repos/$name" add later
    git -C "$T/repos/$name" -c user.name=t -c user.email=t@t commit -q -m two
  done
  # a gatehouse repo whose versions.toml pins each stand-in at its first commit
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
  git -C "$T/gh" init -q -b main
  git -C "$T/gh" add -A
  git -C "$T/gh" -c user.name=t -c user.email=t@t commit -q -m gatehouse
  export GATEHOUSE_REPO_BASE="$T/repos" GATEHOUSE_URL="$T/gh"
  SRC="$HOME/.local/share/gatehouse"
  # a folder holding only a python3 that is 3.12 or newer, for tests that cut PATH down
  mkdir "$T/py"
  for c in python3 python3.14 python3.13 python3.12; do
    command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 12))' && { ln -s "$(command -v "$c")" "$T/py/python3"; break; }
  done
}

teardown() { rm -rf "${T:?}"; }

check() {
  local name=$1; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $name"; sed 's/^/    /' "$TEST_LOG"; fi
}

pin_of() { git -C "$T/repos/$1" rev-list --max-parents=0 HEAD; }
logged() { grep -qF -- "$1" "$TEST_LOG"; }
not_logged() { ! grep -qF -- "$1" "$TEST_LOG"; }
at_pin() { [ "$(git -C "$SRC/$1" rev-parse HEAD)" = "$(pin_of "$1")" ]; }
says() { grep -qF -- "$1" <<<"$out"; }
# a stand-in `trk`/`hx` on PATH whose --version --json reports <commit> (none given: null)
fake_tool() {
  local commit=null
  [ -n "${2:-}" ] && commit="\"$2\""
  printf '#!/bin/sh\necho %s\n' "'{\"version\": \"0.1.0\", \"commit\": $commit}'" >"$HOME/.local/bin/$1"
  chmod +x "$HOME/.local/bin/$1"
}

t_default_installs_trk_hx_and_plugins_at_the_pins() {
  setup; out=$("$T/gh/install.sh" --full 2>&1)
  check "default: trk installed as a copy" logged "trk install.sh --force --no-editable"
  check "default: hx installed as a copy" logged "hx install.sh --force --no-editable"
  check "default: clones under ~/.local/share/gatehouse" test -d "$SRC/trk/.git"
  check "default: nothing in ~/src" test ! -e "$HOME/src"
  check "default: trk at its pin, not the newest commit" at_pin trk
  check "default: hx at its pin" at_pin hx
  check "default: workbench at its pin" at_pin workbench
  check "default: marketplace added from the pinned clone" logged "claude plugin marketplace add $SRC/workbench"
  check "default: plugins installed" logged "claude plugin install turn-mode@mjfork"
  check "default: summary box" says "gatehouse: done"
  check "default: summary says installed" says "trk        installed at"
  check "default: summary names --verify" says "install.sh --verify"
  check "default: a log was written" test -n "$(ls "$HOME/.local/state/gatehouse/"install-*.log 2>/dev/null)"
  check "default: the lock is gone" test ! -e "$HOME/.local/state/gatehouse/install.lock"
  teardown
}

t_piped_from_curl_it_clones_gatehouse_and_runs_from_there() {
  setup; out=$(cd "$T" && bash -s -- --full --no-plugins <"$T/gh/install.sh" --full 2>&1); code=$?
  check "piped: succeeds" test "$code" = 0
  check "piped: gatehouse cloned" test -f "$SRC/gatehouse/versions.toml"
  check "piped: trk installed" logged "trk install.sh --force --no-editable"
  : >"$TEST_LOG"; out=$(cd "$T" && bash -s -- --full --no-plugins <"$T/gh/install.sh" --full 2>&1)
  check "piped again: updates the clone" says "Updating gatehouse"
  teardown
}

t_a_piped_dry_run_or_force_reaches_the_options_and_a_dry_run_leaves_nothing() {
  setup; out=$(cd "$T" && bash -s -- --full --dry-run <"$T/gh/install.sh" --full 2>&1); code=$?
  check "piped dry run: succeeds" test "$code" = 0
  check "piped dry run: previews" says "dry run: nothing was changed"
  check "piped dry run: no gatehouse clone left" test ! -e "$SRC"
  out=$(cd "$T" && bash -s -- --full --no-plugins <"$T/gh/install.sh" --full 2>&1); : >"$TEST_LOG"
  out=$(cd "$T" && bash -s -- --full --force --no-plugins <"$T/gh/install.sh" --full 2>&1)
  check "piped --force: reaches the tools" logged "trk install.sh --force"
  teardown
}

t_a_rerun_skips_tools_already_at_their_pins() {
  setup; fake_tool trk; fake_tool hx
  "$T/gh/install.sh" --full --no-plugins >/dev/null 2>&1; : >"$TEST_LOG"
  out=$("$T/gh/install.sh" --full --no-plugins 2>&1)
  check "rerun: trk not reinstalled" not_logged "trk install.sh"
  check "rerun: says current" says "trk        current at"
  : >"$TEST_LOG"; "$T/gh/install.sh" --full --no-plugins --force >/dev/null 2>&1
  check "rerun --force: reinstalls" logged "trk install.sh --force"
  teardown
}

t_a_tool_reporting_its_pin_is_skipped_without_a_record() {
  setup; fake_tool trk "$(pin_of trk)"
  out=$("$T/gh/install.sh" --full --no-plugins --no-hx 2>&1)
  check "reported: not reinstalled" not_logged "trk install.sh --force"
  check "reported: says already" says "trk is already at"
  teardown
}

t_a_tool_at_another_commit_is_updated() {
  setup; fake_tool trk "$(git -C "$T/repos/trk" rev-parse HEAD)"
  out=$("$T/gh/install.sh" --full --no-plugins --no-hx 2>&1)
  check "other: reinstalled" logged "trk install.sh --force"
  check "other: says updated" says "trk        updated at"
  teardown
}

t_our_marketplace_and_plugins_are_updated_not_added() {
  setup; MARKET_SOURCE="Directory ($SRC/workbench)" PLUGINS_INSTALLED="turn-mode@mjfork" "$T/gh/install.sh" --full >/dev/null 2>&1
  check "ours: marketplace updated" logged "claude plugin marketplace update mjfork"
  check "ours: not added again" not_logged "marketplace add"
  check "ours: installed plugin updated" logged "claude plugin update turn-mode@mjfork"
  check "ours: missing plugin installed" logged "claude plugin install cockpit@mjfork"
  teardown
}

t_a_marketplace_from_elsewhere_is_left_alone() {
  setup; out=$(MARKET_SOURCE="GitHub (mjfork/workbench)" "$T/gh/install.sh" --full 2>&1)
  check "elsewhere: not re-added" not_logged "marketplace add"
  check "elsewhere: not updated" not_logged "marketplace update"
  check "elsewhere: says plugins follow it" says "not the pin"
  teardown
}

t_options_choose_what_is_installed() {
  setup; "$T/gh/install.sh" --full --no-hx --plugins cockpit,vet >/dev/null 2>&1
  check "options: no hx" not_logged "hx install.sh"
  check "options: chosen plugins" logged "claude plugin install vet@mjfork"
  check "options: others not installed" not_logged "turn-mode@mjfork"
  teardown
}

t_options_after_dashes_reach_hx() {
  setup; "$T/gh/install.sh" --full --no-plugins -- --no-sidebar >/dev/null 2>&1
  check "dashes: hx gets them" logged "hx install.sh --force --no-editable --no-sidebar"
  check "dashes: no plugins" not_logged "claude plugin"
  teardown
}

t_me_reaches_trk_and_hx() {
  setup; "$T/gh/install.sh" --full --no-plugins --me alice >/dev/null 2>&1
  check "me: trk" logged "trk install.sh --force --no-editable --me alice"
  check "me: hx" logged "hx install.sh --force --no-editable --me alice"
  teardown
}

t_the_default_installs_only_the_plugins() {
  setup; rm "$T/bin/uv"
  out=$("$T/gh/install.sh" 2>&1); code=$?
  check "plugins: succeeds without uv" test "$code" = 0
  check "plugins: no trk" not_logged "trk install.sh"
  check "plugins: no hx" not_logged "hx install.sh"
  check "plugins: no trk clone" test ! -e "$HOME/.local/share/gatehouse/trk"
  check "plugins: installed" logged "claude plugin install herdr-jump@mjfork"
  check "plugins: says how to add more" says "--full adds trk and hx"
  : >"$TEST_LOG"; "$T/gh/install.sh" >/dev/null 2>&1
  check "plugins: a rerun stays at the plugins" not_logged "trk install.sh"
  out=$(PLUGINS_INSTALLED="cockpit@mjfork ctx-bar@mjfork cache-timer@mjfork herdr-jump@mjfork turn-mode@mjfork" "$T/gh/install.sh" --verify 2>&1); code=$?
  check "plugins: verify skips trk and hx" test "$code" = 0
  check "plugins: verify names the level" says "level: plugins"
  printf '#!/bin/sh\nexit 0\n' >"$T/bin/uv"; chmod +x "$T/bin/uv"
  : >"$TEST_LOG"; "$T/gh/install.sh" --full >/dev/null 2>&1
  check "plugins: --full adds trk" logged "trk install.sh --force --no-editable"
  check "plugins: --full adds hx" logged "hx install.sh --force --no-editable"
  : >"$TEST_LOG"; "$T/gh/install.sh" --force >/dev/null 2>&1
  check "full: a plain rerun keeps trk and hx" logged "trk install.sh --force --no-editable"
  teardown
}

t_an_install_from_before_levels_counts_as_full() {
  setup; mkdir -p "$HOME/.local/state/gatehouse"; echo "trk=abc" >"$HOME/.local/state/gatehouse/installed"
  "$T/gh/install.sh" --no-plugins >/dev/null 2>&1
  check "old install: trk still updated" logged "trk install.sh --force --no-editable"
  teardown
}

t_tool_options_imply_full() {
  setup; "$T/gh/install.sh" --no-plugins --no-hx >/dev/null 2>&1
  check "implies: --no-hx installs trk" logged "trk install.sh"
  teardown
  setup; "$T/gh/install.sh" --no-plugins --me alice >/dev/null 2>&1
  check "implies: --me installs trk" logged "trk install.sh --force --no-editable --me alice"
  teardown
}

t_the_plugins_level_needs_herdr_and_the_plugins() {
  setup; rm "$T/bin/herdr"
  out=$(PATH="$T/bin:/usr/bin:/bin" "$T/gh/install.sh" 2>&1); code=$?
  check "plugins no herdr: refused" test "$code" = 1
  check "plugins no herdr: says why" says "needs-you queue lives in herdr"
  "$T/gh/install.sh" --no-plugins >/dev/null 2>&1; code=$?
  check "plugins no plugins: refused" test "$code" = 2
  teardown
}

t_cockpit_gets_stack_auto_only_when_unset() {
  setup; COCKPIT_STACK=unset "$T/gh/install.sh" >/dev/null 2>&1
  check "stack: unset is set to auto" logged "claude plugin configure cockpit@mjfork --values-stdin {\"stack\":\"auto\"}"
  : >"$TEST_LOG"; COCKPIT_STACK=set "$T/gh/install.sh" >/dev/null 2>&1
  check "stack: a chosen stack is left alone" not_logged "--values-stdin"
  : >"$TEST_LOG"; "$T/gh/install.sh" >/dev/null 2>&1
  check "stack: a cockpit without the option is left alone" not_logged "--values-stdin"
  teardown
}

t_trk_permission_is_asked_once_and_passed_on() {
  setup; out=$("$T/gh/install.sh" --full --no-plugins 2>&1)
  check "allow: no terminal leaves the rule out" logged "trk install.sh --force --no-editable --no-allow-trk"
  check "allow: summary says how to change it" grep -q -- "--allow-trk" <<<"$out"
  check "allow: hx never gets it" not_logged "hx install.sh --force --no-editable --no-allow-trk"
  : >"$TEST_LOG"; "$T/gh/install.sh" --full --no-plugins --force --allow-trk >/dev/null 2>&1
  check "allow: --allow-trk reaches trk" logged "trk install.sh --force --no-editable --allow-trk"
  : >"$TEST_LOG"; "$T/gh/install.sh" --full --no-plugins --force --no-allow-trk >/dev/null 2>&1
  check "allow: --no-allow-trk reaches trk" logged "trk install.sh --force --no-editable --no-allow-trk"
  mkdir -p "$HOME/.claude"; printf '{"permissions": {"allow": ["Bash(trk *)"]}}' >"$HOME/.claude/settings.json"
  : >"$TEST_LOG"; "$T/gh/install.sh" --full --no-plugins --force >/dev/null 2>&1
  check "allow: a rule already there counts as yes" logged "trk install.sh --force --no-editable --allow-trk"
  teardown
}

t_a_dry_run_never_decides_the_trk_permission() {
  setup; "$T/gh/install.sh" --full --dry-run --no-plugins >/dev/null 2>&1
  check "allow dry: no flag, so trk's preview says it would ask" not_logged "allow-trk"
  teardown
}

t_src_moves_the_clones() {
  setup; "$T/gh/install.sh" --full --no-plugins --src "$T/elsewhere" >/dev/null 2>&1
  check "src: clones there" test -d "$T/elsewhere/trk/.git"
  teardown
}

t_differing_skills_stop_the_install_without_force() {
  setup; out=$(DIFFERS=hx "$T/gh/install.sh" --full --no-plugins 2>&1); code=$?
  check "differs: refused" test "$code" = 1
  check "differs: hx not forced" not_logged "hx install.sh --force"
  check "differs: says --force" says "Run again with --force"
  : >"$TEST_LOG"; DIFFERS=hx "$T/gh/install.sh" --full --no-plugins --force >/dev/null 2>&1
  check "differs: --force replaces" logged "hx install.sh --force --no-editable"
  teardown
}

t_a_failing_installer_shows_the_log_tail() {
  setup; out=$(FAILS=trk "$T/gh/install.sh" --full --no-plugins 2>&1); code=$?
  check "fails: exit 1" test "$code" = 1
  check "fails: shows its output" says "boom from trk"
  check "fails: names the log" says "full log:"
  check "fails: hx not attempted" not_logged "hx install.sh --force"
  check "fails: the lock is released" test ! -e "$HOME/.local/state/gatehouse/install.lock"
  teardown
}

t_an_old_clone_is_fetched_from_the_pinned_url() {
  setup; mkdir -p "$SRC"; git clone -q "$T/repos/trk" "$SRC/trk"
  git -C "$SRC/trk" remote set-url origin "$T/nowhere"
  "$T/gh/install.sh" --full --no-plugins --no-hx >/dev/null 2>&1
  check "old origin: still reaches the pin" at_pin trk
  teardown
}

t_dry_run_changes_nothing() {
  setup; out=$("$T/gh/install.sh" --full --dry-run 2>&1)
  check "dry run: nothing cloned" test ! -e "$SRC/trk"
  check "dry run: no real install" not_logged "--force"
  check "dry run: no claude change" not_logged "plugin install"
  check "dry run: says what it would do" says "would clone"
  check "dry run: says nothing changed" says "dry run: nothing was changed"
  teardown
}

t_a_dry_run_on_an_old_clone_says_the_preview_is_not_the_pin() {
  setup; mkdir -p "$SRC"; git clone -q "$T/repos/trk" "$SRC/trk"
  out=$("$T/gh/install.sh" --full --dry-run --no-plugins --no-hx 2>&1)
  check "dry old: says so" says "not $(pin_of trk | cut -c1-7)"
  check "dry old: previews with the tool's own dry run" logged "trk install.sh --dry-run"
  teardown
}

t_local_changes_stop_the_install() {
  setup; "$T/gh/install.sh" --full --no-plugins >/dev/null 2>&1
  echo mine >"$SRC/trk/mine"; : >"$TEST_LOG"
  "$T/gh/install.sh" --full --no-plugins --force >/dev/null 2>&1; code=$?
  check "dirty: refused" test "$code" = 1
  check "dirty: nothing installed" not_logged "install.sh --force"
  teardown
}

t_a_running_install_holds_the_lock() {
  setup; mkdir -p "$HOME/.local/state/gatehouse/install.lock"; echo $$ >"$HOME/.local/state/gatehouse/install.lock/pid"
  out=$("$T/gh/install.sh" --full --no-plugins 2>&1); code=$?
  check "lock: refused" test "$code" = 1
  check "lock: says another install" says "another gatehouse install is running"
  echo 999999 >"$HOME/.local/state/gatehouse/install.lock/pid"
  "$T/gh/install.sh" --full --no-plugins >/dev/null 2>&1; code=$?
  check "stale lock: taken over" test "$code" = 0
  teardown
}

t_missing_herdr_is_named() {
  setup; rm "$T/bin/herdr"
  out=$(PATH="$T/bin:$T/py:/usr/bin:/bin" "$T/gh/install.sh" --full 2>&1); code=$?
  check "no herdr: refused" test "$code" = 1
  check "no herdr: says --no-hx" says "--no-hx"
  teardown
}

t_an_old_python_stops_before_anything_is_cloned() {
  setup
  for c in python3 python3.12 python3.13 python3.14; do
    printf '#!/bin/sh\ncase "$*" in *"version_info < (3, 12)"*) exit 1;; esac\nexec %s "$@"\n' "$(command -v python3)" >"$T/bin/$c"
    chmod +x "$T/bin/$c"
  done
  out=$("$T/gh/install.sh" --full 2>&1); code=$?
  check "old python: refused" test "$code" = 1
  check "old python: says 3.12" says "python 3.12 or newer is required"
  check "old python: nothing cloned" test ! -e "$SRC/trk"
  teardown
}

t_a_missing_or_logged_out_gh_only_warns() {
  setup; rm "$T/bin/gh"
  out=$(PATH="$T/bin:$T/py:/usr/bin:/bin" "$T/gh/install.sh" --full --no-plugins 2>&1); code=$?
  check "no gh: still installs" test "$code" = 0
  check "no gh: says so" says "gh auth login"
  printf '#!/bin/sh\nexit 1\n' >"$T/bin/gh"; chmod +x "$T/bin/gh"
  out=$("$T/gh/install.sh" --full --no-plugins 2>&1)
  check "logged out: says so" says "not logged in"
  teardown
}

t_a_path_without_local_bin_is_named_and_easy_mode_adds_it() {
  setup; touch "$HOME/.zshrc"
  out=$(PATH="$T/bin:$T/py:/usr/bin:/bin" "$T/gh/install.sh" --full --no-plugins 2>&1)
  check "path: warned" says "is not on PATH"
  out=$(PATH="$T/bin:$T/py:/usr/bin:/bin" "$T/gh/install.sh" --full --no-plugins --easy-mode --force 2>&1)
  check "easy: added to .zshrc" grep -qF "$HOME/.local/bin" "$HOME/.zshrc"
  teardown
}

t_quiet_prints_nothing_on_success() {
  setup; out=$("$T/gh/install.sh" --full --quiet --no-plugins 2>&1); code=$?
  check "quiet: succeeds" test "$code" = 0
  check "quiet: silent" test -z "$out"
  teardown
}

t_verify_checks_and_changes_nothing() {
  setup; fake_tool trk "$(pin_of trk)"; fake_tool hx "$(pin_of hx)"
  out=$("$T/gh/install.sh" --full --verify --no-plugins 2>&1); code=$?
  check "verify: trk at pin" says "trk at its pin"
  check "verify: names the watcher" says "the hx watcher"
  check "verify: fails without a running watcher" test "$code" = 1
  check "verify: installed nothing" not_logged "install.sh"
  out=$("$T/gh/install.sh" --full --verify --no-hx --no-plugins 2>&1); code=$?
  check "verify trk only: passes" test "$code" = 0
  check "verify trk only: all passed" says "all checks passed"
  teardown
}

t_uninstall_runs_each_installer() {
  setup; "$T/gh/install.sh" --full --no-plugins >/dev/null 2>&1; : >"$TEST_LOG"
  out=$("$T/gh/install.sh" --full --uninstall 2>&1)
  check "uninstall: trk" logged "trk install.sh --uninstall"
  check "uninstall: hx" logged "hx install.sh --uninstall"
  check "uninstall: clones kept" test -d "$SRC/trk"
  check "uninstall: says how to remove plugins" says "claude plugin uninstall turn-mode@mjfork"
  check "uninstall: says how to remove the clones" says "rm -rf"
  teardown
}

t_bad_options_are_refused() {
  setup; "$T/gh/install.sh" --full --nod-agent >/dev/null 2>&1; code=$?
  check "unknown: exit 2" test "$code" = 2
  "$T/gh/install.sh" --full --src >/dev/null 2>&1; code=$?
  check "missing value: exit 2" test "$code" = 2
  teardown
}

t_run_by_sh_says_to_use_bash() {
  sh -c '[ -n "${BASH_VERSION:-}" ]' && return 0  # sh is bash here (macOS): it runs, which is fine
  setup; out=$(sh "$T/gh/install.sh" --full 2>&1); code=$?
  check "sh: refused" test "$code" = 1
  check "sh: says bash" says "needs bash"
  teardown
}

t_the_real_pins_are_full_commit_ids() {
  check "pins: 40 hex characters" test "$(grep -cE '^commit = "[0-9a-f]{40}"$' "$HERE/versions.toml")" = 3
}

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do "$t"; done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
