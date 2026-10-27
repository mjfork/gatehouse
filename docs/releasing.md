# Releasing a new set

A gatehouse release is one commit of [`versions.toml`](../versions.toml) that moves one or more pins.
Users get it by running the install one-liner again: it fetches the newest gatehouse, installs
what has a new pin and skips the rest.

1. **Pick the commits.** Bump trk, hx and workbench together: for each, use a commit on its
   default branch whose own tests pass. When trk's contract changed (anything under
   `trk/contract/`), the hx commit must carry a matching copy of it.
2. **Edit `versions.toml`.** Change only the `commit` lines, and give the full 40-character hash.
   Each commit must already be pushed to its repo on GitHub: the installer clones from there.
3. **Install the set on a clean machine.** Use a fresh Linux user or container, and a Mac if the
   release touches anything platform-specific:

   ```bash
   ./install.sh --dry-run
   ./install.sh
   ./install.sh --verify
   ```

   Then run the README's "How you use it" loop on a small repo: `/trk-create-program`, then
   `/trk-drive-program`, until one ticket reaches `verified` with at least one ask answered from
   the needs-you list.
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
