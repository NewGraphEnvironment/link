# DRAFT — not filed. For NewGraphEnvironment/knowledge, pending approval.

**Title:** Parse FISS individual-fish sheets (length, life stage); `average_gradient_percent` holds proportions

**If we do it:** link#284 can split bull trout and chinook FISS captures into adults and juveniles by length. bcfishobs gives BT no life stage at all, so this is the only route to BT spawning-vs-rearing evidence at measured sites. **If we never do:** BT stage stays inferred from DV records, which mix two chars.

## Problem

1. `0220` parses step 1 (site), step 2 (fish collection: species × count) and step 4 (habitat) from the FISS data-submission `.xls`, but not the individual-fish sheet. Per-fish length, weight and life stage are in the submissions and absent from the snapshots (`fiss_step2_fishcoll_<wsg>.csv` has `species`, `total_number` only).
2. `fiss_sites_<wsg>_all.csv` column `average_gradient_percent` holds **proportions**. Across COTR, LNTH, PINE, UNTH and UPCE (knowledge@20f0a5a), all 469 non-NA values lie in 0.001–0.43 (median 0.08), and 0.40 sits on a 0.6 m channel (PINE/UPCE report 17032). The parser passes the `.xls` value through unchanged (`scripts/0220-fiss-xls-parse-nfc.R:382-395`), so either the template field is filled as a proportion or its header is mislabelled. A consumer that divides by 100 gets 0.08 % median gradients.
3. The `_all` snapshots of neighbouring groups share `site_key`s when a report spans both groups (e.g. 17032 in PINE and UPCE): 2,115 duplicated keys across the five. That is likely by design ("all" = the whole report), but it is worth a line in the README, since the natural join key fans out.

## Proposed Solution

- Add the individual-fish step to `0220` → `fiss_step3_fish_<wsg>.csv` (site_key, species, length_mm, weight_g, life_stage where given).
- Rename to `average_gradient` with a stated unit, or convert, after checking a handful of source `.xls` against their PDFs.
- Note the cross-group `site_key` sharing in the README.

Relates to NewGraphEnvironment/link#284
