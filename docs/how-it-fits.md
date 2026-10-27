# How the parts fit

```
            ┌──────────── you ────────────┐
            │ terminal · herdr sidebar ·  │
            │ footer ⚑                    │
            └──────▲───────────────┬──────┘
          asks     │               │ answers
                   │               ▼
 ┌────────┐ change feed + JSON ┌────────┐  herdr CLI   ┌──────────────────────────┐
 │  trk   │◀──────────────────▶│   hx   │─────────────▶│ herdr: Spaces and panes  │
 │ work,  │                    │ router │  wakes panes │ running Claude Code      │
 │ gates, │◀───── trk CLI ─────┤        │              │ sessions with workbench  │
 │ asks   │  (sessions claim,  └───┬────┘              │ plugins in their footers │
 └────────┘   record evidence,     │ needs-you queue   └──────────────────────────┘
              open asks)           ▼ files
                            workbench herdr-jump (⚑ N)
```

## What each part reads and writes

**trk** owns all the state: items, claims, evidence, asks and an append-only journal. Every write
lands in the journal, and `trk changes --since <seq> --json` replays it. trk never calls herdr or hx. Claude Code sessions use trk through its CLI, taught by
its skills, and its hooks keep each session's claims alive.

**hx** reads trk's change feed and wakes when trk's `feed.head` file changes, so it never polls.
From each change it decides who needs to hear about it:
- an ask for a person goes to the console inbox and the needs-you queue;
- an ask for an agent goes to that agent's pane;
- an answer goes to the asker.

It drives herdr through herdr's CLI and socket, and it writes items to workbench's needs-you queue
so the `⚑` count includes trk asks. `hx start` opens a Space and launches a session for a ticket.

**workbench** plugins run inside each Claude Code session. They read herdr and their own state
files, and none of them call trk or hx. The `turn-mode` plugin makes a session end its turn
with a clear ask when it needs you, and `herdr-jump` counts those asks.

## Contracts

| Between | Written down in |
|---|---|
| trk → hx | trk's `docs/adr/0002-herdr-contract.md` and the JSON Schemas in `trk/contract/`. hx keeps a copy and stops acting, with an alert, if a reply doesn't match. That's why trk and hx are pinned together. |
| trk → a page service | trk's `docs/publisher-contract.md`: optional, and gatehouse ships no service |

The needs-you queue files that hx and herdr-jump share are documented only in herdr-jump's script
for now.

## What runs where

| Process | Started by | Where |
|---|---|---|
| hx watcher | a user service (systemd on Linux, launchd on macOS) | every machine running agents |
| Claude Code sessions | you, `hx start`, or another agent | herdr panes |

trk and the workbench plugins run no background process.
