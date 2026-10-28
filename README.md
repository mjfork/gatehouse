# gatehouse

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Bring in the work. A fleet of token-efficient agents drives it to done. You see only the
decisions that need you.**

```bash
curl -fsSL "https://raw.githubusercontent.com/mjfork/gatehouse/main/install.sh?$(date +%s)" | bash
```

Linux and macOS · needs [herdr](https://herdr.dev), [Claude Code](https://claude.com/claude-code),
[uv](https://docs.astral.sh/uv/) and Python 3.12+ · [prerequisites](#install) ·
[what gets installed where](#what-gets-installed-and-where)

</div>

<!-- screenshot: docs/images/overview.png
     A herdr window mid-run: driver pane, three worker panes, the needs-you list on the left
     (highlight it), and one footer (highlight ⚑ and the cache timer). -->

## The idea

Work is defined somewhere else: an upstream ticket in JIRA or Azure DevOps, a GitHub issue, a doc,
or an idea in your head. gatehouse takes it from there:

1. **Bring it in.** One command reads the ticket or your description and charts it with you: the
   problem, what "done" looks like as checkable statements, the open decisions, and the projects.
2. **Build the tree.** Projects get specs, specs get tickets, and tickets get dependencies, all
   sized so one agent session can do each piece.
3. **Turn the fleet loose.** A driver session runs the program. It starts worker sessions, gives
   each the cheapest model that will pass first time, keeps every slot busy, and checks every
   result.
4. **Decide, don't babysit.** When anything needs a person, it reaches you in one queue, sorted
   by how much work it holds up. Answer it, and the agent that asked carries on.

Nothing moves to "done" on an agent's say-so. Stage gates need the evidence on record first: the
PR, a passing test run, an independent review.

### Why use gatehouse?

| | What you get |
|---|---|
| **One queue for your decisions** | Every question from every agent lands in the needs-you list on herdr's left and as `⚑ N` in every footer. No pane-hunting. |
| **"Done" means proven** | Tickets can't move from built to merged to verified until the evidence is recorded. |
| **Your answer wakes the agent** | It gets a one-line note and continues. Nothing ever types over you: the note waits until the pane is idle and its input box is empty. |
| **Work keeps moving around you** | An open question blocks only the work that depends on it. Everything else carries on. |
| **Token-efficient by design** | Each job gets the cheapest model that will pass, workers compact early and start fresh between tickets, and timers keep the prompt cache warm. [More below.](#token-efficiency) |
| **You can see each session** | Footers show cache time left, what fills the context, and which sessions are heaviest. |

## How you use it

**1. Open a workspace in herdr for the work.**

**2. Bring the work in.** In a Claude Code session in that workspace:

```
/trk-create-program https://jira.example.com/browse/PROJ-123
```

A link to a JIRA or Azure DevOps ticket, or a plain description:
`/trk-create-program Move billing to the new payments API`. The session reads what it can, asks
what it can't, and charts the program with you: the problem, a checkable destination, the
decisions still open, and the projects. It ends by naming the program's id.

**3. Drive it.**

```
/trk-drive-program tr-ab12c
```

This session becomes the program's **driver**. It resolves decisions, gets each project specced
and reviewed, starts a worker session for each ticket in its own worktree, watches them, and keeps
going until every line of the destination is checked off. It surfaces only what a person must
decide.

**4. Answer what reaches you.** When `⚑ 1` appears, run `/needs-me` (or click it) to jump to the
session that's waiting, and answer it there. Answers can be a word: most questions end with
numbered options and an exact "Reply with" line.

That's the whole loop. You never call the tracker or the router yourself: the sessions do.

## How work moves

Everything the fleet does is an item in the tracker, and each kind of item has its own path to
"done". You can follow any of them on the program's page or by asking the driver.

| Item | What it is | How it gets to done |
|---|---|---|
| **Program** | The work you brought in: a destination written as checkable statements, plus notes and open questions | Closes only when every child is closed and each destination line has proof: a passing release run, or your own sign-off on lines that name you |
| **Project** | One piece of the program, with a spec: problem, solution, user stories, decisions, testing, out of scope | Its spec must be **accepted by a session that didn't write it**; then its tickets are cut, built, and closed |
| **Ticket** | One agent session's worth of work, with acceptance criteria and dependencies | Moves through five gates (below) |
| **Decision** | A question to settle before work can go on: research, a prototype, or a grilling | Closes with a written resolution, which later work cites |
| **Question for you** | An *ask*: one question, a recommendation, and numbered options | Blocks exactly the work that waits on it until you answer or it's withdrawn |
| **Findings ticket** | Work whose result is findings, not code: an audit, a review, a diagnosis | framed → specd → reviewed → verified, with the findings checked by someone else |

### A ticket's five gates

```
framed ──▶ specd ──▶ built ──▶ merged ──▶ verified
```

| Gate | Opens when |
|---|---|
| **specd** | The ticket is complete enough to build: its own spec, or the project's spec, has been accepted by an independent session |
| **built** | A PR (or "no repo change") and a passing test run are recorded at the same commit, and every real choice the builder made is logged |
| **merged** | The change is rated for risk and has the review its rating requires (below), and the merge is recorded |
| **verified** | Every acceptance criterion has its own passing check, at a commit that contains the merge |

A gate that isn't met refuses and names what's missing. "I'm done" never opens one.

### Independent review, built in

The tracker checks *who* recorded each piece of evidence, not just that it exists:

- A spec is accepted by a session that wrote none of it.
- A build is audited by a separate session. An auditor reads the builder's logged choices and rules
  on each one: sound, risky or wrong. Every risky or wrong ruling is fixed or settled before the
  merge.
- Findings are checked by a session that didn't write them.
- A subagent shares its parent's session, so it can never review its parent's work. Independence
  needs a separate session.
- Only a person can approve a RED change. An agent that records an approval is refused.

### Merging by risk

Each repo has a `.trk/blast-radius` file that maps paths to risk: for example,
`RED migrations/**` or `YELLOW src/billing/**`. Before a ticket merges, its diff is rated against
that file, and the rating decides how much review it needs:

| Rating | Merges after | Your attention |
|---|---|---|
| **GREEN** | Green CI | None |
| **YELLOW** | Green CI plus an independent audit, with every finding fixed or settled | None, unless the audit raises a question |
| **RED** | All of the above, plus **your** approval | One question in your queue, with a written brief |

A RED change reaches you with a nine-part brief instead of a diff: the decision, what changes and
why, why it's RED, the impact if it's wrong, the evidence, the rollback, the criteria to approve
or hold, where to look, and a recommendation. Your review goes where it matters, and GREEN work
never waits on you. A change to the `.trk/blast-radius` file itself is always RED.

**Keep RED small.** Every RED change waits for you, so a wide RED map fills your queue and slows
the whole fleet. Mark RED only what you would truly want to approve yourself: schema and
migrations, auth and secrets, money, and the map itself. Make the code that's merely important
YELLOW, so an independent audit covers it without you. Files the map doesn't name are GREEN.

## What you'll see

<!-- screenshot: docs/images/needs-you.png
     herdr's left sidebar with the needs-you list: three panes waiting, sorted by urgency.
     Highlight the list and the top row. -->

<!-- screenshot: docs/images/footer.png
     One session's footer, cropped tight. Highlight and label each part:
     cache 42m (cache-timer) · ⚑ 2 (herdr-jump) · heaviest sessions with their cache left
     (ctx-heavy) · the context bar (ctx-bar) · async (turn-mode). -->

<!-- screenshot: docs/images/driver.png
     The driver pane mid-cycle: its status of workers and items, next to two worker panes.
     Highlight the worker names, which match the items they hold. -->

<!-- screenshot: docs/images/ask.png
     A session ending its turn with a "⚑ Needs you" block: the question, numbered options,
     "Reply with". Highlight the Reply with line. -->

| Where | What it shows | From |
|---|---|---|
| **herdr's left sidebar** | The needs-you list: every pane waiting on you, most urgent first | hx + herdr-jump |
| **Footer: `cache 42m`** | Time until this session's prompt cache expires | cache-timer |
| **Footer: `⚑ 2`** | How many sessions are waiting on you. Click to go there | herdr-jump |
| **Footer: the session list** | Your heaviest sessions anywhere in herdr, each with its cache time left. Click to go | ctx-heavy |
| **Footer: the bar** | What fills this session's context, colored by source (file reads, shell output, subagents…) | ctx-bar |
| **Footer: `async`** | How this session ends its turns: with a summary and a clear ask (async), or just stopping (real-time). Click to switch | turn-mode |

## Shortcuts

Type these in any Claude Code session:

| Command | Does |
|---|---|
| `/needs-me` | Jump to the next session waiting on you |
| `/needs-me-list` | The whole needs-you list: pick one, or dismiss one |
| `/jump` | A picker of every herdr pane; type to filter |
| `/jump <pane-id \| workspace \| words>` | Straight to a pane (`w8N:p2`), a workspace, or the one whose title matches |
| `/jump-back` | Back to where you just were |
| `/ctxbar` | What's filling this context, with the biggest chunks |
| `/lets-compact <what's next>` | Writes the best `/compact` (or `/clear`) for what you'll do next |
| `/trk-create-program <link or text>` | Bring work in and chart it |
| `/trk-drive-program <id>` | Drive a program to done |
| `/cockpit:implement-with-herdr <spec>` | Build an existing spec's tickets in parallel workers, at the lowest cost |
| `/vet:map` · `/vet:address` · `/vet:verify` | Review an agent's PR by its decisions, fix what it found, and confirm before merge |

The footer is clickable too: `⚑ N` opens the list, any pane id goes to that pane, and the
turn-mode label switches modes.

## Token efficiency

Running a fleet is cheap only if every session is. gatehouse builds that in:

- **The cheapest model that will pass first time.** The driver routes each job:
  - Haiku at low effort for searches, summaries and CI watching.
  - Sonnet at medium for building an agreed ticket, writing specs and audits.
  - Opus for framing, design and hard debugging.
- **Workers compact early.** Workers start with auto-compact at 250k tokens instead of near the
  1M limit, so each turn re-sends less context.
- **Fresh workers between tickets.** A worker is cleared, or a new one started, for the next
  ticket, so nothing carries one ticket's context into the next.
- **Timers that respect the cache.** The prompt cache lives 60 minutes. The driver's cycles run at
  50 minutes or less, so they stay warm, or 4 hours or more. A cold cycle re-reads the whole
  context at full price: about $1.70 at 300k tokens.
- **Idle when only you block.** When every open path waits on a person, the driver stops its cycle
  and sets one long fallback, instead of spending tokens on checking.
- **A guard on expired caches.** cache-timer shows a confirm card before a prompt re-sends an
  expired cache at full price. It can also write a handoff note just before a big session's cache
  expires, so you resume from the note instead of re-reading everything.
- **See where tokens go.** ctx-bar shows what fills a context, and ctx-heavy shows which sessions
  are heaviest and how long each one's cache has left.
- **No model in the plumbing.** Routing questions and answers runs no model and never polls.

## Install

**Prerequisites:**

| Needs | Check | Get it |
|---|---|---|
| git | `git --version` | preinstalled on most systems |
| Python 3.12 or newer, on PATH | `python3.12 --version` | macOS: `brew install python@3.12` (the system `python3` is 3.9) |
| uv | `uv --version` | `brew install uv`, or [docs.astral.sh/uv](https://docs.astral.sh/uv/) |
| herdr | `herdr --version` | [herdr.dev](https://herdr.dev) |
| Claude Code, logged in | `claude --version` | [claude.com/claude-code](https://claude.com/claude-code) |
| GitHub CLI, logged in, for repos on GitHub | `gh auth status` | `brew install gh`, then `gh auth login`. Workers open PRs and read CI with it |

On a Mac: `brew install uv python@3.12 gh`, then herdr and Claude Code, and `gh auth login`.

**Install:**

```bash
curl -fsSL "https://raw.githubusercontent.com/mjfork/gatehouse/main/install.sh?$(date +%s)" | bash
```

To see every step first without changing anything, add `-s -- --dry-run` after `bash`. The
installer clones itself into `~/.local/share/gatehouse/gatehouse` and runs from there. If you'd
rather read it before running it:

```bash
git clone https://github.com/mjfork/gatehouse ~/.local/share/gatehouse/gatehouse
~/.local/share/gatehouse/gatehouse/install.sh --dry-run
~/.local/share/gatehouse/gatehouse/install.sh
```

It ends with a summary box: each part as installed, updated, current or skipped, then what to do
next, where the clones and the log are, and how to uninstall. You can run it again at any time,
and it skips anything already at its pin. If `~/.local/bin` isn't on your PATH, add `--easy-mode`
and it adds it to `~/.zshrc` and `~/.bashrc` for you.

**Check it worked:**

```bash
~/.local/share/gatehouse/gatehouse/install.sh --verify
```

This checks Python, trk and hx at their pins, herdr, the background service, the plugins, `gh`, and
your PATH, and changes nothing. If you need help, paste its output. Then restart Claude Code, open
a session in herdr, and look for the footer with `cache` and `⚑`. Type `/trk-` to see the program
commands.

**On Windows**, use WSL2 (untested). herdr and the installers are bash and Unix.

### What gets installed, and where

Everything goes under your home folder. Nothing needs `sudo`.

```
~/.local/share/gatehouse/                the clones, checked out at the pins in versions.toml
├── gatehouse/                           this repo, and the installer
├── trk/                                 the tracker ┐ keep these: Claude Code's hooks
├── hx/                                  the router  ┘ run scripts from them
└── workbench/                           the plugins (Claude Code installs from here)

~/.local/bin/
├── trk, hx                              commands, installed by uv (the sessions use them)
└── claude-worker                        how worker sessions start: Claude Code with early
                                         auto-compact (Linux also gets launch-guard.sh)
~/.local/share/uv/tools/{trk,hx}/        their Python environments, managed by uv

~/.claude/
├── skills/trk, trk-create-program,
│   trk-drive-program, hx-work           what teaches sessions the tracker and the program loop
├── settings.json                        hooks added: SessionStart, UserPromptSubmit and
│                                        PostToolUse (keep claims alive, warn on a stale
│                                        checkout); Linux also gets a memory guard on Bash
└── plugins/                             the mjfork marketplace (→ the workbench clone) and cockpit,
                                         ctx-bar, cache-timer, herdr-jump, turn-mode

~/.config/hx/config.toml                 the router's settings (a starter, only if none exists)
~/.config/herdr/config.toml              three keys changed so herdr shows the needs-you list,
                                         with a config.toml.bak-hx-* backup beside it (skip with
                                         install.sh -- --no-sidebar); the hx herdr plugin is
                                         linked
~/Library/LaunchAgents/com.hx.watch.plist   the router's background service on macOS
~/.config/systemd/user/hx.service           …or on Linux

~/.local/share/trk/                      your data: the tracker's SQLite store
~/.local/state/hx/                       the router's inbox, logs and hold file
~/.local/state/gatehouse/                installed (the commit each part is at), install.lock,
                                         and install-<time>.log for every run
~/.herdr-queue/, ~/.claude/ctx/          the plugins' small state files
```

Replaced skills and scripts are backed up to `~/.local/share/{trk,hx}-skill-backups/`. The one
background process is the router service, which uses no model and doesn't poll.
`install.sh --uninstall` removes the commands, skills, hooks and the router service. It keeps your
data, your config, the clones, the plugins and the install logs, and prints the commands that
remove the plugins and the clones (`rm -rf ~/.local/share/gatehouse`).

### Optional: the status line

workbench also includes a status line for the bottom of every Claude Code session: where you are,
the model, how full the context is (measured against the auto-compact level), your session and
weekly usage with their reset times, the cost, and which login you're on.

```
/Users/…/myapp [myapp] Sonnet 5.5 ctx 19% (184k/967k)
session 37% (resets 4:02 PM CDT) · week 21% (resets Sat 1:22 AM CDT) · $3.42
alex@example.com · Example Co
```

It's a plain script, not a plugin, so the installer leaves it alone. To use it (it needs `jq`;
on a Mac, `brew install jq`):

```bash
cp ~/.local/share/gatehouse/workbench/statusline/statusline.sh ~/.claude/statusline.sh
```

Then add this to `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh\"" }
```

Set `STATUSLINE_TZ` (for example `America/Chicago`) to pin the time zone. To remove it, delete the
`statusLine` entry.

### Installer options

| Option | Does |
|---|---|
| `--dry-run` | Print every step and change nothing |
| `--verify` | Check an existing install and change nothing; paste its output when asking for help |
| `--src DIR` | Where the clones go (default `~/.local/share/gatehouse`) |
| `--me NAME` | Your name in the tracker and router, for a new store (default: your user name) |
| `--no-hx` | The tracker only; no herdr needed |
| `--no-plugins` | Leave Claude Code's plugins alone |
| `--plugins LIST` | Choose the plugins, e.g. `--plugins cache-timer,herdr-jump` |
| `--force` | Reinstall everything, and replace installed skills that differ from the pinned copy (old copies are backed up) |
| `--easy-mode` | Add `~/.local/bin` to PATH in `~/.zshrc` and `~/.bashrc` if it's missing |
| `--uninstall` | Remove what was installed; your clones, data and config stay |
| `--verbose` | Show each tool installer's own output (it always goes to the log) |
| `--quiet` | Print errors only |
| `--no-gum` | Plain output, even when [gum](https://github.com/charmbracelet/gum) is installed |
| `-- <args>` | Pass options to the router's installer, e.g. `-- --no-sidebar` |

## Updating

Run the install one-liner again:

```bash
curl -fsSL "https://raw.githubusercontent.com/mjfork/gatehouse/main/install.sh?$(date +%s)" | bash
```

It fetches the newest gatehouse, updates whatever has a new pin, and skips the rest. The tools are
installed as copies, so they change only when you rerun the installer. That way, the set you run
is always one that was tested together.

If an update changes skills, the run may stop with "Nothing was changed", because your older
installed copy counts as different. If you didn't edit those skills yourself, rerun with
`-s -- --force` after `bash`. The old copies are backed up either way.

## Design philosophy

1. **Evidence over trust.** An agent saying it's finished is a claim; a passing test tied to a
   commit is evidence. Gates read the evidence.
2. **A question is a work item.** Questions live in the tracker, block exactly what depends on
   them, and have an owner and an answer on record. A question in a chat scrollback has none of
   that.
3. **Interrupt the person, never the typing.** Questions reach you, and answers reach agents.
   Nothing is typed into a pane you're using.
4. **Spend tokens on work, not on watching.** Cheapest model per job, early compaction, a warm
   cache, and no model in the plumbing.
5. **Plumbing, not prompts.** gatehouse works under whatever skills and prompts you already use.
6. **One set, tested together.** The tools are pinned to commits that passed together, and you
   upgrade them as a set.

## How it compares

| | gatehouse | herdr alone | An issue tracker (GitHub Issues, Linear) |
|---|---|---|---|
| Runs many agent sessions side by side | ✅ via herdr | ✅ | ❌ |
| Breaks outside work into a dependency tree agents can work | ✅ | ❌ | ⚠️ by hand |
| Starts and manages the worker sessions | ✅ the driver | ❌ | ❌ |
| Gates that need evidence before "done" | ✅ | ❌ | ❌ |
| Agent questions as tracked, blocking items | ✅ | ❌ | ⚠️ as comments |
| An answer wakes the asking session | ✅ | ❌ | ❌ |
| Model routing, early compaction and cache-aware timers | ✅ | ❌ | ❌ |
| Setup | one installer | one install | a hosted account |

**Use gatehouse when** you have more work than one session can carry, and you want to spend your
attention on decisions, not on supervision.

**It's not the best fit when** you run one session at a time, you don't use herdr, or your team
needs a shared hosted tracker (the tracker is one SQLite file per machine).

## Architecture

```
            ┌──────────── you ────────────┐
            │ needs-you list · footer ⚑ · │
            │ the session that's asking   │
            └──────▲───────────────┬──────┘
         questions │               │ answers
                   │               ▼
 ┌────────┐ change feed + JSON ┌────────┐  herdr CLI   ┌──────────────────────────┐
 │  trk   │◀──────────────────▶│   hx   │─────────────▶│ herdr: workspaces, panes │
 │ work,  │                    │ router │  wakes panes │ driver + worker sessions │
 │ gates, │◀───── trk CLI ─────┤        │              │ with the workbench       │
 │ asks   │  (sessions claim,  └───┬────┘              │ plugins in their footers │
 └────────┘   record evidence,     │ needs-you queue   └──────────────────────────┘
              ask questions)       ▼
                            workbench herdr-jump (⚑ N)
```

| Part | What it does | You use it through |
|---|---|---|
| [trk](https://github.com/mjfork/trk) | The tracker: programs, specs, tickets, claims, stage gates, questions and evidence, in one SQLite file per machine with an append-only journal | the `/trk-…` commands; sessions run the CLI |
| [hx](https://github.com/mjfork/hx) | The router: a background service that delivers questions and wakes the sessions that asked | nothing; it runs on its own |
| [workbench](https://github.com/mjfork/workbench) | Claude Code plugins: the footer, the shortcuts, the parallel-build workflow and `vet` | the footer and the `/` commands |

[docs/how-it-fits.md](docs/how-it-fits.md) covers what each part reads and writes, and the written
contracts between them.

## Troubleshooting

### `python 3.12 or newer is required`
macOS's `python3` is 3.9. Run `brew install python@3.12`, open a new shell, and run the installer
again. A Python that only uv manages doesn't count: the installers look on your PATH.

### `herdr is required` / `claude is required`
Install it and make sure it's on your PATH.

### `… Nothing was changed. Run again with --force …`
Your installed skills differ from the new pinned copies. After an update this is normal: the older
installed copy counts as different. If you didn't edit those skills, rerun the one-liner with `-s -- --force` after `bash`.
The old copies are backed up either way.

### `… has local changes; commit or stash them first`
The installer won't overwrite edits in one of its clones under `~/.local/share/gatehouse`. Commit or
stash them, or install to a fresh folder with `--src DIR`.

### `another gatehouse install is running`
Two installs can't run at once. Wait for the other one to finish. A lock left by a run that died is
taken over automatically.

### `this script needs bash`
Pipe the one-liner to `bash`, not `sh`.

### Something else failed
Every run writes a log to `~/.local/state/gatehouse/install-<time>.log`, and a failure prints its
last 25 lines and the path. Run `install.sh --verify` too, and send both when you ask for help.

### `/trk-create-program` doesn't appear, or there's no footer
Restart Claude Code so it loads the new skills and plugins, and check that `claude plugin list`
shows the five plugins.

### Sessions report `trk: command not found`
uv's tool folder isn't on your PATH. Run `uv tool update-shell`, open a new shell, and restart the
sessions.

### Questions don't reach the needs-you list
Check the router's service is running:
- **macOS:** `launchctl print gui/$(id -u)/com.hx.watch`
- **Linux:** `systemctl --user status hx`

Its log is `~/.local/state/hx/watch.log`. Restart it with
`launchctl kickstart -k gui/$(id -u)/com.hx.watch` on macOS, or `systemctl --user restart hx` on
Linux.

### The plugins follow GitHub, not the pin
You already had an `mjfork` marketplace from another source, and the installer left it alone. To
pin it, run `claude plugin marketplace remove mjfork`, then the installer again.

## Limitations

- **One machine.** The tracker keeps one store per machine. There's no shared server, and no team
  view of the same tickets.
- **herdr is required** for the fleet, the needs-you list and most of the footer.
- **Claude Code only.** The sessions, skills, hooks and plugins are built for Claude Code.
- **It reads upstream tickets; it doesn't write back to them.** `/trk-create-program` takes a JIRA
  or Azure DevOps link as input, through whatever access your session has. Status doesn't sync
  back.
- **Windows is untested.** Use WSL2.
- **The router's `hx` command shares its name with the Helix editor's `hx`.** You never type it,
  but if you use Helix, check which one comes first on your PATH.

## FAQ

### Do I have to change my skills or prompts?
No. The tracker's skills teach sessions the program loop, and everything else you use stays as it
is.

### Does it cost tokens when nothing is happening?
The plumbing runs no model. When only you are blocking, the driver idles on one long fallback
timer instead of cycling.

### Where does my data live?
On your machine, in `~/.local/share/trk`. Nothing is sent anywhere.

### What happens to a worker that dies mid-ticket?
Its claim is a lease. When the session stops renewing it, the lease lapses, and the driver gives
the ticket to a new worker.

### How many workers run at once?
As many as the program's charter allows. The driver keeps that many busy and puts the critical
path first.

### Can I run more than one program?
Yes: one workspace and one driver per program. A pattern that scales well is one top-level
session over several drivers, with you answering from the top. Nothing requires this shape.

### How do I uninstall?
Run `~/.local/share/gatehouse/gatehouse/install.sh --uninstall`. Your clones, data and config stay.
It prints the commands that remove the plugins and the clones.

## About contributions

Issues are welcome. See each repo for how it takes changes.

## License

MIT. See [LICENSE](LICENSE). trk, hx and workbench each carry their own MIT license.
