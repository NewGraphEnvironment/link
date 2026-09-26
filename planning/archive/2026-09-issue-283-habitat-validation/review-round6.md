# Review round 6: source-agnostic `observations` (staged delta diff_r6.patch)

Reviewed `R/lnk_habitat_validate.R` and `tests/testthat/test-lnk_habitat_validate.R` in full.
The tests ran in a `cp -r` copy with the fixture schema renamed: 100 expectations, 0 failures.
Probes ran against local docker fwapg, using temp tables and a renamed probe schema that was
dropped afterwards.

## Findings

### 1. A source with no key silently skips `observation_exclusions` (medium, silently wrong numbers)

`R/lnk_habitat_validate.R:465-469` and `:524-525`. When a source has no `observation_key`,
the key is generated as `'row' || row_number()`, and the exclusion `NOT EXISTS` can never match
a generated key. So `data_error` and `release_exclude` records are counted, with no message.

This contradicts the delta's own rule, "a filter whose column the source does not have is an
error, not a silent pass" (roxygen lines 37-40). That rule is enforced for `match_type` and
`source` but not for this filter. The most likely data-frame use is the one the docs suggest:
a held-out subset of bcfishobs. A user who selects columns and drops `observation_key` gets
this silently.

Measured on the fixture. `o3` is the `data_error` record.
- `o3` at its fixture position: the location at 50 has `n_records` 2 with the key and 3 without it.
- `o3` moved to 250: `n_obs` for `any` is 4 with the key and 5 without it.

Fix: when the source has no `observation_key` and the exclusion key set is non-empty, error.
The error should name the opt-out (`loaded$observation_exclusions <- NULL`), the same way the
other two filters name theirs.

### 2. Generated `observation_key` is not deterministic, and "rowN" is not input row N (medium, reproducibility)

`R/lnk_habitat_validate.R:468`. `row_number() OVER ()` has no ORDER BY.

For a permanent table the plan is `WindowAgg -> Gather (3 workers) -> Parallel Seq Scan`. This
was checked with EXPLAIN on `bcfishobs.observations` using the same join and filter shape.
Three identical read-only runs that assigned the keys produced three different key-to-record
maps (md5 `86eee…`, `650c…`, `2578…`).

The key reaches the output (`observations$observation_key`). It also chooses the "first record
by observation_key" that `.lnk_hv_dedup` keeps for each location, and that record supplies `m`,
`match_class`, `activity` and the other per-record fields. So the output table is not
byte-reproducible. Counts move only when records at one `round(m)` carry different `m`. That
was 0 of 1383 MORR/BULK bcfishobs locations, but nothing stops another source having it.

Separately, the generated number is assigned after the join and filters, so it does not name
the caller's row. In the fixture, input row 1 (`o1`) came back as `row6` and input row 9 as
`row3`. A caller cannot join results back to their own data frame.

Fix:
- **Data frame:** add `observation_key = as.character(seq_len(nrow(d)))` in R before
  `dbWriteTable`. That is deterministic and maps back to the caller's rows.
- **Table:** either require `observation_key`, or order the window by every selected source
  column.

### 3. Species and WSG codes are normalised on one end only (medium, silent zero)

`R/lnk_habitat_validate.R:520-522` against `:238-240`. `species` and `species_obs` are
upper-cased, and `aoi` is forced to `^[A-Z]{3,5}$`, but the observation side is compared raw.

Measured on a data-frame source:
- `species_code = "bt"`, `watershed_group_code = "aaaa"` and `species_code = "BT "` each give
  `n_obs` 0 on every row, with no error.

bcfishobs is upper-case, so the default is unaffected. The delta's purpose is to accept other
sources, and this is where they will differ.

Fix: `upper(trim(...))` on both observation columns in the SELECT and the JOIN. The join is
already a seq-scan hash join (see the plan above), so no index is lost. Alternatively,
normalise the data frame in R before writing it.

### 4. An empty string in `source_exclude` drops every record (low, silent zero)

`:220-222` validation plus `:477-479`. `left(x, length('')) = ''` is true for every row,
including NULL sources after `coalesce`. So `source_exclude = ""` gives `n_obs` 0 everywhere
(measured, probe E). Add `all(nzchar(source_exclude))` to the `stopifnot`.

### 5. `is_spawn` / `is_rear` stored as double error with a Postgres cast message (low, loud)

`opt("is_spawn", "boolean")` at `:528`. A 0/1 column read by readr arrives as double. It fails
with `cannot cast type double precision to boolean`, which does not say which argument is
wrong. Integer, logical and `"yes"`/`"t"` text all work. On the data-frame path, coerce with
`as.logical()` in R, or check the type and name the column in the error.

## Checked and not a defect

- **SQL injection.** The table name goes through `.lnk_validate_identifier` (`^[a-zA-Z_][a-zA-Z0-9_.]*$`).
  Only whitelisted column names are written or interpolated (`cols_keep`, `opt()`/`has()` over
  fixed names). Values travel by `dbWriteTable` or a bound `$1`. `source_exclude` travels by
  temp table, and a `LIKE` wildcard (`a_`, `50%`) is matched literally (probed).
- **Temp-table overwrite.** RPostgres 1.4.10 `dbRemoveTable(temporary = TRUE)` qualifies the
  DROP with the session's `pg_temp_N`. A same-named permanent table in `search_path` cannot be
  dropped by `lnk_vd_src` or `lnk_vd_srcx`. Repeated calls in one session, data frame then
  table, give correct results.
- **Odd inputs, all correct.**
  - A 0-row data frame.
  - Factor codes, and character `blue_line_key` and measure.
  - `integer64` `blue_line_key`.
  - A tibble.
  - A numeric `observation_key`.
  - An all-NA logical `is_spawn` column.
  - `match_types = NULL` (the `params = NULL` path, which keeps match C).
  - `is_spawn` / `is_rear` NA falling back to wording.
- **Stage flags** can never be NA after the `ifelse` fallback, so `d[d$is_spawn, ]` is safe.
- **`data-raw/habitat_validate.R`** calls with named arguments, so inserting `source_exclude`
  before `buffer_m` breaks no caller. A positional numeric would fail `is.character` loudly.
- **Latent, not a bug today:** the optional-column set is written twice, in `cols_keep`
  (`:429-431`) and in the `opt()`/`has()` calls (`:457-528`). The two agree now. If a column
  were added to one and not the other, a data frame's column would be dropped before writing
  and read as NULL.
