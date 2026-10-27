# Code-check round 3: fresh branch `order-child-width-gradient` (HEAD 0810289, vs origin/main)

## Checklist read
- `code-check-infra.md` (38,115 B): read in full.
- `code-check.md` (330,698 B): the prose of all 14 H3s under `## Mechanisms`, with table rows and evidence blocks skipped. Also the standalone "Bare `y`, `n`, `on`, `off`, `yes`, `no` are booleans in YAML 1.1".
- `code-check-r.md` (178,405 B): these headings in full:
  - testthat counts an uncaught error under `error`
  - `skip_if_not()` skips only its own block
  - `expect_gt()` and friends take no `info`
  - R's `yaml` mixed int/float
  - testthat failure snapshots
  - Postgres row order
  - `sprintf("%g")` writes `Inf`/`NA` into SQL
  - `information_schema` lookup by literal name
  - a `function(...)` mock hides arguments
  - `expect_message(regexp = "...$")`

  For the rest, the index lines only.
- `code-check-spatial.md` (155,517 B): "FWA main flow is not edge type 1000 alone" and "FWA `upstream_route_measure` misses the next segment's start". The rest, index only.
- `code-check-shell.md` (125,440 B): index only. The diff has no shell.

## Scope of this round
Since round 2 (e863155 to 0810289) only the docs changed: `R/frs_order_child.R`, the Rd file, and one test name. No code or test logic changed, and round 2's test and mutation results still hold. This round enumerates bcfishpass at `smnorris/bcfishpass@7f444f1b` (checked: `git log -1` = 7f444f1b), `model/02_habitat_linear/sql/load_habitat_linear_{bt,ch,co,st,wct}.sql`.

`grep -n stream_order_parent` finds 15 occurrences of the exception: 3 rearing blocks in each of the 5 files, and none anywhere else in the habitat SQL. I read every block in full.

## Enumeration (table per species/block)

Where frs_order_child() stands on each condition:
- **T** = tested in the SQL at `R/frs_order_child.R:253-275`.
- **D** = named in the docs as the caller's job, or as a deliberate difference (roxygen lines 28-60).
- **N** = neither.

### Conditions shared by every block (all 15)

| condition | bcfishpass text | frs_order_child |
|---|---|---|
| the group being run | `s.watershed_group_code = :'wsg'` | n/a: the caller's `table` defines the scope |
| gradient | `s.gradient <= t.rear_gradient_max` (outside the cw/mad branches; NULL fails) | **T**, only if `gradient_max` is passed (`AND s.gradient <= x`; NULL fails). D: lines 34-41 |
| model | `wsg.model = 'cw' AND …` (inner join on `parameters_habitat_method`) | **D**, "Model" bullet (46-48) |
| width max | `cw.channel_width <= t.rear_channel_width_max` (NULL fails) | **T** by implication: `IS NOT NULL AND < channel_width_lt`, and `lt` = min ≤ max (9999 in every bundle) |
| width min, or the exception | `cw >= rear_channel_width_min OR (stream_order_parent >= 5 AND stream_order = 1)` | **T**: `< channel_width_lt`, `stream_order_parent >= 5`, `stream_order` between 1 and 1. Fresh adds `stream_order = stream_order_max`, which is **D** ("Direct child", 57-60) |

### Conditions specific to each block

| species | block | lines (exception) | spawning or connectivity | access | waterbody / edge filter | other |
|---|---|---|---|---|---|---|
| BT | 1, rearing on spawning | 69-107 (96) | row is `h.spawning` or known `hk.spawning_bt` (87) | none in this block (only through modelled spawning, 29) | none in the block. The row inherits spawning's `R OR (wb NULL AND edge IN (1000,1100,2000,2300))` (52-54) unless the spawning is known | — |
| BT | 2, downstream of spawning | 115-197 (142) | cluster (DBSCAN 1 m) whose downstream-most point has spawning upstream, or is within 10 m of a confluence with spawning upstream (167-183) | `barriers_bt_dnstr = '{}'` (132) | none | — |
| BT | 3, upstream of spawning | 205-347 (229) | spawning downstream within 10 km of the cluster, with no ≥ 5 % segment between; side channels excluded from the trace; trace kept within the group (267-333) | (219) | none | — |
| CH | 1 | 69-114 (103) | spawning or known (86) | none in block | `R OR (wb NULL AND edge IN (1000,1100,2000,2300))` (88-94), **AND form** | — |
| CH | 2 | 121-207 (153) | as BT 2, modelled spawning only (190-191) | (138) | AND form (140-144) | — |
| CH | 3 | 215-… (244) | as BT 3 | (229) | AND form (231-235) | — |
| CO | 1 | 69-115 (103) | spawning or known (86) | none in block | `R OR (wb NULL **OR** edge IN (1000,1100,2000,2300,1050,1150))` (88-94), **OR form, wetland lines included** | `OR s.edge_type IN (1050,1150)` (112): wetland flow lines rear with no width test |
| CO | 2 | 122-210 (154) | as CH 2 | (139) | OR form with 1050/1150 (141-145) | same, at 163 |
| CO | 3 | 218-… (247) | as BT 3 | (232) | OR form with 1050/1150 (234-238) | same, at 256 |
| ST | 1 | 68-112 (101) | spawning or known (86) | none in block | `R OR (wb NULL **OR** edge IN (1000,1100,2000,2300))` (88-92), **OR form** | — |
| ST | 2 | 119-205 (151) | as CH 2 | (136) | OR form (138-142) | — |
| ST | 3 | 213-… (242) | as BT 3 | (227) | OR form (229-233) | — |
| WCT | 1 | 68-114 (103) | spawning or known (86) | none in block | `R OR (wb NULL AND edge IN …)` (88-94), **AND form** | — |
| WCT | 2 | 121-207 (153) | as CH 2 | (138) | `R OR (wb NULL **OR** edge IN …)` (140-144), **OR form** | — |
| WCT | 3 | 215-… (244) | as BT 3 | (229) | **OR form** (231-235) | — |

