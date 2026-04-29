## Outcome

Decomposed `lnk_config()` into a manifest-only loader and a new `lnk_load_overrides()` data-ingest function that dispatches registered files through `crate::crt_ingest()` for source-agnostic canonicalization. Flattened the config schema into one `files:` map keyed by filename stem, moved `rules:` and `dimensions:` to top-level (no format suffix), added `extends:` for project configs. Pipeline phases gained a `loaded` arg; callers materialize once and thread through. `tar_make()` parity confirmed bit-identical (sha256 `a82de9928809b9751213e08916c476b4ee3f99286bc9ea2dc53f9659eeb92097`) under both crate `0.0.0.9000` and `0.0.2`.

Two process slips during the work, both surfaced and corrected by the user:

1. Started by hand-coding type casts in crate's bcfp handler — flagged as a "scab" since crate's schema YAML already declared types and crate's job was to enforce them generically. Redone schema-driven.
2. Then committed the schema-driven version locally in crate from link's session without a comms-first design conversation. Crate-Claude flagged this, re-implemented properly under Convention C (`crt_*` prefix on every symbol, family-namespaced), shipped as crate v0.0.2. Lesson: sibling-repo work surfaced during integration goes through `comms/<peer>/<date>_<topic>.md` first, the other repo implements + releases, this side consumes.

Follow-ups filed: link#78 (attribution / NOTICE for redistributed upstream data — fwapg, bcfishobs, bcfishpass).

Closed by: commit `749a69f` / PR #79 / tag `v0.18.0`
