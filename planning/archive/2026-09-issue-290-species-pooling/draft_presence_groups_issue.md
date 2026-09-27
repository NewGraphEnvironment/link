Title: lnk_presence(): move the hard-coded presence groups into the bundle

**If we do it:** the species groups that promote presence ("any salmon present means all salmon present") are bundle data, logged and hashed like every other model input. **If we never do:** a model input lives in code, outside `config_hash`, and a change to it is invisible to run provenance.

## Problem

`lnk_presence()` defaults `groups = list(salmon = c("ch","cm","co","pk","sk"), ct_dv_rb = c("ct","dv","rb"))` (`R/lnk_presence.R:67-70`). The pipeline consumes it (`R/lnk_pipeline_run.R:227`) for bcfishpass-parity presence promotion, so it changes model output. #290 introduced `species_groups.csv` for observation pooling, but deliberately left presence alone:
- the concept differs (presence promotion vs evidence pooling);
- the groups differ (`ct_dv_rb` vs `CHAR` = BT, DV);
- folding them together would change pipeline output.

## Proposed

- A bundle file, e.g. `presence_groups.csv` (`group_code, species_code`), or a `role` column in `species_groups.csv`. Whichever it is, declare it under `files:` so it enters `config_hash`.
- `lnk_pipeline_run()` passes it to `lnk_presence(groups = )`.
- `bcfishpass` carries today's two groups verbatim (parity); `default` starts identical.
- Verify byte-identical `streams_access` on ADMS and BULK before and after.

Relates to #290, #236, #189
