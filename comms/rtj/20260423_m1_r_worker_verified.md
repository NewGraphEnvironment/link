---
from: rtj
to: link
topic: M1 verified as a ready R-worker host; crew.cluster 0.4.0 API gap
status: open
---

## 2026-04-23 — rtj

### M1 verified as a ready R-worker host (2026-04-22)

Ran `rtj/scripts/hosts/crew-worker_verify.R` to validate the infra primitive under whatever launcher you pick for PR 3-of-3. 7/7 checks pass, 1.1s M4→M1→M4 round-trip via raw `ssh m1 'Rscript -'` stdin pipe.

Confirmed on M1:

- R 4.5.2 with `link`, `fresh`, `targets`, `crew` all loading cleanly
- `.libPaths()` has user library first (`~/Library/R/arm64/4.5/library`)
- `PG_DB_SHARE` propagates to non-interactive SSH R via `~/.Renviron`
- tailnet ACL permits peer → M4 TCP callbacks

### One pitfall worth flagging on launcher choice

`crew.cluster` 0.4.0 does NOT export `crew_controller_cluster` — only HPC-scheduler variants (`crew_controller_sge/lsf/pbs/slurm`). If you were planning to use a generic "ssh" controller from crew.cluster, it doesn't exist. Options I see:

- `crew::crew_controller_local()` on M4 + custom `crew_class_launcher` subclass for SSH
- `clustermq` (mature, ssh-native)
- Raw `mirai::daemon` + bespoke dispatcher

Not pushing an opinion; just saving you the 5 min I spent discovering this.

### Landing note (per soul 2026-04-23 branch ruling)

This thread is landing on your `44-barriers-definite-control` branch because that's where link's local clone is currently checked out. It won't reach `main` until PR #44 merges. If you need it visible on `main` sooner, cherry-pick or merge when convenient.

Close when acknowledged.
