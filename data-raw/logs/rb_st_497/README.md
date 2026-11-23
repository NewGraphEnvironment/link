# Rainbow trout and steelhead records, by code and place (link#501, #497)

**Question.** Before rainbow trout (RB) comes back to `default`, how do its
records sit against steelhead's (ST)? Which RB records lie in water steelhead
can reach, which ST records lie above a barrier steelhead cannot pass (likely
rainbow), and what would each way of telling the two apart change?

**Method.** `data-raw/rb_st_records_check.R --schema=fresh_default
--out=data-raw/logs/rb_st_497`, run on m1 on 2026-11-23 against local fwapg
(link `9d3b2ea6` plus the uncommitted script, fresh 0.55.1; `stamp.txt`). It
reads every bcfishobs record coded `RB`, `ST`, `SST`, `WST`, `RB/CT`, `CT/RB`
or ` RB` (137,230 records), `default`'s presence table (overlay applied), and the
persisted `barriers` and `barrier_overrides` of the province-wide `default`
build `20261103_163715-269b585a` (241 groups, link `4dfbfa49`, tokens
`cut-full-top acc-v5`). So the ST lifts read are that build's record rule, not
#470's.

- A record is **above a steelhead barrier** when a natural barrier blocking ST
  (FALLS, GRADIENT at ST's 0.20, USER_DEFINITE; the build holds no subsurface
  rows) lies downstream of it and no ST lift sits within 1 m of that barrier.
  Otherwise it is in **steelhead-reachable water**. "Reachable" is geometry
  only: it ignores dams and whether steelhead live in the drainage (the Columbia
  above the dams, the Mackenzie and the Yukon read reachable where no natural
  barrier stands).
- The nearest barrier's kind comes from `.lnk_presence_measures()` with
  `barrier_species = c(RB = "ST")` (this branch's change).
- Classes use records the pipeline reads (not in `observation_exclusions`;
  36 ST records are). `RB/CT`, `CT/RB` and ` RB` (38 records) are in no class.
- What counts as RB follows the record rule: excluded records out, the record's
  own group marks RB present, no date floor. An RB lift position is a natural
  barrier blocking RB, in a group marking RB present, with one dated record
  counting as RB above it (RB lifts on one record). The top record per line is
  taken per group, as the cuts read it. A presence flag is a group with no RB
  cell and a counting record (1950 or later, not a release, not excluded) that
  would count as RB.
- **Independent check:** for BULK, LFRA and OKAN, records counted from the
  barrier side with `fwa_upstream()` equal the record-side test in all six
  group and code pairs (`independent.csv`).

## Numbers

| class | records |
|---|---:|
| RB in steelhead-reachable water | 69,911 |
| RB above a steelhead barrier | 49,972 |
| ST, SST, WST above a steelhead barrier (likely rainbow) | 348 |
| ST, SST, WST in steelhead-reachable water | 16,925 |

The 348 sit mostly on the coast: East Vancouver Island 134, West Vancouver
Island 69, Fraser 52, South Mainland Coast 43 (COWN 81, SQAM 26, CAMB 25).

| option | records as RB | undated | ST records as RB | RB lift positions | groups whose RB top per line moves | RB presence flags (new) |
|---|---:|---:|---:|---:|---:|---:|
| a, code alone | 119,882 | 661 | 0 | 6,318 | 0 | 1 (0) |
| b, ST also counts as RB | 136,391 | 1,100 | 16,509 | 6,522 | 77 | 2 (1: TUTR) |
| c, by place | 91,718 | 237 | 348 | 6,451 | 96 | 1 (0) |

## What they say

- **Most RB records are in steelhead water** (58 %): field crews record
  juvenile *O. mykiss* below barriers as rainbow trout. Option (c) would discard
  about 28,000 of them in groups where ST is present, for 348 likely-rainbow ST
  records gained. It also needs a place rule the record rule has no term for.
- **Option (b) adds 16,509 ST records to RB's evidence and moves little else at
  the lifts** (+204 positions, 3 %), but it moves RB's top record per line in 77
  groups, so segments move there for every species, and the record-rule digest
  moves the cut token.
- **The one new presence flag under (b) is TUTR** (Tutshi River, Yukon
  headwaters): two Steelhead Database records (1984, 1991) at one site, in a
  drainage steelhead do not reach.
- The 348 likely-rainbow ST records lift nothing for ST under any option: they
  sit above barriers no ST lift opens.

**Decided (owner, 2026-11-23):** option (b), with `SST` and `WST` counting as RB
as well as ST (this numbers' option b counts code `ST` only); TUTR RB goes to the
literature issue. `planning/archive/` for #501 carries the rest.

## Files

- `records.csv.gz`: one row per record, with its class and the option flags.
- `groups.csv`: classes and option counts per group.
- `options.csv`: the province table above.
- `independent.csv`: the barrier-side count for three groups.
- `stamp.txt`: host, build read, bcfishobs rows, `lnk_stamp()`.
