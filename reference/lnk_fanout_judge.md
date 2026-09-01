# Judge the outcome of a parallel fan-out

Decides whether a work-list that was fanned out across N workers
actually completed. Every job is expected to record its own exit status;
this reads that record against the list of jobs that were *supposed* to
run and returns a verdict the caller can act on.

## Usage

``` r
lnk_fanout_judge(
  rc,
  expected,
  label = "fanout",
  allow_empty = FALSE,
  quiet = FALSE
)
```

## Arguments

- rc:

  A data frame with a `job` column and an `rc` column, both character.
  One row per job that actually reported. An `rc` that is `NA`, empty,
  or not a run of digits counts as a **failure**, never as a neutral:
  `as.integer("abc")` is `NA`, `NA != 0` is `NA`, and
  [`which()`](https://rdrr.io/r/base/which.html) silently drops it.

- expected:

  Character vector of job ids that were supposed to run. No default —
  see Details.

- label:

  Character. Name for the phase, used in the message.

- allow_empty:

  Logical. Whether an empty `expected` is acceptable. Default `FALSE`.

- quiet:

  Logical. Suppress the summary message. Default `FALSE`.

## Value

Invisibly, a list with `ok`, `status`, `label`, the counts
(`n_expected`, `n_ran`, `n_ok`, `n_failed`, `n_missing`,
`n_unexpected`), the id vectors (`failed`, `missing`, `unexpected`), the
input `rc`, plus `problems` and a formatted `message`.

## Details

Written for the post-consolidate recompute pool in
`data-raw/study_area_run.sh` (link#250), which has no shell test harness
— the predicate lives here because testthat can prove what shell cannot,
the same reasoning that put
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)
and
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md)
in R. `data-raw/fanout_judge.R` is the shell-callable wrapper.

## Why it takes names, not a count

A count answers "how many finished" and cannot answer "which one
didn't". Passing the expected job ids lets the verdict name the jobs
that never reported, and lets it notice a job that reported but was
never asked for — which is a harness bug, not a work failure, and needs
a different fix.

`expected` deliberately has **no default**. Judging a result table on
its own terms produces an affirmative claim of success about jobs that
never reported at all — the failure mode this function exists to
prevent. Same doctrine as `n_expected` in
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md).

## Statuses

Evaluated in order, so the first that applies wins:

- `none_expected`:

  `expected` is empty. A fan-out over nothing exits 0 exactly like a
  successful one, so this is a failure unless the caller passes
  `allow_empty = TRUE`.

- `none_ran`:

  Nothing reported. Distinct from `all_failed`: no job got far enough to
  record anything, which points at the harness rather than at the work.

- `all_failed`:

  Every job that reported failed, and none succeeded. Reported
  separately from how many are missing — both counts are always
  available.

- `ok`:

  Every expected job reported, every status was zero, and there were no
  duplicate or unexpected ids.

- `partial`:

  Anything else — some ran, some did not, or some failed.

## See also

[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md)

Other preflight:
[`lnk_preflight_fresh()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_fresh.md),
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md),
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md),
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)

## Examples

``` r
ran <- data.frame(job = c("BULK", "PARS", "ADMS"),
                  rc  = c("0", "0", "0"),
                  stringsAsFactors = FALSE)
res <- lnk_fanout_judge(ran, expected = c("BULK", "PARS", "ADMS"))
#> [fanout] fanout - OK: 3/3 job(s) succeeded
res$status
#> [1] "ok"

# A job that failed and a job that never reported are different problems.
partial <- data.frame(job = c("BULK", "PARS"), rc = c("0", "1"),
                      stringsAsFactors = FALSE)
bad <- lnk_fanout_judge(partial, expected = c("BULK", "PARS", "ADMS"),
                        label = "recompute", quiet = TRUE)
bad$failed
#> [1] "PARS"
bad$missing
#> [1] "ADMS"
```