### Where frs_order_child stands on each block-specific condition
- **Spawning and connectivity.** Named as the caller's in the "Spawning and connectivity" bullet (49-51). True for all 15 blocks.
- **Access.** Tested (`h.accessible = TRUE`, line 264) and stated in the title paragraph (line 8). Blocks 2 and 3 test access themselves. Block 1 does not, so a known-spawning (`hk`) segment can rear there without it. Fresh is stricter only on known-spawning, inaccessible, order-1 direct children. That is a negligible edge case, and the function's opening paragraph names it, so it is not reported.
- **Waterbody and edge type.** The "Waterbody and edge type" bullet (52-56) names it, **but describes it wrongly for CO, ST and WCT.** See Findings.
- **CO's wetland clause** (`OR edge_type IN (1050,1150)`). Neither tested nor named. It is not a condition on exception rows, but it changes whether admitting a wetland child is a difference from bcfishpass at all for CO. See Findings.

**Nothing else sits above its source.** Every condition in the 15 blocks is tested, named, or one of the two waterbody issues below.

### Every parity claim in fresh about frs_order_child or the bypass (`git grep` over R/, man/, tests/, NEWS.md, vignettes/; vignettes have none)

| where | claim | verdict |
|---|---|---|
| R:19-26 / Rd | bcfishpass hard-codes `cw >= min OR (parent >= 5 AND order = 1)` in the BT/CH/CO/ST/WCT rearing SQL | true: the same text in all 15 blocks |
| R:28-35 / Rd | quoted predicate, cited at `bt.sql:88-97` | true at 7f444f1b. `wsg.model='cw'` (line 91) is omitted from the quote but covered by the Model bullet |
| R:34-35 | "a line with no width never qualifies … a line steeper than the rearing maximum never rears" | true in all 15 blocks. The gradient sits outside the branches, including CO's wetland alternative |
| R:43 | "does not reproduce … on its own. What it leaves to the caller, or does differently:" (4 bullets) | complete as a list; **bullet 3 is false in content for CO/ST/WCT** (Finding 1) |
| R:46-48 | the exception sits in the cw branch only | true, all 15 |
| R:49-51 | exception rows still pass spawning or connectivity | true, all 15 |
| R:52-56 | "For CH, CO, ST and WCT (not BT), each rearing block also limits rows to river polygons or to stream edge types outside any waterbody … so for those species it also admits direct children inside lake and wetland polygons" | **false** for CO (all 3 blocks), ST (all 3) and WCT (blocks 2 and 3); true for CH (all 3) and WCT block 1; "not BT" is true. Finding 1 |
| R:57-60 | bcfishpass has no `stream_order = stream_order_max` test; `stream_order_parent` is per blue_line_key | true: no rearing block reads `stream_order_max`, and `load_streams.sql` joins `fwa_stream_networks_order_parent` on `blue_line_key` |
| R:76-81, 134-144, 222-224 / Rd; test 52-53 | default 5L and 1L "match bcfishpass's `stream_order = 1` predicate (exactly)" | true of those predicates alone (pre-existing wording) |
| R:85-86 | bcfishpass.streams stores `stream_order_max`, "the value is the same" | true (`load_streams.sql`: `om.stream_order_max`) |
| R:176-180 example | "bcfishpass's width and gradient tests, in a channel-width group" (BT 1.5 / 0.1049) | true: link's bcfishpass bundle has BT `rear_channel_width_min` 1.5 and `rear_gradient_max` 0.1049 |
| R:150-151 `@param channel_width_lt` | "admit only the lines that the width minimum turned away, as bcfishpass does" | true for the width test |
| frs_params.R:479-482 | `width_known_below_min` "(bcfishpass's exception; frs_order_child()'s channel_width_lt and gradient_max)" | names where the width and gradient part comes from; claims no parity. Round 1 asked for the cw-only caveat here too, and it was not added. That is a note, not false |
| test-frs_order_child.R live block | "3 is the one bcfishpass admits" | true for the width and gradient tests the fixture exercises (NULL width, steep, and NULL gradient all fail `<=` there). The fixture has no spawning or waterbody, so it is not a full-parity claim |
| NEWS.md:246, 262, 272-276 | "bcfp parity", "matches … exactly", "Captures the bcfishpass rearing bypass" | entries from 0.27.x describing the order predicate at the time. Historical and not re-pointed. The branch adds no NEWS entry |

