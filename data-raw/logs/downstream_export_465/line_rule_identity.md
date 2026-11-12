# Line rule moved into R/ (#465, Phase 1)

`data-raw/recompute_deps.R <out> line` run on m1's fwapg before and after its line
rule moved into `R/lnk_wsg_deps.R` (`.lnk_wsg_deps_line()`), 2026-11-12 UTC.

| run | link | seconds | pairs | groups | md5 of the tsv |
|---|---|---|---|---|---|
| before | `e464c7be` (script's own SQL) | 70.7 | 2,211 | 208 | `bb599ce6bab13423524999972266e363` |
| after | working tree on `e464c7be` (link's function) | ~75 | 2,211 | 208 | `bb599ce6bab13423524999972266e363` |

`cmp` of the two files: identical. The tsv itself is not committed; it is rebuilt from
FWA by the command above.

The same with `all` (line, owner and closure rules), the old script run from a copy of
`e464c7be:data-raw/recompute_deps.R` and the new one from the working tree: both
`d4a9fdda5b5e790e1b602cc1a424b5be` (line 2,211, owner 1,243, closure 965 pairs), so the
owner rule's refusal path is unchanged too.
