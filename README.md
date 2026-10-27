# gatehouse

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Run many Claude Code agents at once, and see only the decisions that need you.**

```bash
git clone https://github.com/mjfork/gatehouse ~/src/gatehouse && ~/src/gatehouse/install.sh
```

Linux and macOS · needs [herdr](https://herdr.dev), [Claude Code](https://claude.com/claude-code),
[uv](https://docs.astral.sh/uv/) and Python 3.12+ · [prerequisites](#install)

</div>

## TL;DR

**The problem:** with six Claude Code sessions running, you're the bottleneck in the wrong way. One
of them has been sitting on a question for forty minutes in a pane you weren't looking at. Another
says "done", and you have to read the diff to find out whether it is. Your attention goes to
checking on agents instead of deciding things.

**The solution:** gatehouse sets up three tools that change who waits for whom:
- Agents work tickets from a tracker.
- The tracker's gates refuse "done" without evidence.
- When an agent needs a decision, the question comes to you, sorted by how much work it holds up.
- You answer in a word, and the agent that asked carries on.

### Why use gatehouse?

| | What you get |
|---|---|
| **Questions come to you** | An agent that needs a decision opens an *ask*. It shows as `⚑ 1` in every session's footer and in herdr's sidebar, so you never go pane-hunting. |
| **"Done" means proven** | A ticket can't move from built to merged to verified until the PR, a passing test run and an independent review are on record. |
| **Your answer wakes the agent** | You answer, and the asking session gets a one-line note and continues. It never types over you: the note waits until the pane is idle and its input box is empty. |
| **Work keeps moving around you** | An open ask blocks only the work that depends on it, and every other ticket stays on the ready list. |
| **No babysitting cost** | The router wakes on the tracker's change feed: no polling, and no model runs in routine operation. |
| **You can see each session** | Footers show prompt-cache time left, what fills the context, and your heaviest sessions, so you know where the money and the context go. |

### Quick example

```bash
# Write a ticket: what happens now, what should happen, how we'll know
trk new work-item "Fix the flaky login test" --form self-contained --repo ~/src/myapp \
  --section current-behaviour=@current.md --section desired-behaviour=@desired.md \
  --criterion "The login test passes 50 runs in a row"

# Run it: a herdr Space, a fresh worktree, a Claude Code session that claims the ticket
hx start tr-abc12

# Later: ⚑ 1 in your footer. See what's waiting, and answer it
trk waiting
trk answer tr-ask34 --outcome "Retry, don't raise the timeout" --answer -

# The session resumes. The ticket can't close until its evidence is in
trk show tr-abc12
```

## Design philosophy

1. **Evidence over trust.** An agent saying it's finished is a claim; a passing test tied to a
   commit is evidence. Gates read the evidence.
2. **A question is a work item.** Asks live in the tracker, block exactly what depends on them, and
   have an owner and an answer on record. A question in a chat scrollback has none of that.
3. **Interrupt the person, never the typing.** Asks reach you; answers reach agents. Nothing is
   typed into a pane you're using.
4. **Plumbing, not prompts.** gatehouse works under whatever skills and prompts you already use. It
   adds no agent persona and no prompt library.
5. **One set, tested together.** The three tools are pinned to commits that passed together, and
   you upgrade them as a set.

## How it compares

| | gatehouse | herdr alone | An issue tracker (GitHub Issues, Linear) |
|---|---|---|---|
| Runs many agent sessions side by side | ✅ via herdr | ✅ | ❌ |
| Work sized for one agent session, with a ready list | ✅ | ❌ | ⚠️ by convention |
| Gates that need evidence before "done" | ✅ | ❌ | ❌ |
| Agent questions as tracked, blocking items | ✅ asks | ❌ | ⚠️ as comments |
| An answer wakes the asking session | ✅ | ❌ | ❌ |
| Cache and context visible per session | ✅ | ❌ | ❌ |
| Setup | one installer | one install | a hosted account |

**Use gatehouse when** you run several Claude Code sessions for hours and want to spend your
attention on decisions, not on checking.

**It's not the best fit when** you run one session at a time, you don't use herdr, or your team
needs a shared hosted tracker. trk is one SQLite file per machine.

## Install

**Prerequisites:**

| Needs | Check | Get it |
|---|---|---|
| git | `git --version` | preinstalled on most systems |
| Python 3.12 or newer, on PATH | `python3.12 --version` | macOS: `brew install python@3.12` (the system `python3` is 3.9) |
| uv | `uv --version` | `brew install uv`, or [docs.astral.sh/uv](https://docs.astral.sh/uv/) |
| herdr | `herdr --version` | [herdr.dev](https://herdr.dev) |
| Claude Code, logged in | `claude --version` | [claude.com/claude-code](https://claude.com/claude-code) |

On a Mac, all at once: `brew install uv python@3.12`, then herdr and Claude Code.

**Install:**

```bash
git clone https://github.com/mjfork/gatehouse ~/src/gatehouse
cd ~/src/gatehouse
./install.sh --dry-run      # shows every step and changes nothing
./install.sh
```

The installer:
1. clones trk, hx and workbench into `~/src` and checks each out at its commit in
   [`versions.toml`](versions.toml);
2. runs each repo's own installer, which puts the `trk` and `hx` commands on your PATH, creates
   trk's store under your name, installs the skills and hooks Claude Code uses, and starts the hx
   watcher (systemd on Linux, launchd on macOS);
3. adds the workbench clone to Claude Code as the `mjfork` plugin marketplace and installs
   `cockpit`, `ctx-bar`, `cache-timer`, `herdr-jump` and `turn-mode`, pinned like the rest.

You can run it again at any time: each step skips work that's already done.

**Check it worked:**

```bash
trk --version
hx reconcile --dry-run      # the watcher sees your store and would take no wrong action
claude plugin list          # the five workbench plugins
```

Then open a Claude Code session in herdr. Its footer shows the cache timer and a `⚑` count.

**On Windows**, use WSL2 (untested). herdr and the installers are bash and Unix.

## Quick start: your first ticket

1. **Describe the work.** Write what happens today and what should happen:
   ```bash
   echo "The login test fails about one run in ten." > current.md
   echo "The login test passes every run." > desired.md
   ```
2. **File it** against one of your repos. trk prints the new ticket's id:
   ```bash
   trk new work-item "Fix the flaky login test" --form self-contained --repo ~/src/myapp \
     --section current-behaviour=@current.md --section desired-behaviour=@desired.md \
     --criterion "The login test passes 50 runs in a row"
   ```
3. **Start it:** `hx start <id>`. A herdr Space opens, and a Claude Code session claims the ticket
   in a fresh worktree.
4. **Get on with something else.** When the session needs you, `⚑ 1` appears in your footers and
   the ask shows in herdr's sidebar. Click it and answer.
5. **Watch it finish.** The session works the ticket through `framed → specd → built → merged →
   verified`, recording evidence at each gate. hx closes the Space 10 minutes after the ticket
   closes.

trk's [quickstart](https://github.com/mjfork/trk#quickstart) goes deeper on gates and evidence,
and hx's [quickstart](https://github.com/mjfork/hx#quickstart) on asks and Spaces.

## Commands

### `install.sh`

| Option | Does |
|---|---|
| `--dry-run` | Print every step and change nothing |
| `--src DIR` | Where the repos go (default `~/src`) |
| `--me NAME` | Your name in trk and hx, for a new store (default: your user name) |
| `--no-hx` | trk only; no herdr needed |
| `--no-plugins` | Leave Claude Code's plugins alone |
| `--plugins LIST` | Choose the workbench plugins, e.g. `--plugins cache-timer,herdr-jump` |
| `--force` | Replace installed skills that differ from the pinned copy (old copies are backed up) |
| `--uninstall` | Run each repo's uninstaller; your clones and data stay |
| `-- <args>` | Pass options to hx's installer, e.g. `./install.sh -- --no-sidebar` |

### The everyday commands

| Command | Does |
|---|---|
| `trk ready` | What can be started now |
| `trk tree` | Your programs, projects and tickets |
| `trk waiting` | Asks waiting on you, most urgent first |
| `trk answer <ask> --outcome "…" --answer -` | Answer an ask (the details come from stdin) |
| `trk show <id>` | An item, its stage, evidence and asks |
| `hx start <id>` | Run a ticket in its own herdr Space |
| `/jump`, `/needs-me` | In Claude Code: go to any pane, or to the next one waiting on you |
| `/cockpit:implement-with-herdr <spec>` | Fan a spec's tickets across parallel sessions |
| `/vet:map` | Review an agent's PR by its decisions before you merge |

Every trk and hx command takes `--help`.

## Configuration

[`versions.toml`](versions.toml) is the one file gatehouse reads:

```toml
[trk]
repo = "https://github.com/mjfork/trk"
commit = "…"              # the full hash; every repo is checked out at its pin

[workbench]
repo = "https://github.com/mjfork/workbench"
commit = "…"
marketplace = "mjfork"    # the name the plugins install under
plugins = ["cockpit", "ctx-bar", "cache-timer", "herdr-jump", "turn-mode"]
```

Each tool keeps its own settings: trk's store is `~/.local/share/trk`, hx's config is
`~/.config/hx`, and the plugins have settings in Claude Code. See each repo's README.

## Architecture

```
            ┌──────────── you ────────────┐
            │ herdr sidebar · footer ⚑ ·  │
            │ terminal                    │
            └──────▲───────────────┬──────┘
          asks     │               │ answers
                   │               ▼
 ┌────────┐ change feed + JSON ┌────────┐  herdr CLI   ┌──────────────────────────┐
 │  trk   │◀──────────────────▶│   hx   │─────────────▶│ herdr: Spaces and panes  │
 │ work,  │                    │ router │  wakes panes │ running Claude Code      │
 │ gates, │◀───── trk CLI ─────┤        │              │ sessions with workbench  │
 │ asks   │  (sessions claim,  └───┬────┘              │ plugins in their footers │
 └────────┘   record evidence,     │ needs-you queue   └──────────────────────────┘
              open asks)           ▼
                            workbench herdr-jump (⚑ N)
```

| Part | What it does |
|---|---|
| [trk](https://github.com/mjfork/trk) | The tracker: programs, specs, tickets, claims, stage gates, asks and evidence. A CLI over one SQLite file per machine, with an append-only journal. |
| [hx](https://github.com/mjfork/hx) | The router: a background watcher that delivers asks and wakes askers. `hx start` runs a ticket in its own Space. |
| [workbench](https://github.com/mjfork/workbench) | Claude Code plugins: the footer instruments, the parallel-agent workflows, and `vet`. |

[docs/how-it-fits.md](docs/how-it-fits.md) covers what each part reads and writes, and the written
contracts between them.

## Updating

```bash
cd ~/src/gatehouse && git pull && ./install.sh
```

trk and hx are installed as copies, so a `git pull` inside `~/src/trk` changes nothing until you
rerun the installer. That way, the set you run is always one that was tested together.

## Troubleshooting

### `python 3.12 or newer is required`
macOS's `python3` is 3.9. Run `brew install python@3.12`, open a new shell, and run the installer
again. A Python that only uv manages doesn't count: the installers look on your PATH.

### `herdr is required` / `claude is required`
Install it and make sure it's on your PATH. For the tracker alone, without herdr, run
`./install.sh --no-hx --no-plugins`.

### `… Nothing was changed. Run again with --force …`
Your installed skills differ from the new pinned copies. After an update this is normal: the older
installed copy counts as different. If you didn't edit those skills, run `./install.sh --force`.
The old copies are backed up either way.

### `~/src/trk has local changes; commit or stash them first`
The installer won't overwrite your edits in a clone. Commit or stash them, or install to a fresh
folder with `--src DIR`.

### `hx: command not found` or `trk: command not found`
uv's tool folder isn't on your PATH. Run `uv tool update-shell` and open a new shell.

### Asks don't show up
Check the watcher is running:
- **Linux:** `systemctl --user status hx`
- **macOS:** `launchctl print gui/$(id -u)/com.hx.watch`

Then look at `~/.local/state/hx/watch.log`. Restart it with `systemctl --user restart hx`, or on
macOS `launchctl kickstart -k gui/$(id -u)/com.hx.watch`.

### The plugins follow GitHub, not the pin
You already had an `mjfork` marketplace from another source, and the installer left it alone. To
pin it, remove it with `claude plugin marketplace remove mjfork` and run the installer again.

## Limitations

- **One machine.** trk keeps one store per machine. There's no shared server, and no team view of
  the same tickets.
- **herdr is required** for routing asks, Spaces and most footer instruments. Without herdr you
  get the tracker alone.
- **Claude Code only.** The sessions, skills, hooks and plugins are built for Claude Code. Other
  agents can drive trk from its CLI, but nothing routes their asks.
- **Windows is untested.** Use WSL2.
- **`hx` shares its name with the Helix editor's `hx` command.** If you use Helix, put one of them
  first on your PATH or alias the other.

## FAQ

### Do I have to change my skills or prompts?
No. trk's skills teach agents the tracker, and everything else you use stays as it is.

### Does it cost tokens to run?
Routine routing runs no model: the watcher wakes on trk's change feed, and footers read local
state. Only your Claude Code sessions use tokens, as they already do.

### Where does my data live?
On your machine. trk's store is a SQLite file in `~/.local/share/trk`, and nothing is sent anywhere.
Back it up with `trk backup`.

### Can I use just one part?
Yes. trk works alone (`./install.sh --no-hx --no-plugins`), and workbench's `cache-timer` and
`vet` work without herdr. Each repo has its own install.

### What happens to an agent that dies mid-ticket?
Its claim is a lease. When the session stops renewing it, the lease lapses and the ticket goes back
on the ready list for another session.

### How far does it scale?
That's up to you, since gatehouse is plumbing. A pattern that works well on top of it: a top-level
agent drives one driver session per program, each driver hands tickets to worker sessions,
independent auditors review what workers built, and you answer asks from the top. Nothing requires
this shape, and none of it is built in.

### How do I uninstall?
Run `./install.sh --uninstall`. Your clones, trk's store and your config stay. It prints the
commands that remove the plugins.

## About contributions

Issues are welcome. See each repo for how it takes changes.

## License

MIT. See [LICENSE](LICENSE). trk, hx and workbench each carry their own MIT license.
