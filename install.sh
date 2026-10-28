#!/usr/bin/env bash
#
# gatehouse installer: trk, hx and the workbench Claude Code plugins, at commits known to work together.
#
# One-liner install (with cache buster):
#   curl -fsSL "https://raw.githubusercontent.com/mjfork/gatehouse/main/install.sh?$(date +%s)" | bash
#
# Or from a clone:
#   git clone https://github.com/mjfork/gatehouse && gatehouse/install.sh
#
# Piped, it clones gatehouse into ~/.local/share/gatehouse/gatehouse and runs itself from there. Each
# tool is cloned beside it, checked out at its full commit id in versions.toml (git checks every
# object against that id), and installed by its own installer. `--help` lists the options.
#
# This is a bash script, and must stay parseable by macOS /bin/bash 3.2.
# Keep this block POSIX sh: it runs before anything bash-specific is parsed.
if [ -z "${BASH_VERSION:-}" ]; then
  printf '%s\n' \
    "gatehouse installer: this script needs bash. Pipe it to bash instead, for example:" \
    '  curl -fsSL "https://raw.githubusercontent.com/mjfork/gatehouse/main/install.sh" | bash' >&2
  exit 1
fi
case ":${SHELLOPTS:-}:" in
  *:posix:*) set +o posix ;;
esac

set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

