# Do all hosts' pre-flight stamps agree?

A stale install on one cypher silently produces different rollup
numbers: the provincial run looks fine, and the bcfishpass parity diff
then contains version drift as well as methodology drift, with no way to
separate them afterwards. This is the \#183 sibling-host parity hook,
absorbed into link#246.

## Usage

``` r
lnk_preflight_parity(
  stamps,
  n_expected,
  keys = c("link_version", "fresh_version", "repo_sha", "config_hash", "fwapg_sha"),
  forbid_na = c("link_version", "fresh_version", "repo_sha", "fwapg_sha"),
  forbid_dirty = TRUE,
  quiet = FALSE
)
```

## Arguments

- stamps:

  A data frame, one row per host, from
  [`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md).

- n_expected:

  Number of hosts that were supposed to report. Required.

- keys:

  Fields that must be identical across hosts.

- forbid_na:

  Fields that may not be the literal `"NA"` on any host.

- forbid_dirty:

  Fail when any host's checkout is dirty.

- quiet:

  Suppress the human-readable report.

## Value

Invisibly, a list with `ok`, `n`, `mismatches`, `reference`,
`offenders`, `problems` and `message`.

## Details

Three properties, each of which fails toward stop:

- **Everybody answered.** `n_expected` has no default on purpose. A
  dropped ssh yields a short table, and a short table judged on its own
  terms produces "no mismatches found" — an affirmative claim of
  agreement among hosts that never replied.

- **Nothing is unresolved.** A field that is the literal `"NA"` on any
  host is a failure, not a neutral. `NA == NA` is not agreement.

- **Nothing is dirty.** A SHA recorded against a dirty tree is a lie,
  the same position
  [`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
  already takes for packages.

Only then are the key fields compared, against row 1 (the dispatcher) as
reference. `link_sha` and `fresh_sha` are deliberately **not** keys —
see
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md)
for why comparing them is either guaranteed to fail or guaranteed to
pass vacuously.

## See also

Other preflight:
[`lnk_preflight_fresh()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_fresh.md),
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md),
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)

## Examples

``` r
row <- function(host, ...) {
  d <- list(host = host, link_version = "0.46.0", link_sha = "NA",
            fresh_version = "0.33.0", fresh_sha = "NA",
            repo_sha = "abc123def456", repo_dirty = "FALSE",
            config_hash = "cfg012345678", fwapg_sha = "e6e1eb0aaaaa",
            r_version = "4.4.1")
  as.data.frame(utils::modifyList(d, list(...)), stringsAsFactors = FALSE)
}
agree <- rbind(row("m1"), row("cy-job1"))
lnk_preflight_parity(agree, n_expected = 2, quiet = TRUE)$ok
#> [1] TRUE

drift <- rbind(row("m1"), row("cy-job1", fresh_version = "0.31.0"))
lnk_preflight_parity(drift, n_expected = 2, quiet = TRUE)$offenders
#> [1] "cy-job1"
```