## Findings

### 1. [doc false] The "Waterbody and edge type" bullet generalises CH block 1 to CO, ST and WCT, and they differ

Location: `R/frs_order_child.R:52-56`, and the same paragraph in `man/frs_order_child.Rd`.

It says each rearing block of CH, CO, ST and WCT "limits rows to river polygons or to stream edge types outside any waterbody", and that for those species the function therefore "also admits direct children inside lake and wetland polygons". Only CH (all three blocks) and WCT block 1 use that filter, `R OR (wb NULL AND edge IN (1000,1100,2000,2300))`. The others use an **OR** form, `R OR (wb NULL OR edge IN …)`:
- **ST**, all three blocks: `_st.sql:88-92`, 138-142, 229-233.
- **WCT** blocks 2 and 3: `_wct.sql:140-144`, 231-235.
- **CO**, all three blocks, with 1050/1150 added to the list: `_co.sql:88-94`, 141-145, 234-238. CO also rears every 1050/1150 line with no width test at all: `OR s.edge_type IN (1050, 1150)`, at 112, 163 and 256.

What the OR form passes:
- every line with no `fwa_waterbodies` row, whatever its edge type;
- every 1000/1100/2000/2300 line inside a wetland or lake polygon;
- for CO, every wetland flow line.

So for CO, a direct child in a wetland is mostly **not** a difference from bcfishpass. For ST and WCT it is a difference only for 1050/1150 and construction lines in wetlands.

This is the round's mechanism again: prose written from one file. Round 2's review had listed the three forms (ST "`IS NULL OR`", CO "with 1050/1150 added"), and the fix compressed them into the CH form.

Measured on local fwapg `whse_basemapping.fwa_stream_networks_sp`, province-wide. Population: lines with `stream_order = 1`, the line's maximum order 1, `stream_order_parent >= 5`, the `load_streams.sql` exclusions applied, and no species, access or width filter. That is 23,735 km in waterbodies or with non-stream edge types, against 101,497 km that pass every form:

| class | km | CH (AND) | ST, WCT 2-3 (OR) | CO (OR + 1050/1150) |
|---|---|---|---|---|
| lake polygon (1450, 1200, 1400, 1300) | 16,708 | excluded | excluded | excluded |
| wetland polygon, 1000/1100/2000/2300 | 2,227 | excluded | **admitted** | **admitted** |
| wetland polygon, 1050/1150 | 1,746 | excluded | excluded | **admitted** |
| wetland polygon, 1200/1400/1410 | 1,866 | excluded | excluded | excluded |
| no waterbody row, 1410/1450/1200/1350/1425 | 1,171 | excluded | **admitted** | **admitted** |
| reservoir (X) | 17 | excluded | excluded | excluded |

The CH column is the bullet's description. Under ST/WCT, 2,227 of the 5,839 km of wetland children are already bcfishpass rearing candidates; under CO, 3,973 km are. The bullet's "so … also admits … wetland polygons" is therefore wrong for those species.

The bullet is also incomplete for CH and WCT block 1. Fresh also admits 1,171 km of construction or connector lines (mostly 1410 network connectors) that sit in no waterbody, and 17 km in reservoirs, which "lake and wetland polygons" does not cover.

**Fix:** state the filter per species. For example:
- CH (and WCT's spawning-streams block): river polygon, or a stream edge (1000/1100/2000/2300) outside any waterbody.
- ST (and WCT's other two blocks): river polygon, no waterbody, or a stream edge.
- CO: as ST, plus wetland flow lines (1050/1150), which CO rears with no width test.

And say what the function then admits beyond bcfishpass per species: lake lines for all four; for CH, also wetland lines, reservoir lines and connectors outside waterbodies; for ST and WCT, wetland flow and construction lines. Or drop the consequence clause and just say "tests no edge or waterbody type; bcfishpass's filter differs by species and block (cite the three forms)".

**Downstream.** link's `planning/active/task_plan.md:66` open decision repeats the same generalisation: "for CH, CO, ST and WCT bcfishpass's exception rows must also be river-polygon or stream-edge-outside-waterbody". Correct it before the Phase 4 measurement is designed. Option (a), "link passes the carrying rules' scope", would need three species-specific filter forms, not one.

## Not findings
- Code and tests are unchanged since round 2. Its runs (12 blocks green, live block executed) and its mutation table still apply.
- The access difference in block 1 (known-spawning rows) is stated in the title paragraph and is negligible.
