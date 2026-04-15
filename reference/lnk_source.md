# Produce a fresh-compatible break source list

The bridge between link and fresh. Takes scored crossings and returns a
list spec that plugs directly into
`frs_habitat(break_sources = list(...))`. Zero translation needed — link
scores, fresh consumes.

## Usage

``` r
lnk_source(
  conn,
  crossings,
  label = NULL,
  label_col = "severity",
  label_map = c(high = "blocked", moderate = "potential"),
  where = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (used only for table validation).

- crossings:

  Character. Schema-qualified scored crossings table (output of
  `lnk_score_severity()`).

- label:

  Character. Static label for all rows (mutually exclusive with
  `label_col`).

- label_col:

  Character. Column to read labels from (default: `"severity"` — the
  column `lnk_score_severity()` creates).

- label_map:

  Named character vector. Keys are link severity levels, values are
  fresh break labels. Default maps high -\> blocked, moderate -\>
  potential.

- where:

  Character. Optional SQL filter (e.g., only crossings in a specific
  watershed). Developer API — raw SQL, must not contain user input.

## Value

A named list with elements `table`, `label` or `label_col`, `label_map`,
and optionally `where` — exactly the format `frs_habitat()` expects.

## Details

**Zero-friction bridge:** the return value IS a fresh break source spec.
No transformation, no adapter — just pass it through.

**`label_map` is the key abstraction:** link thinks in severity
(high/moderate/low). fresh thinks in access
(blocked/potential/accessible). The map translates between domains.

## Examples

``` r
# --- The link -> fresh handoff ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Step 1: Score crossings with link
lnk_score_severity(conn, "working.crossings")

# Step 2: Produce break source
src <- lnk_source(conn, "working.crossings")
# Returns:
# list(table = "working.crossings",
#      label_col = "severity",
#      label_map = c(high = "blocked", moderate = "potential"))

# Step 3: Feed to fresh — link's output is fresh's input
frs_habitat(conn, "BULK", break_sources = list(src))

# --- Combine with other break sources ---
frs_habitat(conn, "BULK", break_sources = list(
  src,
  list(table = "working.falls", label = "blocked"),
  list(table = "working.dams", label = "blocked")))
# link scored crossings + falls + dams — all as break sources.

# --- Custom label_map for a conservative project ---
# Only treat high-severity as blocked
src_strict <- lnk_source(conn, "working.crossings",
  label_map = c(high = "blocked"))

# --- Static label for all crossings ---
src_all <- lnk_source(conn, "working.crossings",
  label = "potential", label_col = NULL)
# Every crossing is a potential barrier — no severity differentiation.
} # }
```
