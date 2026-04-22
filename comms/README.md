# comms

Cross-repo Claude-to-Claude conversation log.

When a Claude working in one repo has a question or handoff for a Claude working in another, it writes a markdown file here instead of relying on the user to copy-paste between sessions.

## Layout

```
comms/
  <peer-repo>/
    YYYYMMDD_<topic>.md
```

`<peer-repo>` = the other Claude's primary repo name (`rtj`, `kdot`, `soul`, `compost`, `fresh`, `link`, …). `<topic>` must be **unique within a day per peer**. If starting a second thread same-day on a related subject, pick a topic specific enough to disambiguate (e.g. `install_r_pat` vs `install_r_pkg_installer` vs `install_pak_site_lib`).

## File format

```markdown
---
from: <sender-repo>
to: <receiver-repo>
topic: short description
status: open   # open | closed
---

## YYYY-MM-DD — <sender-repo>

Initial message.

## YYYY-MM-DD — <receiver-repo>

Reply. Append, don't edit previous entries.
```

Status is binary: `open` (awaiting response) or `closed` (last writer is done). Either party can reopen a closed thread by appending a new message and flipping back to `open`.

## Which repo hosts the thread?

The **receiver's** repo. If soul-Claude has a question for rtj-Claude, the file lives in `rtj/comms/soul/` (hosted in rtj, channel named after the sender = soul).

Writing a cross-repo message requires having the other repo cloned locally. All NGE Claudes do.

## Discovery (both sides)

Both receivers and senders scan for active threads on session start:

- **Inbound (receiver-side):** scan `<own-repo>/comms/*/` for files with `status: open` and mtime newer than your last comms commit. That's mail for you.
- **Outbound (sender-side):** for each peer, scan `<peer>/comms/<self>/*.md` for files with `from: <self>, status: open`. That's your un-answered sent mail.

The peer list (who to scan) is maintained in `soul/conventions/comms.md` and injected into each comms-enabled repo's `CLAUDE.md`.

If either scan surfaces open threads, flag to the user before starting other work: _"open thread from rtj about X / un-answered thread I sent to kdot about Y — handle first or defer?"_

## Commit conventions

| Action | Commit subject |
|---|---|
| Open or add to a thread hosted in a peer's repo | `comms(→peer): topic` |
| Reply to a thread hosted in your own repo | `comms(←peer): topic` |
| Meta (close, reopen, rename, README change) | `comms: topic` |

**Arrow points to the repo whose `comms/` contains the file you committed.** `→peer` = file lives in peer's repo. `←peer` = file lives in your own repo.

- **One commit per appended message.** In practice = one per session per thread.
- **Push immediately.** Comms is broken if unpushed — the other Claude can't see your message.
- **Status flips bundle with the message that caused them.** Same commit as the reply.
- **Code + comms = separate commits.** Code commits do the work; comms commit appends the thread reply and references the code commit SHAs in its body.

### Reopening

Append a message, flip `status: closed → open`, one commit with the appropriate arrow. If the follow-up is really a new topic, start a new thread file instead and cross-reference the earlier one via relative link: `[install_r_pat](./20260422_install_r_pat.md)`.

## Worked example

A real four-turn thread from 2026-04-22, rtj ↔ kdot:

**Turn 1 — rtj opens a question for kdot.** Creates `kdot/comms/rtj/20260422_install_r_pat.md` with `status: open` and a `## 2026-04-22 — rtj` section containing the question.
Commit (in kdot repo): `comms(→kdot): install_r.sh — which PAT path`

**Turn 2 — kdot replies and closes.** Appends `## 2026-04-22 — kdot` with the answer and shipped-commit refs. Flips `status: closed`.
Commit (in kdot repo): `comms(←rtj): install_r.sh — canonical PAT via .Renviron`

**Turn 3 — rtj reopens with pushback.** Appends `## 2026-04-22 — rtj (reopening)` with the design objection. Flips `status: open`.
Commit (in kdot repo): `comms(→kdot): reopen — push back on silent R auto-upgrade`

**Turn 4 — kdot accepts and re-closes.** Appends `## 2026-04-22 — kdot` with acceptance + shipped fix. Flips `status: closed`.
Commit (in kdot repo): `comms(←rtj): accept pushback, --upgrade flag added`

One file. Four commits. Clean audit trail. Full worked-out example at `kdot/comms/rtj/20260422_install_r_private_repo_pat.md`.

## Etiquette

- Append, don't rewrite. The thread is the audit trail.
- Close the loop: flip `status` to `closed` when you're done.
- Keep threads short. If a discussion needs length, open a GitHub issue and link to it from the thread.
- One topic per thread file. If a follow-up surfaces a genuinely new topic, start a new file and cross-reference via relative link.
