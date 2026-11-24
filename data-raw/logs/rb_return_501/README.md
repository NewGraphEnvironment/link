# Rainbow trout back in `default`: three-state builds (link#501, #497)

**Question.** Does bringing RB back, with steelhead records counting as RB,
move anything but RB and the segments its breaks cut?

**Method.** `build.sh` built LKEL (ST and RB present; its RB tops move), GRNL (RB
present without ST; while RB was paused it was modelled with nothing to classify)
and NBNK (RB breaks only through the `ct_dv_rb` presence group) under `default`,
on m1's local fwapg on 2026-11-23, 21:03 to 21:29 UTC, one at a time, from three
`git worktree`s into scratch schemas:

| state | code | schema | tokens |
|---|---|---|---|
| main | `origin/main` `b89d3150` (0.89.0) | `fresh_rb501_main` | `cut-full-top-2 acc-v6` |
| paused | `5b649456` with RB set back to `f` (uncommitted, `link_dirty`) | `fresh_rb501_paused` | `cut-full-top-3`, a throwaway acc row |
| ship | `5b649456` | `fresh_rb501_ship` | `cut-full-top-3 acc-v7` |

So main → paused is the record rule (and presence, which moves no cell in these
groups), and paused → ship is RB modelled. Single-group builds with
`LNK_GUARD_DOWNSTREAM=warn`: downstream groups' barriers are absent in every state
alike. `compare.R` writes `km.csv`, `same_seg.csv` (columns that differ on
segments identical in both states, by line, start and length to the mm) and
`lifts.csv`. `build.log` is the run. Five other sessions were active on the
database, so minutes are not comparable.

## Numbers

| group | segments main / paused / ship | RB accessible km (code 2) | RB rearing / spawning km | RB lifts main / paused / ship (on steelhead records) |
|---|---|---|---|---|
| LKEL | 3,294 / 3,296 / 3,297 | 407.6 (108.6) | 241.9 / 144.6 | 9 / 14 / 14 (6) |
| GRNL | 8,655 / 8,655 / 8,668 | 1,749.2 (167.1) | 657.2 / 136.7 | 3 / 3 / 3 (0) |
| NBNK | 3,897 / 3,897 / 3,922 | none: promoted, so cut but not classified | none | 0 / 0 / 0 |

- **On every segment identical between two states, no column but RB's differs**
  (`same_seg.csv`: 0 for every species' access, spawning and rearing in both
  steps). Every other change sits on a segment that was cut again. LKEL BT
  spawning moves +0.05 km between main and paused, on the two new segments.
- **RB lifts are built even while RB is paused,** so the record rule moves them
  before the unpause: LKEL 9 → 14, 6 of them resting on steelhead records.
- **Against the last build before the pause** (m1's `fresh_default_20261023`,
  `acc-v4`, 0.68.0, other segmentation): GRNL RB 1,749.2 km accessible, 173.5 of
  code 2, 657.3 rearing, 136.7 spawning; LKEL 407.5, 104.5, 242.3, 144.7. LKEL's
  code 2 is 4.1 km higher now, from steelhead records counting as RB.

## Province-wide, from the presence table and the records alone

- 137,152 records count as RB (119,882 RB, 16,509 ST, 761 SST and WST),
  `data-raw/logs/rb_st_497/` with SST and WST added.
- RB's top record per line moves in 78 groups.
- RB breaks streams in 224 groups: 208 with RB marked, and 16 promoted through
  `ct_dv_rb` (BEAV, BLUR, COAL, DEAL, DEAR, FROG, JENR, KTSU, KUSR, LKEC, LPRO, LRAN,
  MBNK, NBNK, SWIR, TOAD; CHUK would be a 17th but is not in the run). In 60 of them no other
  modelled species shares RB's 0.25 access gradient, so RB's gradient breaks are new
  cuts. With the moved tops: cuts move in at least 105 groups. More may move where
  RB's lifts differ from BT's at the same gradient.

The scratch schemas stay on m1 until this PR merges.
