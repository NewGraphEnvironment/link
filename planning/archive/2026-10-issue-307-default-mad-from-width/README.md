## Outcome

`default` now carries mean-annual-discharge minima for BT, GR, KO and RB, converted
from its own channel-width minima. Each width minimum maps to the median `mad_m3s` at
that modelled width, floored to two significant figures: spawning 2 m → 0.041 m³/s, GR's
4 m → 0.20, rearing 1.5 m → 0.021. Maxima are open, and KO rearing (lake-only) stays NA.
A `default` group put on `mad` therefore keeps stream habitat for these species instead
of none, and `cw` and `mad` inside `default` test one stream size two ways.
`default_tuned` keeps #302's observed ranges, so the biology/observation contrast
survives. The #302 medians had no producer; `data-raw/query_width_mad_equivalent.R` is
now that producer.

What was learned:
- **#302's ladders no longer regenerate on `--base=default`.** Their rungs set
  `*_mad_max = 9999`, which `default` now carries.
- **A rear range also gates the `lake_rearing` / `wetland_rearing` buckets under `mad`.**
- **Hand-restated facts drift.** Code review spent four rounds on one mechanism: which
  bundle carries which MAD range was restated by hand in about a dozen documents, none
  checked against the CSV. The review ended on a repo-wide grep of the candidate
  phrasings.

The durable verdict is `research/habitat_thresholds.md`, "`default`'s MAD ranges,
converted from its width minima (#307)".

## Measurement

- **Width to discharge** (`fresh_default`, 55 WSGs, run at `f52c8f0`):

  | width | n | median `mad_m3s` | minimum |
  |---|---|---|---|
  | 1.5 m | 36,601 | 0.0214 | 0.021 |
  | 2 m | 24,509 | 0.04115 | 0.041 |
  | 4 m | 5,977 | 0.2010 | 0.20 |

  These are #302's ad-hoc n and medians exactly. The 2 m median sits 0.00015 above its
  floor boundary.
- **`cw` moves nothing.** Every species' `streams_habitat` digest is identical, main
  against branch, on NATR and ADMS.
- **Under `mad`, stream habitat off waterbodies goes from 0** (NATR):
  - BT: 1,487 km spawning, 2,525 km rearing;
  - GR: 511 / 1,272 km;
  - KO: 816 km spawning, before connect;
  - RB: 1,406 / 2,272 km.

  CH, CO and SK on ADMS are identical. The stream invariant (`*_out_nowb`, `null_nowb`)
  is 0 everywhere.
- **Within `default` after connect, `mad` against `cw` agrees within about 5 %.** NATR
  BT −4.5 % spawning and +1.5 % rearing; ADMS BT +1.7 % / +5.0 %. Compare
  `default_tuned`'s −32 % BT and −76 % GR rearing (#305).
- **Lake and wetland buckets shrink under `mad`.** NATR BT lakes 521 → 304 km and
  wetlands 1,287 → 710 km. This was predicted by the plan review before it was measured.
- **Wrong turns kept:**
  - The plan said "regenerate `rules.yaml` and confirm no diff". That cannot pass: its
    `# Generated:` date moves the checksum. It was replaced by temp builds from the old
    and new CSV, which are byte-identical.
  - The plan said "other species unchanged" on NATR. That could not fail, because NATR
    holds only the four species; ADMS was added as the control.
  - The plan said #302's ladders "regenerate with extra cells". In fact they stop.
- **Full suite:** FAIL 0 / WARN 16 / SKIP 0 / PASS 2449.

## Evidence

`data-raw/logs/habitat_thresholds_307/` — producer outputs (`width_mad_*`, `stamp.txt`),
the `20261006_{natr,adms}_*` before/after runs and the harness copied from #286. Review
records `review-round*.md` and `review-p2-round*.md` in this directory.

Closed by: PR (to be opened from branch `307-default-mad-ranges-for-bt-gr-ko-and-rb-f`)