GATEHOUSE_URL=${GATEHOUSE_URL:-https://github.com/mjfork/gatehouse}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
SRC="$DATA_HOME/gatehouse"
BIN_DIR="$HOME/.local/bin"
ORIGINAL_ARGS=("$@")

usage() {
  cat <<EOF
Usage: install.sh [options] [-- hx installer options]

Installs trk, hx and the workbench Claude Code plugins at the commits in versions.toml.
Run it again to update: it skips what is already at its pin.

  --src DIR         where the clones go (default: ~/.local/share/gatehouse)
  --me NAME         your name in trk and hx, for a new store and config (default: your user name)
  --full            add trk and hx to the plugins: stage gates, independent review, programs and
                    routed asks. Without it, only the workbench plugins are installed (the
                    needs-you queue, the footers, cockpit). Later runs keep the level
                    (--no-hx, --me and options after -- imply --full)
  --no-hx           install trk only (hx needs herdr)
  --no-plugins      leave Claude Code's plugins alone
  --plugins LIST    comma-separated workbench plugins (default: the list in versions.toml)
  --force           reinstall everything, and replace installed skills and scripts that differ
                    from the pinned copy (your edits, or an older version); old copies are backed up
  --allow-trk       let Claude Code sessions run trk without a permission prompt: adds
                    Bash(trk *) to ~/.claude/settings.json without asking first
  --no-allow-trk    leave that rule out without asking (with neither, the installer asks)
  --easy-mode       add ~/.local/bin to PATH in ~/.zshrc and ~/.bashrc when it is missing
  --verify          check an existing install and change nothing (paste its output when asking for help)
  --dry-run         print what would happen and change nothing
  --uninstall       remove what was installed; clones, trk's data and config stay
  --verbose         show each tool installer's own output (it always goes to the log)
  --quiet           print errors only
  --no-gum          plain output even when gum is installed
  -h, --help        this text

Options after \`--\` go to hx's installer, e.g. \`install.sh -- --no-sidebar\`.
EOF
}

ALLOW="" LEVEL="" TRK=1 ME="" HX=1 PLUGINS_ON=1 PLUGINS="" FORCE=0 EASY=0 VERIFY=0 DRY=0 UNINSTALL=0 VERBOSE=0 QUIET=0 NO_GUM=0
HX_ARGS=()
need_value() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "install.sh: $1 needs a value (see --help)" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --src) need_value "$@"; SRC=$2; shift ;;
    --me) need_value "$@"; ME=$2; LEVEL=full; shift ;;
    --full) LEVEL=full ;;
    --no-hx) HX=0; LEVEL=full ;;
    --no-plugins) PLUGINS_ON=0 ;;
    --plugins) need_value "$@"; PLUGINS=$2; shift ;;
    --force) FORCE=1 ;;
    --easy-mode) EASY=1 ;;
    --verify) VERIFY=1 ;;
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --verbose) VERBOSE=1 ;;
    --quiet) QUIET=1 ;;
    --no-gum) NO_GUM=1 ;;
    --allow-trk) ALLOW=yes; LEVEL=full ;;
    --no-allow-trk) ALLOW=no; LEVEL=full ;;
    -h|--help) usage; exit 0 ;;
    --) shift; HX_ARGS=("$@"); [ $# -gt 0 ] && LEVEL=full; break ;;
    *) echo "install.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# ═══ Output ═══════════════════════════════════════════════════════════════════

HAS_GUM=0
if [ "$NO_GUM" = 0 ] && command -v gum >/dev/null 2>&1 && [ -t 1 ]; then HAS_GUM=1; fi
COLOR=0
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then COLOR=1; fi

paint() { # paint <ansi code> <text>
  if [ "$COLOR" = 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}
info() { [ "$QUIET" = 1 ] && return 0; if [ "$HAS_GUM" = 1 ]; then gum style --foreground 39 "→ $*"; else echo "$(paint '0;34' '→') $*"; fi; }
ok()   { [ "$QUIET" = 1 ] && return 0; if [ "$HAS_GUM" = 1 ]; then gum style --foreground 42 "✓ $*"; else echo "$(paint '0;32' '✓') $*"; fi; }
warn() { [ "$QUIET" = 1 ] && return 0; if [ "$HAS_GUM" = 1 ]; then gum style --foreground 214 "⚠ $*"; else echo "$(paint '1;33' '⚠') $*"; fi; }
err()  { if [ "$HAS_GUM" = 1 ]; then gum style --foreground 196 "✗ $*" >&2; else echo "$(paint '0;31' '✗') $*" >&2; fi; }
die()  { err "$*"; exit 1; }

# A box around lines, sized to the longest.
draw_box() { # draw_box <ansi code> <line>...
  local color=$1; shift
  local line width=0 len pad border="" i
  for line in "$@"; do len=${#line}; [ "$len" -gt "$width" ] && width=$len; done
  for ((i = 0; i < width + 4; i++)); do border+="═"; done
  echo "$(paint "$color" "╔$border╗")"
  for line in "$@"; do
    pad=$((width - ${#line})); printf -v line '%s%*s' "$line" "$pad" ""
    echo "$(paint "$color" "║")  $line  $(paint "$color" "║")"
  done
  echo "$(paint "$color" "╚$border╝")"
}

banner() {
  [ "$QUIET" = 1 ] && return 0
  if [ "$HAS_GUM" = 1 ]; then
    gum style --border normal --border-foreground 39 --padding "0 1" --margin "1 0" \
      "$(gum style --foreground 42 --bold 'gatehouse installer')" \
      "$(gum style --foreground 245 'trk, hx and the workbench plugins, at commits known to work together')"
  else
    echo
    echo "$(paint '1;32' 'gatehouse installer')"
    echo "$(paint '0;90' 'trk, hx and the workbench plugins, at commits known to work together')"
    echo
  fi
}

# ═══ Bootstrap: piped from curl, clone gatehouse and run from the clone ═══════

SELF=${BASH_SOURCE[0]:-}
if [ -z "$SELF" ] || [ ! -f "$(dirname "$SELF")/versions.toml" ]; then
  command -v git >/dev/null 2>&1 || die "git is required: gatehouse clones its tools with it"
  if [ "$DRY" = 1 ]; then
    # A preview changes nothing, so this clone goes in a temporary folder that is removed after.
    preview=$(mktemp -d)
    info "Cloning gatehouse into a temporary folder for the preview"
    git clone -q "$GATEHOUSE_URL" "$preview/gatehouse" || { rm -rf "$preview"; die "could not clone $GATEHOUSE_URL"; }
    code=0
    bash "$preview/gatehouse/install.sh" ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"} || code=$?
    rm -rf "$preview"
    exit "$code"
  fi
  home="$SRC/gatehouse"
  if [ -d "$home/.git" ]; then
    [ -z "$(git -C "$home" status --porcelain)" ] || die "$home has local changes; commit or stash them first"
    info "Updating gatehouse in $home"
    git -C "$home" fetch -q "$GATEHOUSE_URL" main || die "could not fetch $GATEHOUSE_URL"
    git -C "$home" -c advice.detachedHead=false checkout -q FETCH_HEAD
  else
    info "Cloning gatehouse into $home"
    mkdir -p "$SRC"
    git clone -q "$GATEHOUSE_URL" "$home" || die "could not clone $GATEHOUSE_URL"
  fi
  exec bash "$home/install.sh" ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}
fi
HERE=$(cd "$(dirname "$SELF")" && pwd)

# versions.toml: `pin <repo> <key>` prints one value. The file is plain `[name]` tables of
# `key = "string"` or `key = ["a", "b"]`, read here without tomllib so any Python 3 will do.
pin() {
  python3 -I - "$HERE/versions.toml" "$1" "$2" <<'PY'
import re, sys
path, table, key = sys.argv[1:]
section = None
for line in open(path):
    line = line.split("#", 1)[0].strip()
    found = re.match(r"^\[(.+)\]$", line)
    if found:
        section = found.group(1).strip()
    elif section == table and "=" in line:
        name, value = (part.strip() for part in line.split("=", 1))
        if name == key:
            print(",".join(re.findall(r'"([^"]*)"', value)))
            sys.exit(0)
sys.exit(f"versions.toml has no {key} under [{table}]")
PY
}
url_of() { if [ -n "${GATEHOUSE_REPO_BASE:-}" ]; then echo "$GATEHOUSE_REPO_BASE/$1"; else pin "$1" repo; fi; }

MARKET=$(pin workbench marketplace)
IFS=, read -r -a WANTED <<<"${PLUGINS:-$(pin workbench plugins)}"
RECORD="$STATE_HOME/gatehouse/installed"   # name=commit, for each tool this installer put in place

# The level: "plugins" (herdr and the workbench plugins, the default) or "full" (trk and hx too,
# with --full). A run without --full keeps the level of the last install, so an update never
# drops trk and hx; an install from before levels, with trk recorded, counts as full.
LEVEL_FILE="$STATE_HOME/gatehouse/level"
if [ -z "$LEVEL" ]; then
  LEVEL=$(cat "$LEVEL_FILE" 2>/dev/null || true)
  if [ "$LEVEL" != full ] && [ "$LEVEL" != plugins ]; then
    if [ -s "$RECORD" ]; then LEVEL=full; else LEVEL=plugins; fi
  fi
fi
if [ "$LEVEL" = plugins ]; then
  TRK=0 HX=0
  if [ "$PLUGINS_ON" = 0 ]; then echo "install.sh: without --full there is nothing to install but the plugins, so --no-plugins needs --full" >&2; exit 2; fi
fi

# ═══ Platform and preflight ═══════════════════════════════════════════════════

OS=$(uname -s)
case "$OS" in
  Darwin|Linux) ;;
  *) die "gatehouse runs on Linux and macOS; on Windows, use WSL2" ;;
esac
if [ "$OS" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; then WSL=1; else WSL=0; fi

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required: $2"; }

# trk and hx need Python 3.12 or newer on PATH; their installers look for python3, then python3.14..3.12.
has_python312() {
  local c
  for c in python3 python3.14 python3.13 python3.12; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null && return 0
  done
  return 1
}

preflight() {
  need git "gatehouse clones its tools with it"
  need python3 "it reads versions.toml"
  [ "$TRK" = 1 ] && need uv "trk and hx install with it (https://docs.astral.sh/uv/)"
  [ "$HX" = 1 ] && need herdr "hx opens Spaces and wakes panes in herdr; use --no-hx for trk alone"
  [ "$TRK" = 0 ] && need herdr "the needs-you queue lives in herdr"
  [ "$PLUGINS_ON" = 1 ] && need claude "the workbench plugins install into Claude Code; use --no-plugins to skip"
  if [ "$TRK" = 1 ] && ! has_python312; then
    local hint="install one and put it on PATH"
    [ "$OS" = Darwin ] && hint="macOS's own python3 is $(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null); run: brew install python@3.12"
    die "python 3.12 or newer is required by trk and hx; $hint"
  fi
  [ "$WSL" = 1 ] && warn "WSL detected: gatehouse is untested here"

  # Space: the clones and two Python environments take about 200 MB.
  local parent=$SRC avail
  while [ ! -d "$parent" ]; do parent=$(dirname "$parent"); done
  avail=$(df -Pk "$parent" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$avail" ] && [ "$avail" -lt 307200 ]; then die "less than 300 MB free in $parent"; fi
  [ -w "$parent" ] || die "no write permission in $parent; choose another place with --src"

  # The network. git takes a proxy from HTTPS_PROXY by itself.
  local probe=trk
  [ "$TRK" = 0 ] && probe=workbench
  if [ -z "${GATEHOUSE_REPO_BASE:-}" ] &&
     ! GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 ls-remote -q "$(pin "$probe" repo)" HEAD >/dev/null 2>&1; then
    warn "cannot reach $(pin "$probe" repo); cloning will fail unless the clones are already here"
  fi

  # The GitHub CLI: the program skills and vet use it for repos on GitHub. Azure DevOps repos don't.
  if [ "$TRK" = 0 ]; then return 0; fi
  if ! command -v gh >/dev/null 2>&1; then
    warn "the GitHub CLI (gh) is not installed; for repos on GitHub install it and run: gh auth login"
  elif ! gh auth status >/dev/null 2>&1; then
    warn "the GitHub CLI is not logged in; for repos on GitHub run: gh auth login"
  fi
}

maybe_add_path() {
  case ":$PATH:" in *":$BIN_DIR:"*) return 0 ;; esac
  if [ "$EASY" = 1 ] && [ "$DRY" = 0 ]; then
    local rc updated=0
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [ -e "$rc" ] && [ -w "$rc" ] || continue
      grep -qF "$BIN_DIR" "$rc" || echo "export PATH=\"$BIN_DIR:\$PATH\"" >>"$rc"
      updated=1
    done
    if [ "$updated" = 1 ]; then warn "added $BIN_DIR to PATH in your shell rc files; open a new shell"; return 0; fi
  fi
  warn "$BIN_DIR is not on PATH: add it (or rerun with --easy-mode), or Claude Code sessions won't find trk and hx"
}

# Whether sessions may run trk without a permission prompt. Asked here, on the terminal, because
# trk's installer runs under a spinner with its output in the log. The answer always goes on to it
# as --allow-trk or --no-allow-trk, so it never asks a second time.
TRK_RULE='Bash(trk *)'
TTY=${GATEHOUSE_TTY:-/dev/tty}   # tests point it elsewhere
rule_present() {
  python3 -I -c 'import json, sys
try: allow = json.load(open(sys.argv[1])).get("permissions", {}).get("allow", [])
except Exception: sys.exit(1)
sys.exit(0 if sys.argv[2] in allow else 1)' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$TRK_RULE" 2>/dev/null
}
choose_allow() {
  [ -n "$ALLOW" ] && return 0
  if rule_present; then ALLOW=yes; return 0; fi
  [ "$DRY" = 1 ] && return 0   # trk's own dry run reports that it would ask
  # /dev/tty can exist with no terminal behind it (macOS), so only opening it tells.
  if ! (exec 3<>"$TTY") 2>/dev/null; then ALLOW=no; return 0; fi
  local answer=""
  {
    echo
    echo "Claude Code asks before each command a session runs, and sessions run trk constantly."
    printf 'Let sessions run trk without asking? This adds %s to ~/.claude/settings.json; it covers trk only. [y/N] ' "$TRK_RULE"
  } >"$TTY"
  read -r answer <"$TTY" || answer=""
  case "$answer" in y|Y|yes|YES|Yes) ALLOW=yes ;; *) ALLOW=no ;; esac
}

# ═══ Lock, temp files and the log ═════════════════════════════════════════════

LOCK_DIR="$STATE_HOME/gatehouse/install.lock"
LOCKED=0
TMP=""
LOG=""
cleanup() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  if [ "$LOCKED" = 1 ]; then rm -rf "$LOCK_DIR"; fi
  return 0
}
trap cleanup EXIT

take_lock() {
  mkdir -p "$(dirname "$LOCK_DIR")"
  if mkdir "$LOCK_DIR" 2>/dev/null; then LOCKED=1; echo $$ >"$LOCK_DIR/pid"; return 0; fi
  local old
  old=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$old" ] && ! kill -0 "$old" 2>/dev/null; then
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then LOCKED=1; echo $$ >"$LOCK_DIR/pid"; return 0; fi
  fi
  die "another gatehouse install is running (pid ${old:-unknown}; lock $LOCK_DIR)"
}

start_log() {
  mkdir -p "$STATE_HOME/gatehouse"
  LOG="$STATE_HOME/gatehouse/install-$(date +%Y%m%d-%H%M%S).log"
  : >"$LOG"
  TMP=$(mktemp -d)
}

# Run a command with its output in the log. Shown live with --verbose or a dry run; otherwise a
# spinner (with gum) or one line, and the log's tail if it fails.
run_logged() { # run_logged <title> <command>...
  local title=$1; shift
  echo "\$ $*" >>"$LOG"
  if [ "$VERBOSE" = 1 ] || [ "$DRY" = 1 ]; then
    if [ "$QUIET" = 1 ]; then "$@" >>"$LOG" 2>&1; return $?; fi
    info "$title"
    "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  fi
  local code=0
  if [ "$HAS_GUM" = 1 ] && [ "$QUIET" = 0 ]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >>"$0" 2>&1' "$LOG" "$@" || code=$?
  else
    info "$title"
    "$@" >>"$LOG" 2>&1 || code=$?
  fi
  if [ "$code" != 0 ]; then
    err "$title failed (exit $code). The end of the log:"
    tail -n 25 "$LOG" | sed 's/^/    /' >&2
    err "full log: $LOG"
  fi
  return "$code"
}

# ═══ The tools ════════════════════════════════════════════════════════════════

# Which commit of <name> is installed: what the tool reports (`<name> --version --json`, "commit"),
# else what this installer recorded. Empty when unknown.
installed_commit() {
  local name=$1 found=""
  command -v "$name" >/dev/null 2>&1 || return 0
  found=$("$name" --version --json 2>/dev/null | python3 -I -c 'import json, sys
try: print(json.load(sys.stdin).get("commit") or "")
except Exception: pass' 2>/dev/null || true)
  if [ -z "$found" ] && [ -f "$RECORD" ]; then
    found=$(sed -n "s/^$name=//p" "$RECORD" | tail -n 1)
  fi
  echo "$found"
}

record() { # record <name> <commit>
  [ "$DRY" = 1 ] && return 0
  mkdir -p "$(dirname "$RECORD")"
  { if [ -f "$RECORD" ]; then grep -v "^$1=" "$RECORD" || true; fi; echo "$1=$2"; } >"$TMP/record"
  mv "$TMP/record" "$RECORD"
}

# Clone the repo, or fetch it from the pinned URL (not the clone's own origin, which may be an old
# copy), and check out its pinned commit. Refuses a checkout with local changes.
checkout() {
  local name=$1 url commit dir
  url=$(url_of "$name")
  commit=$(pin "$name" commit)
  dir="$SRC/$name"
  if [ -d "$dir/.git" ]; then
    [ -z "$(git -C "$dir" status --porcelain)" ] || die "$dir has local changes; commit or stash them first"
    if [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ]; then return 0; fi
    if [ "$DRY" = 1 ]; then
      info "would fetch $url into $dir and check out ${commit:0:7}"
      warn "$name: the preview below is of what $dir has checked out now, not ${commit:0:7}"
      return 0
    fi
    run_logged "$name: fetching ${commit:0:7}" git -C "$dir" fetch -q "$url" "+refs/heads/*:refs/remotes/gatehouse/*" || exit 1
  else
    if [ "$DRY" = 1 ]; then info "would clone $url into $dir at ${commit:0:7}"; return 0; fi
    mkdir -p "$SRC"
    run_logged "$name: cloning $url" git clone -q "$url" "$dir" || exit 1
  fi
  git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null ||
    die "$name: $commit is not in $url; is versions.toml newer than the published repo?"
  git -C "$dir" -c advice.detachedHead=false checkout -q "$commit"
}

# trk's and hx's installers need --force to replace an installed copy, but --force also replaces
# skills and scripts that differ from the repo's, which may be the user's edits. So preview first,
# and go on with --force only when nothing would be replaced, or the user said --force.
# Sets STATUS_<name> to installed, updated, current, previewed or failed.
install_tool() { # install_tool <name> <installer args>...
  local name=$1; shift
  local commit was status
  commit=$(pin "$name" commit)
  was=$(installed_commit "$name")
  checkout "$name"
  if [ "$FORCE" = 0 ] && [ "$was" = "$commit" ]; then
    ok "$name is already at ${commit:0:7}"
    eval "STATUS_$name=current"; return 0
  fi
  if [ "$DRY" = 1 ]; then
    if [ -x "$SRC/$name/install.sh" ]; then run_logged "$name: what its installer would do" "$SRC/$name/install.sh" --dry-run "$@" || true
    else info "would run $name's installer: install.sh $*"; fi
    eval "STATUS_$name=previewed"; return 0
  fi
  if [ "$FORCE" = 0 ]; then
    "$SRC/$name/install.sh" --dry-run "$@" >"$TMP/preview" 2>&1 || true
    if grep -qE "would refuse here|with --force to replace" "$TMP/preview"; then
      grep -E "differ|not ours" "$TMP/preview" >&2 || true
      eval "STATUS_$name=failed"
      die "$name: the skills or scripts above differ from the pinned copy (an older version, or your edits). Nothing was changed. Run again with --force to replace them; the old copies are backed up."
    fi
  fi
  if run_logged "$name: installing ${commit:0:7}" "$SRC/$name/install.sh" --force "$@"; then
    record "$name" "$commit"
    if [ -n "$was" ]; then status=updated; else status=installed; fi
    ok "$name $status at ${commit:0:7}"
    eval "STATUS_$name=$status"
  else
    eval "STATUS_$name=failed"
    exit 1
  fi
}

PLUGIN_LINES=()
install_plugins() {
  checkout workbench
  local source_line plugin installed
  source_line=$(claude plugin marketplace list 2>/dev/null | awk -v m="$MARKET" '$0 ~ "❯ "m"$" {getline; print; exit}')
  if [ -z "$source_line" ]; then
    if [ "$DRY" = 1 ]; then info "would add $SRC/workbench as the $MARKET marketplace"
    else run_logged "plugins: adding the $MARKET marketplace" claude plugin marketplace add "$SRC/workbench" || exit 1; fi
  elif [[ $source_line == *"$SRC/workbench"* ]]; then
    if [ "$DRY" = 1 ]; then info "would update the $MARKET marketplace"
    else run_logged "plugins: updating the $MARKET marketplace" claude plugin marketplace update "$MARKET" || exit 1; fi
  else
    warn "the $MARKET marketplace already comes from elsewhere (${source_line#*Source: }); leaving it, so its plugins follow that, not the pin"
  fi
  installed=$(claude plugin list 2>/dev/null || true)
  for plugin in "${WANTED[@]}"; do
    if grep -qF "$plugin@$MARKET" <<<"$installed"; then
      if [ "$DRY" = 1 ]; then info "would update $plugin@$MARKET"; continue; fi
      if run_logged "plugins: updating $plugin" claude plugin update "$plugin@$MARKET"; then PLUGIN_LINES+=("  $plugin: updated"); else PLUGIN_LINES+=("  $plugin: failed (see the log)"); fi
    else
      if [ "$DRY" = 1 ]; then info "would install $plugin@$MARKET"; continue; fi
      if run_logged "plugins: installing $plugin" claude plugin install "$plugin@$MARKET"; then PLUGIN_LINES+=("  $plugin: installed"); else PLUGIN_LINES+=("  $plugin: failed (see the log)"); fi
    fi
  done
  set_default_stack
}

# cockpit's `stack` option picks the skill stack its workers build with. Claude Code leaves an
# unsaved option unsubstituted in the skill, so write "auto" (the first installed of mattpocock
# and superpowers, else Claude Code's own steps) when the option exists and nothing is saved.
# A value the person chose is never touched; a cockpit without the option is left alone.
set_default_stack() {
  case " ${WANTED[*]} " in *" cockpit "*) ;; *) return 0 ;; esac
  [ "$DRY" = 1 ] && { info "would set cockpit's build stack to auto, if it has the option and none is saved"; return 0; }
  local state
  state=$(claude plugin configure "cockpit@$MARKET" --json 2>/dev/null | python3 -I -c 'import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
if "stack" in d.get("schema", {}): print("unset" if "stack" in d.get("unconfigured", []) else "set")' 2>/dev/null || true)
  [ "$state" = unset ] || return 0
  echo "\$ claude plugin configure cockpit@$MARKET --values-stdin <<< {\"stack\":\"auto\"}" >>"$LOG"
  if printf '{"stack":"auto"}' | claude plugin configure "cockpit@$MARKET" --values-stdin >>"$LOG" 2>&1; then
    PLUGIN_LINES+=("  cockpit builds with: auto (name a stack in the prompt, or change it in /config)")
  fi
}

# ═══ --verify: check an install and change nothing ════════════════════════════

VERIFY_FAILED=0
check() { # check <status> <label> [detail]
  if [ "$1" = 0 ]; then ok "$2"; else err "$2${3:+: $3}"; VERIFY_FAILED=1; fi
}

verify() {
  local name commit was plugin installed
  echo "gatehouse $(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo '(not a clone)') on $OS $(uname -m)$([ "$WSL" = 1 ] && echo ' (WSL)' || true)"
  echo "level: $LEVEL"
  if [ "$TRK" = 1 ]; then
    if has_python312; then check 0 "Python 3.12 or newer on PATH"; else check 1 "Python 3.12 or newer on PATH"; fi
  fi
  for name in trk hx; do
    if [ "$name" = trk ] && [ "$TRK" = 0 ]; then continue; fi
    if [ "$name" = hx ] && [ "$HX" = 0 ]; then continue; fi
    commit=$(pin "$name" commit)
    if ! command -v "$name" >/dev/null 2>&1; then check 1 "$name on PATH" "not found (is $BIN_DIR on PATH?)"; continue; fi
    was=$(installed_commit "$name")
    if [ "$was" = "$commit" ]; then check 0 "$name at its pin ${commit:0:7}"
    elif [ -z "$was" ]; then warn "$name is installed, but its commit is unknown (pin ${commit:0:7})"
    else check 1 "$name at its pin ${commit:0:7}" "installed is ${was:0:7}"; fi
  done
  if [ "$HX" = 1 ] || [ "$TRK" = 0 ]; then
    if command -v herdr >/dev/null 2>&1; then check 0 "herdr on PATH"; else check 1 "herdr on PATH"; fi
  fi
  if [ "$HX" = 1 ]; then
    if [ "$OS" = Darwin ]; then
      if launchctl print "gui/$(id -u)/com.hx.watch" 2>/dev/null | grep -q "state = running"; then check 0 "the hx watcher is running (launchd com.hx.watch)"
      else check 1 "the hx watcher is running (launchd com.hx.watch)"; fi
    else
      if systemctl --user is-active --quiet hx 2>/dev/null; then check 0 "the hx watcher is running (systemd --user hx)"
      else check 1 "the hx watcher is running (systemd --user hx)"; fi
    fi
  fi
  if [ "$PLUGINS_ON" = 1 ]; then
    if command -v claude >/dev/null 2>&1; then
      installed=$(claude plugin list 2>/dev/null || true)
      for plugin in "${WANTED[@]}"; do
        if grep -qF "$plugin@$MARKET" <<<"$installed"; then check 0 "plugin $plugin@$MARKET"; else check 1 "plugin $plugin@$MARKET"; fi
      done
    else
      check 1 "Claude Code on PATH"
    fi
  fi
  if [ "$TRK" = 1 ]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then ok "GitHub CLI logged in"
    else warn "GitHub CLI missing or logged out (needed for repos on GitHub)"; fi
    if rule_present; then ok "sessions run trk without a permission prompt"
    else warn "sessions ask permission for each trk command (install.sh --allow-trk stops that)"; fi
    case ":$PATH:" in *":$BIN_DIR:"*) check 0 "$BIN_DIR on PATH" ;; *) check 1 "$BIN_DIR on PATH" ;; esac
  fi
  if [ "$VERIFY_FAILED" = 0 ]; then ok "all checks passed"
  else err "some checks failed; rerun install.sh to repair, or paste this output when asking for help"; fi
  return "$VERIFY_FAILED"
}

# ═══ Main ═════════════════════════════════════════════════════════════════════

if [ "$VERIFY" = 1 ]; then
  if verify; then exit 0; else exit 1; fi
fi

banner
ME_ARGS=()
[ -n "$ME" ] && ME_ARGS=(--me "$ME")

if [ "$UNINSTALL" = 1 ]; then
  take_lock; start_log
  DRYFLAG=()
  [ "$DRY" = 1 ] && DRYFLAG=(--dry-run)
  if [ "$HX" = 1 ] && [ -x "$SRC/hx/install.sh" ]; then run_logged "hx: uninstalling" "$SRC/hx/install.sh" --uninstall ${DRYFLAG[@]+"${DRYFLAG[@]}"} || exit 1; fi
  if [ "$TRK" = 1 ] && [ -x "$SRC/trk/install.sh" ]; then run_logged "trk: uninstalling" "$SRC/trk/install.sh" --uninstall ${DRYFLAG[@]+"${DRYFLAG[@]}"} || exit 1; fi
  [ "$DRY" = 1 ] || rm -f "$RECORD" "$LEVEL_FILE"
  lines=("gatehouse: uninstalled" ""
         "Kept: the clones in $SRC, trk's data (~/.local/share/trk) and your config."
         "The Claude Code plugins stay; remove them with:")
  for plugin in "${WANTED[@]}"; do lines+=("  claude plugin uninstall $plugin@$MARKET"); done
  lines+=("  claude plugin marketplace remove $MARKET" "Remove the clones with:  rm -rf \"$SRC\"")
  [ "$QUIET" = 1 ] || draw_box '0;33' "${lines[@]}"
  exit 0
fi

preflight
[ "$TRK" = 1 ] && choose_allow
ALLOW_ARGS=()
if [ "$ALLOW" = yes ]; then ALLOW_ARGS=(--allow-trk); elif [ "$ALLOW" = no ]; then ALLOW_ARGS=(--no-allow-trk); fi
take_lock
start_log
info "clones: $SRC · log: $LOG"

STATUS_trk=skipped STATUS_hx=skipped
if [ "$TRK" = 1 ]; then install_tool trk --no-editable ${ME_ARGS[@]+"${ME_ARGS[@]}"} ${ALLOW_ARGS[@]+"${ALLOW_ARGS[@]}"}; fi
if [ "$HX" = 1 ]; then
  install_tool hx --no-editable ${ME_ARGS[@]+"${ME_ARGS[@]}"} ${HX_ARGS[@]+"${HX_ARGS[@]}"}
fi
if [ "$PLUGINS_ON" = 1 ]; then install_plugins; fi
if [ "$TRK" = 1 ]; then maybe_add_path; fi

if [ "$DRY" = 1 ]; then ok "dry run: nothing was changed"; exit 0; fi
echo "$LEVEL" >"$LEVEL_FILE"

lines=("gatehouse: done" "")
if [ "$TRK" = 0 ]; then
  lines+=("level      the plugins: the needs-you queue, the footers and cockpit (no trk or hx)")
else
  lines+=("trk        $STATUS_trk at $(pin trk commit | cut -c1-7)")
  if [ "$HX" = 1 ]; then lines+=("hx         $STATUS_hx at $(pin hx commit | cut -c1-7)"); else lines+=("hx         skipped (--no-hx)"); fi
fi
if [ "$PLUGINS_ON" = 1 ]; then
  lines+=("plugins    workbench $(pin workbench commit | cut -c1-7)")
  if [ ${#PLUGIN_LINES[@]} -gt 0 ]; then lines+=("${PLUGIN_LINES[@]}"); fi
else
  lines+=("plugins    skipped (--no-plugins)")
fi
if [ "$TRK" = 1 ]; then
  if [ "$ALLOW" = yes ]; then lines+=("trk        runs without a permission prompt")
  else lines+=("trk        asks permission each time; to stop that: $HERE/install.sh --allow-trk"); fi
fi
lines+=("" "Check it:   $HERE/install.sh --verify")
if [ "$TRK" = 0 ]; then
  lines+=("Next:       restart Claude Code in herdr; when a session needs you, ⚑ N shows in every footer"
          "Add more:   $HERE/install.sh --full adds trk and hx: gates, routed asks and the fleet")
else
  lines+=("Next:       open Claude Code in herdr and run /trk-create-program")
fi
lines+=("Where:      clones in $SRC"
        "Log:        $LOG"
        "Uninstall:  $HERE/install.sh --uninstall")
[ "$QUIET" = 1 ] || draw_box '0;32' "${lines[@]}"
