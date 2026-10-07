# Code-check P2, round 2 (prose, bundle relation, consumers)

No code bugs. Three prose inaccuracies; the first two are in the diff.

## Findings

- **[severity: fragile, doc]** `inst/extdata/configs/default_tuned/config.yaml:10`: the description says `default` "carries **the same ranges** converted from its channel-width minima". The ranges are on the same species and stages, but the values differ: default has BT 0.041/0.021, GR 0.20/0.021, KO 0.041, RB 0.041/0.021; tuned has BT 0.078/0.078, GR 0.96/0.97, KO 0.57, RB 0.011/0.019. Read as "same values", it contradicts both CSVs and the test at `test-lnk_config.R:351-358`. It also hides that tuned is not uniformly stricter: for RB it is **looser** than default (0.011 < 0.041 spawning, 0.019 < 0.021 rearing), so a `mad` group admits more RB stream habitat under tuned than under default. Suggest "carries ranges for the same species and stages" or "carries its own ranges".
  - The README version (`default_tuned/README.md:17`) is accurate: it quotes default's values and says "instead". Nothing in it claims tuned is stricter.

- **[severity: fragile, doc]** `inst/extdata/configs/default/README.md:26`: "so a group put on `mad` keeps their stream habitat" overclaims for this bundle.
  - `default` has no `pipeline: discharge_fill` (only `default_tuned` sets it, #305). Under `mad`, edge-1250 main stems with no `mad_m3s` still fail every MAD test: 22 % of edge-1250 km in covered groups, and #300 put most of BT's `cw`-only used water there.
  - A group with no discharge at all (BULK) still loses all stream habitat.
  - The old tuned wording carried a caveat ("less rearing than `cw` gives"); this one carries none.
  - Suggest "so a group put on `mad` is not left with no MAD range for them" or similar, or name the discharge gap.

- **[severity: fragile, doc, not in diff but made stale by it]** `inst/extdata/configs/dictionary_parameters_habitat_method.csv:3`: the `model` description says "species with no MAD thresholds (BT, GR, KO, RB) get no stream habitat from inheriting rules". After #307 that is true only of the `bcfishpass` bundle and fresh's copy. `default` and `default_tuned` both give all four a range. A reader takes the parenthetical as the current list.

## Verified true

- **Values match the producer and the CSV.** `default/README.md` quotes spawning 2 m → 0.041, GR 4 m → 0.20, rearing 1.5 m → 0.021, maxima open. Those match `data-raw/logs/habitat_thresholds_307/width_mad_conversion.csv` (medians 0.04115 / 0.20103 / 0.0214, floored to 2 s.f.) and the CSV rows. KO has no rearing MAD, which is right because it rears in lakes only. The producer `data-raw/query_width_mad_equivalent.R` exists.
- **"fresh's copy, plus …" holds.** The pre-diff default CSV is byte-identical to installed fresh 0.36.2's `parameters_habitat_thresholds.csv`. The only changed cells are the 14 MAD cells. The new sha256 `b397dda1…` matches the file.
- **`default_tuned/README.md`'s tuned values match** `default_tuned/parameters_habitat_thresholds.csv` (BT 0.078/0.078, GR 0.96/0.97, KO 0.57, RB 0.011/0.019, 9999 maxima).
- **Consumers:**
  - `cfg$description` is only carried through `lnk_config()` (`R/lnk_config.R:122,235`). Nothing parses it.
  - Provenance `source` is read only by `data-raw/sync_bcfishpass_csvs.R:122`, as an exact match on `https://github.com/smnorris/bcfishpass`. The old value was the fresh URL, which never matched, so moving off it changes nothing.
  - `lnk_config_verify()` resolves the file by its provenance key, not by `path`, so the retained `path: inst/extdata/...` (fresh's upstream path) is harmless.
  - `audit_configs.R` §3c compares headers only, and those are unchanged.
  - `config_hash` hashes file contents. It changes for default and default_tuned, which is intended, because the thresholds really changed.
