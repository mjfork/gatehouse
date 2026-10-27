# Releasing a new set

A gatehouse release is one commit of [`versions.toml`](../versions.toml) that moves one or more pins.
Users get it with `git pull && ./install.sh`.

1. **Pick the commits.** Bump trk, hx and workbench together: for each, use a commit on its
   default branch whose own tests pass. When trk's contract changed (anything under
   `trk/contract/`), the hx commit must carry a matching copy of it.
2. **Edit `versions.toml`.** Change only the `commit` lines, and give the full 40-character hash.
3. **Install the set on a clean machine.** Use a fresh Linux user or container, and a Mac if the
   release touches anything platform-specific:

   ```bash
   ./install.sh --src /tmp/gh-src
   trk --version && hx reconcile --dry-run && claude plugin list
   ```

   Then take one ticket from `hx start` through an ask and its answer to `verified`, the way the
   README's "Your first ticket" does.
4. **Run gatehouse's own tests:** `tests/run.sh`.
5. **Commit** with a message listing what moved and why, for example
   `trk 671c450 → 1a2b3c4 (asks sort by urgency), hx 175e440 → 5d6e7f8 (matching contract)`.
   Tag it `vYYYY.MM.DD`.

Never move a pin to a commit that isn't on that repo's default branch: users would fetch a
branch that may later vanish.

The workbench pin is enforced like the others: `install.sh` checks out the workbench clone at its
pin and installs the plugins from that folder. The exception is a user whose `mjfork` marketplace
comes from somewhere else, such as GitHub. The installer leaves that marketplace alone and tells
them their plugins follow that source.
