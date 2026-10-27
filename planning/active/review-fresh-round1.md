# Review: fresh `order-child-width-gradient` (round 1)

Diff: branch order-child-width-gradient vs origin/main merge-base 5400e99 (HEAD 25dca92).

## Checklist read

- `code-check-infra.md` (38,115 bytes): in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms` (table rows skipped). Of the 21 other headings, I read the index lines only.
- `code-check-r.md`: 11 headings read in full: `on.exit()` at a script's top level; testthat counts an uncaught error under `error`; `skip_if_not()` skips only its own block; `$` partial-matches; `::text` spelling; under `R CMD check` tests run from a temp dir; R's `yaml` mixed int/float list; Postgres row order; `sprintf("%g")` writes `Inf`/`NA` as bare words; `information_schema` lookup by literal name; a `pkg::` call in a test. About 105 headings not read beyond the index (they do not apply to this diff).
- `code-check-shell.md`: index only, 0 headings read. The diff has no shell.
- `code-check-spatial.md`: index only, 0 headings read. The diff has no spatial code.

## What I ran

All runs used a copy at the scratchpad (`cp -r` of the fresh tree). The fresh checkout was not touched. In the copy, the live test's table names were changed to `working.zz_rev_r1_oc_*`, and I confirmed no such tables were left afterwards.

- `test-frs_order_child.R`: 12 blocks, 0 failed, 0 errors. The live test ran and was not skipped (3 expectations).
- Mutations to `R/frs_order_child.R`, one at a time, each restored before the next:

| Mutation | Result |
|---|---|
| `<` changed to `<=` | live and SQL-shape tests red |
| gradient clause dropped | live and SQL-shape tests red |
| width clause dropped | live and SQL-shape tests red |
| `v < 0` dropped from the validator | refusal test red |
| `IS NOT NULL` dropped | only the SQL-shape test is red; the live test stays green |

  The `IS NOT NULL` result is expected: `NULL < x` is already not true in a WHERE, so that half of the clause is redundant but harmless.
- `test-frs_params.R`: the new blocks pass, and the rest of the file passes too. With the logical check disabled, 3 of 4 refusal cases go red. With the key removed from `bypass_keys`, both new blocks error.
- `yaml::yaml.load("a: ~\nb: yes")` gives `list(a = NULL, b = TRUE)`.

Checked:
- **Defaults:** with both formals `NULL`, the SQL emitted is unchanged apart from two trailing empty `%s`.
- **NULL handling matches bcfishpass:**
  - NULL width fails `cw.channel_width <= max` there and fails `IS NOT NULL` here.
  - NULL gradient fails `s.gradient <= max` in both.
  - Where `min <= max`, `channel_width < min` implies bcfishpass's `<= max`.
- **`.frs_sql_num()`:** finite scalars only reach it after validation, so the `Inf`/`NA` trap cannot fire.

## Findings

- **[fragile]** `R/frs_order_child.R:28-41` (roxygen) and the new example at about line 157 (`# bcfishpass's exception in full`). The prose says that passing `channel_width_lt` and `gradient_max` "reproduce[s]" bcfishpass's exception. It quotes the predicate as `s.gradient <= rear_gradient_max AND cw.channel_width <= ... AND (cw >= min OR (parent >= 5 AND order = 1))`.
  - **What the quote leaves out.** The range it cites, `load_habitat_linear_bt.sql:88-97` at `7f444f1b`, includes line 91 `wsg.model = 'cw' AND`. In all three BT rearing blocks (lines 91, 137 and 224) the order-1 exception sits only inside the `cw` branch. In a group on `mad`, bcfishpass never applies it.
  - **Why it matters.** `frs_order_child()` knows nothing about the cw/mad model. A caller that follows this doc and passes the two bounds for every group admits sub-minimum order-1 lines in `mad` groups, and bcfishpass does not. fresh's working streams carry `channel_width` whatever the group's model, so nothing stops it.
  - **Impact today.** None measured: link's `parameters_habitat_method.csv` bundles are all `cw`. It becomes a silent parity and over-admission gap the first time a group is put on `mad`, which is a reviewed row edit link has planned for.
  - **Second over-claim.** "exactly what the exception adds" overstates parity in another way. bcfishpass's exception rows also pass that block's spawning or connectivity conditions: line 87, `h.spawning IS TRUE ...`, and the clustering in the downstream and upstream blocks. This function runs after clustering and checks no connectivity. That behaviour predates this diff, but the new sentence now claims parity it does not have.
  - **Fix.** Either say in the doc (and in the `width_known_below_min` comment in `frs_params.R`) that the caller must apply this only in `cw` groups and that connectivity is not tested, or give the function a model gate. Reword "in full" in the example.

## Notes (not defects)

- `width_known_below_min` is validated (`R/frs_params.R:479-488`) but nothing in fresh reads it. link's consumer on `main` (`R/lnk_pipeline_classify.R:179-189`) does not read it yet either. So a rules YAML setting `true` is accepted and has no effect until link wires it. This is presumably the planned link half of #326; make sure that half lands before any bundle sets the key.
- The new test comment at `tests/testthat/test-frs_params.R` (the "~" case) says "YAML null drops the key". It does not: yaml keeps `width_known_below_min = NULL`. The assertion (`expect_null`) is still correct, and the case still shows the validator accepts a null.
- The live test uses fixed table names (`working.test_order_child_*`), so two concurrent suite runs on one database would collide. Many existing fresh live tests share this pattern.

## Verdict

One fragile finding: the documentation claims bcfishpass parity but leaves out the `cw`-only gate. Otherwise the SQL, the defaults, the validators and the tests are sound, and every new guard turns a test red when it is removed.
