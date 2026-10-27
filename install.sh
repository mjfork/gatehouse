#!/usr/bin/env bash
# Install trk, hx and the workbench Claude Code plugins at the commits in versions.toml.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Clones (or updates) each repo under the source folder, checks it out at the commit in
versions.toml, and runs that repo's own installer. Then installs the workbench plugins into
Claude Code from the workbench clone, so they are pinned too.

  --src DIR         where the repos go (default: ~/src)
  --me NAME         your name in trk and hx, for a new store and config (default: your user name)
  --no-hx           install trk only (hx needs herdr)
  --no-plugins      leave Claude Code's plugins alone
  --plugins LIST    comma-separated workbench plugins (default: the list in versions.toml)
  --force           replace installed skills and scripts that differ from the pinned copy (an
                    older version, or your edits); the old copies are backed up
  --dry-run         print what would happen and change nothing
  --uninstall       run each repo's installer with --uninstall; clones and data stay
  -h, --help        this text

Options after `--` go to hx's installer, e.g. `./install.sh -- --no-sidebar`.
EOF
}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC="$HOME/src"
ME="" HX=1 PLUGINS_ON=1 PLUGINS="" FORCE=0 DRY=0 UNINSTALL=0
HX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC=${2:?--src needs a folder}; shift ;;
    --me) ME=${2:?--me needs a name}; shift ;;
    --no-hx) HX=0 ;;
    --no-plugins) PLUGINS_ON=0 ;;
    --plugins) PLUGINS=${2:?--plugins needs a list}; shift ;;
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; HX_ARGS=("$@"); break ;;
    *) echo "install.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "install.sh: $*" >&2; exit 1; }
say() { echo "• $*"; }
run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }

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

need() { command -v "$1" >/dev/null || die "$1 is required: $2"; }
need git "every repo is cloned with it"
need python3 "it reads versions.toml"
need uv "trk and hx install with it (https://docs.astral.sh/uv/)"
[ "$HX" = 1 ] && need herdr "hx opens Spaces and wakes panes in herdr; use --no-hx for trk alone"
[ "$PLUGINS_ON" = 1 ] && need claude "the workbench plugins install into Claude Code; use --no-plugins to skip"
# trk and hx need Python 3.12 or newer on PATH; their installers look for python3, then python3.14..3.12.
has_python312() {
  local c
  for c in python3 python3.14 python3.13 python3.12; do
    command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null && return 0
  done
  return 1
}
if [ "$UNINSTALL" != 1 ] && ! has_python312; then
  hint="install one and put it on PATH"
  [ "$(uname -s)" = Darwin ] && hint="macOS's own python3 is $(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null); run: brew install python@3.12"
  die "python 3.12 or newer is required by trk and hx; $hint"
fi

# The program skills and vet use the GitHub CLI for repos on GitHub; a repo elsewhere (Azure DevOps)
# doesn't need it, so this only warns.
if [ "$UNINSTALL" != 1 ]; then
  if ! command -v gh >/dev/null; then
    say "note: the GitHub CLI (gh) is not installed; for repos on GitHub install it and run: gh auth login"
  elif ! gh auth status >/dev/null 2>&1; then
    say "note: the GitHub CLI is not logged in; for repos on GitHub run: gh auth login"
  fi
fi

url_of() { if [ -n "${GATEHOUSE_REPO_BASE:-}" ]; then echo "$GATEHOUSE_REPO_BASE/$1"; else pin "$1" repo; fi; }

# Clone the repo, or fetch it from the pinned URL (not the clone's own origin, which may be an old
# copy), and check out its pinned commit. Refuses a checkout with local changes.
checkout() {
  local name=$1 url commit dir
  url=$(url_of "$name")
  commit=$(pin "$name" commit)
  dir="$SRC/$name"
  if [ -d "$dir/.git" ]; then
    [ -z "$(git -C "$dir" status --porcelain)" ] || die "$dir has local changes; commit or stash them first"
    say "$name: fetching $url into $dir"
    run git -C "$dir" fetch -q "$url" "+refs/heads/*:refs/remotes/gatehouse/*"
    if [ "$DRY" = 1 ] && [ "$(git -C "$dir" rev-parse HEAD)" != "$(git -C "$dir" rev-parse -q --verify "$commit^{commit}" 2>/dev/null)" ]; then
      say "$name: (dry run) the preview below runs on what $dir has checked out now, not on $commit"
    fi
  else
    say "$name: cloning $url into $dir"
    run mkdir -p "$SRC"
    run git clone -q "$url" "$dir"
  fi
  if [ "$DRY" != 1 ]; then
    git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null ||
      die "$name: $commit is not in $url; is versions.toml newer than the published repo?"
  fi
  say "$name: checking out $commit"
  run git -C "$dir" -c advice.detachedHead=false checkout -q "$commit"
}

