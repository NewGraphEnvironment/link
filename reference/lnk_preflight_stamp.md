# One-line provenance stamp for cross-host pre-flight parity

The parity payload in a fixed field order, drawn from the facts
[`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
already collects plus the git state of the checkout this host installed
from. Kept separate from
[`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
so the shell contract — the field order — is a documented, tested thing
rather than an inline `Rscript -e` incantation that drifts between two
call sites.

## Usage

``` r
lnk_preflight_stamp(cfg = lnk_config("bcfishpass"), repo = ".")
```

## Arguments

- cfg:

  An `lnk_config` from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).
  Supplies `config_hash`.

- repo:

  Path to the git checkout this host's install came from.

## Value

A named character vector in the documented field order.

## Details

**`repo_sha` is the load-bearing field, not `link_sha`.**
`.lnk_pkg_git_sha()` resolves a SHA from a `.git` beside the installed
package. On the dispatcher link is
[`pkgload::load_all`](https://pkgload.r-lib.org/reference/load_all.html)'d
from a checkout, so it finds one; on every cypher link is pak-installed,
so it does not and returns `NA`. `fresh_sha` is `NA` on both unless pak
recorded a `RemoteSha`. Comparing `link_sha` across hosts would
therefore always fail, and comparing `fresh_sha` would be a vacuous
`NA == NA` pass — a check that looks like a check. `repo_sha` is read
from `~/Projects/repo/link` **on the host itself**, which on a cypher is
exactly what `git reset --hard origin/<branch>` produced. It is an
independent observation rather than a restatement of what the dispatcher
believes (link#246).

Unresolvable facts are the literal string `"NA"`, never empty, so a
truncated ssh response is distinguishable from a resolved absence.

## See also

Other preflight:
[`lnk_fanout_judge()`](https://newgraphenvironment.github.io/link/reference/lnk_fanout_judge.md),
[`lnk_preflight_fresh()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_fresh.md),
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md),
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)

## Examples

``` r
s <- lnk_preflight_stamp(lnk_config("bcfishpass"))
names(s)
#>  [1] "host"          "link_version"  "link_sha"      "fresh_version"
#>  [5] "fresh_sha"     "repo_sha"      "repo_dirty"    "config_hash"  
#>  [9] "fwapg_sha"     "r_version"    
s[["fresh_version"]]
#> [1] "0.33.0"
```
