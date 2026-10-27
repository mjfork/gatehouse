# gatehouse

**Run many Claude Code agents at once, and see only the decisions that need you.**

Agents do the work. Stage gates make each piece of work show its evidence before it moves on. When
an agent needs a decision, it asks for one, and the question comes to you instead of waiting in a
pane you aren't watching. Answer it in a word, and the agent that asked picks up where it stopped.
Everything else stays out of your way.

gatehouse is the front door to three tools that do this together. It holds no tool code of its own:
just this README, [`versions.toml`](versions.toml) (a set of commits known to work together) and
[`install.sh`](install.sh), which installs that set.

**Who it's for:** a developer running several Claude Code sessions side by side, for hours, inside
[herdr](https://herdr.dev). It runs on Linux and macOS. On Windows, use WSL2 (untested): herdr
and the installers are bash and Unix, and nothing runs natively on Windows.

## What a day looks like

1. You write the work down in **trk**: a program, a spec, and tickets each sized for one agent
   session.
2. You start a ticket with `hx start <id>`. hx opens a herdr Space, starts Claude Code in a fresh
   worktree, and the session claims the ticket.
3. The agent builds and tests the change, and opens a PR. trk's gates refuse to move the ticket on
   until the evidence is recorded: the PR, a passing test run, an independent review. Saying "done"
   doesn't count.
4. When the agent needs you, it opens an **ask** and stops. Work that depends on the answer waits,
   and everything else keeps moving.
5. The ask reaches you in the herdr sidebar and in the `⚑` count in every session's footer. Asks
   are sorted by how much work each one holds up.
6. You answer. hx types a one-line note into the asking session when it's idle and its input box is
   empty, so it never types over you. The session carries on.

Watching a session isn't how you find out it needs you. The ask comes to you.

## The parts

| Repo | What it does | Needs |
|---|---|---|
| [trk](https://github.com/mjfork/trk) | The tracker: programs, specs, tickets, claims, stage gates, asks and the evidence behind each. A CLI with one SQLite file per machine. | Python, uv |
| [hx](https://github.com/mjfork/hx) | The router: a small background watcher that delivers asks to the right person or session and wakes the asker when they're answered. `hx start` runs a ticket in its own herdr Space. No polling, and no model runs in routine operation. | trk, herdr, Claude Code |
| [workbench](https://github.com/mjfork/workbench) | Claude Code plugins: a footer showing cache time left, what fills the context, your heaviest sessions and who is waiting on you; commands that split a spec's tickets across parallel agents; `vet` for reviewing an agent's PR before merge. | Claude Code (most plugins also need herdr) |

[docs/how-it-fits.md](docs/how-it-fits.md) shows what each part reads and writes, and which
interfaces between them are written contracts.

## Install

You need `git`, Python 3.12 or newer on your PATH, [uv](https://docs.astral.sh/uv/),
[herdr](https://herdr.dev) and [Claude Code](https://claude.com/claude-code). macOS's own `python3`
is 3.9, so on a Mac run `brew install uv python@3.12` first.

```bash
git clone https://github.com/mjfork/gatehouse ~/src/gatehouse
cd ~/src/gatehouse
./install.sh --dry-run      # shows every step and changes nothing
./install.sh
```

The installer:

1. clones trk, hx and workbench into `~/src` (change it with `--src DIR`) and checks each out at its
   commit in `versions.toml`;
2. runs each repo's own installer, which puts the `trk` and `hx` commands on your PATH, creates
   trk's store under your name (your user name, or `--me NAME`), installs the skills and hooks
   Claude Code uses, and starts the hx watcher;
3. adds the workbench clone to Claude Code as the `mjfork` plugin marketplace and installs
   `cockpit`, `ctx-bar`, `cache-timer`, `herdr-jump` and `turn-mode`, so the plugins are pinned
   too.

If you already have an `mjfork` marketplace from somewhere else, such as GitHub, the installer
leaves it alone and tells you that those plugins follow that source, not the pin.

Run it again at any time: each step skips work that's already done.

**Check it worked:**

```bash
trk --version
hx reconcile --dry-run      # the watcher sees your store and would take no wrong action
claude plugin list          # the five workbench plugins
```

Open a Claude Code session in herdr. Its footer shows the cache timer and the `⚑` count.

### Your first ticket

```bash
echo "The login test fails about one run in ten." > current.md
echo "The login test passes every run." > desired.md
trk new work-item "Fix the flaky login test" --form self-contained --repo ~/src/myapp \
  --section current-behaviour=@current.md --section desired-behaviour=@desired.md \
  --criterion "The login test passes 50 runs in a row"
hx start <the id it printed>
```

When the session needs you, `⚑ 1` appears in your footers and the ask shows in herdr's sidebar.
Click it, answer, and watch the session continue. trk's
[quickstart](https://github.com/mjfork/trk#quickstart) walks through gates and evidence in detail;
hx's [quickstart](https://github.com/mjfork/hx#quickstart) covers asks and Spaces.

### Choose how much

| You want | Run |
|---|---|
| The tracker alone, without herdr | `./install.sh --no-hx --no-plugins` |
| Your own choice of plugins | `./install.sh --plugins cache-timer,herdr-jump` |
| To leave Claude Code's plugins alone | `./install.sh --no-plugins` |
| A name other than your user name in trk and hx | `./install.sh --me alice` |
| To replace installed skills that differ from the pinned copy | `./install.sh --force` (old copies are backed up) |
| To pass options to hx's installer | `./install.sh -- --no-sidebar` |

`./install.sh --help` lists everything.

## Updating

```bash
cd ~/src/gatehouse && git pull && ./install.sh
```

trk and hx are installed as copies, not links to the clones, so a `git pull` inside `~/src/trk`
changes nothing until you run the installer again. That's deliberate: the set you run is always
one that was tested together.

The installer previews each step first. If the skills or scripts you have installed differ from
the new pinned copies, it stops with "Nothing was changed". After an update that changes skills
this is normal, because your older installed copy counts as different. If you didn't edit those
skills yourself, run `./install.sh --force`. The old copies are backed up either way.

## Uninstall

```bash
./install.sh --uninstall
```

This runs each repo's own uninstaller. Your clones in `~/src`, trk's store (your tickets and
history) and your config stay. It leaves the plugins installed and prints the
`claude plugin uninstall` and `claude plugin marketplace remove mjfork` commands that remove them.

## Versions

[`versions.toml`](versions.toml) pins one commit of each repo. A gatehouse release is a new set of
pins that has passed the tests together, because trk and hx share a contract that has to match.
[docs/releasing.md](docs/releasing.md) says how to bump them.

## Running many agents

gatehouse is plumbing, and it works under whatever skills and prompts you use. A pattern that scales
well on top of it: a top-level agent drives one driver session per program, each driver hands
tickets to worker sessions, independent auditors review what workers built, and you answer asks
from the top. Nothing in gatehouse requires this shape, and none of it is built in.

## License

MIT. See [LICENSE](LICENSE). Each part carries its own license in its own repo.