installer() {
  local name=$1; shift
  if [ "$DRY" = 1 ] && [ ! -d "$SRC/$name" ]; then echo "  would run: $SRC/$name/install.sh $*"; return; fi
  (cd "$SRC/$name" && ./install.sh "$@")
}

# trk's and hx's installers need --force to replace an installed copy, but --force also replaces
# skills and scripts that differ from the repo's, which may be the user's edits. So preview first,
# and go on with --force only when nothing would be replaced, or the user said --force.
pinned_install() {
  local name=$1; shift
  if [ "$DRY" = 1 ]; then installer "$name" --dry-run "$@"; return; fi
  if [ "$FORCE" != 1 ] && installer "$name" --dry-run "$@" 2>&1 | grep -qE "would refuse here|with --force to replace"; then
    installer "$name" --dry-run "$@" 2>&1 | grep -E "differ|not ours" >&2 || true
    die "$name: the skills or scripts above differ from the pinned copy (an older version, or your edits). Nothing was changed. Run again with --force to replace them; the old copies are backed up."
  fi
  installer "$name" --force "$@"
}

ME_ARGS=()
[ -n "$ME" ] && ME_ARGS=(--me "$ME")
DRYFLAG=""
[ "$DRY" = 1 ] && DRYFLAG=--dry-run
MARKET=$(pin workbench marketplace)
IFS=, read -r -a WANTED <<<"${PLUGINS:-$(pin workbench plugins)}"

if [ "$UNINSTALL" = 1 ]; then
  [ "$HX" = 1 ] && [ -d "$SRC/hx" ] && installer hx --uninstall ${DRYFLAG:+"$DRYFLAG"}
  [ -d "$SRC/trk" ] && installer trk --uninstall ${DRYFLAG:+"$DRYFLAG"}
  say "uninstalled; the clones in $SRC, trk's store and your config were left alone"
  say "the Claude Code plugins stay; to remove them:"
  for plugin in "${WANTED[@]}"; do echo "    claude plugin uninstall $plugin@$MARKET"; done
  echo "    claude plugin marketplace remove $MARKET"
  exit 0
fi

checkout trk
pinned_install trk --no-editable "${ME_ARGS[@]+"${ME_ARGS[@]}"}"

if [ "$HX" = 1 ]; then
  checkout hx
  pinned_install hx --no-editable "${ME_ARGS[@]+"${ME_ARGS[@]}"}" "${HX_ARGS[@]+"${HX_ARGS[@]}"}"
fi

if [ "$PLUGINS_ON" = 1 ]; then
  # The marketplace is the workbench clone at its pin, so the plugins hold still with the rest.
  checkout workbench
  source_line=$(claude plugin marketplace list 2>/dev/null | awk -v m="$MARKET" '$0 ~ "❯ "m"$" {getline; print; exit}')
  if [ -z "$source_line" ]; then
    say "plugins: adding the $MARKET marketplace from $SRC/workbench"
    run claude plugin marketplace add "$SRC/workbench"
  elif [[ $source_line == *"$SRC/workbench"* ]]; then
    say "plugins: updating the $MARKET marketplace"
    run claude plugin marketplace update "$MARKET"
  else
    say "plugins: the $MARKET marketplace already comes from elsewhere (${source_line#*Source: }); leaving it, so its plugins follow that, not the pin"
  fi
  installed=$(claude plugin list 2>/dev/null || true)
  for plugin in "${WANTED[@]}"; do
    if grep -qF "$plugin@$MARKET" <<<"$installed"; then
      say "plugins: updating $plugin@$MARKET"
      run claude plugin update "$plugin@$MARKET"
    else
      say "plugins: installing $plugin@$MARKET"
      run claude plugin install "$plugin@$MARKET"
    fi
  done
fi

[ "$DRY" = 1 ] && { say "dry run: nothing was changed"; exit 0; }
echo
say "installed: trk ${TRK_PIN:=$(pin trk commit)}"
[ "$HX" = 1 ] && say "installed: hx $(pin hx commit)"
[ "$PLUGINS_ON" = 1 ] && say "installed: workbench plugins ${WANTED[*]} at $(pin workbench commit)"
cat <<EOF

Check it worked:
  trk --version
$([ "$HX" = 1 ] && echo "  hx reconcile --dry-run")
$([ "$PLUGINS_ON" = 1 ] && echo "  claude plugin list")

What went where: "What gets installed, and where" in $HERE/README.md
EOF
