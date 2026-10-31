# Findings — Check each group's species presence against its fish records (#402), part 2

## Issue context

**If done:** every row of `default`'s `wsg_species_presence.csv` is checked against a stated rule on the fish records, under the operator's rule (one record dated 1950 or later, decided below). Each disagreement is listed for review. **If never:** a species can be modelled in a group on the strength of one old record, or left out where the records say it is there, and nobody is told.

## Today

- **The table is hand-authored,** with a notes column (`source: link (hand-authored)` in `configs/default/config.yaml`, link@43e34096). No rule produces or checks it.
- **A presence row decides whether a species is modelled in the group at all.** Records of a species not present are dropped before the breaks and the access walk (`R/lnk_pipeline_prepare.R:346`), and `access_<sp>` reads -9. So an absent species gets no observation cut, no code 2, no access and no habitat there.
- **Presence is promoted by species group** (`lnk_presence()`: any salmon present means all salmon present; #292, #153), but less than this issue first assumed. *Corrected during PR #424:* promotion reaches only `.lnk_pipeline_prep_minimal()`, where a promoted species the bundle models breaks the streams at its barriers. Access, classification and mapping code follow `lnk_pipeline_species()`, the cell as written, so a promoted species is still not modelled (ADMS PK in `fresh_default` has no access or mapping code). The check judges the cell as written and says, per row, whether its group promotes it.

## Proposed

A `data-raw/` script that counts records per group and species under the rule, and writes the disagreements in both directions:
- **present with too few records,** such as one CH record from 1945;
- **enough records but not present.**

The operator edits rows with a note. Nothing edits the table automatically:
- no records is not no fish, since some groups are barely sampled;
- some presence comes from knowledge outside bcfishobs.

## Decisions (operator, 2026-10-30)

1. **The rule: one record dated 1950 or later, for every species.** First set at five, revised before any code: a single fish caught above where the species was recorded before is real evidence, and it happens for salmon and bull trout alike.
2. **Pooling: yes.** DV records count toward BT where `species_pooling.csv` pools (#290).
3. **Exclusions first: yes.** `observation_exclusions.csv` is applied before counting.
4. **Releases out,** tagged as bcfishpass tags them.
5. **The story lives in a tracker in the bundle,** `configs/default/wsg_species_presence_review.csv`, one row per disagreement with decision `pending`.

## Outcome (PR #424)

`data-raw/wsg_species_presence_check.R` flags 351 of 3,198 cells: 24 marked present with no counting record, 327 not marked with records (137 of them KO). The list is in `data-raw/logs/presence_check_402/` and each row is in the tracker with a drafted story; write-up `research/species_presence.md`. Acceptance item 1 is done. Item 2, the operator's decision and note on each row, is what keeps this issue open; changing presence cells is its own PR (a new `acc` vocabulary row and a version bump).

Follow-ups filed from this work: #425 (steelhead and char alias codes), #426 (the 1990-01-01 lift date test), #427 (the 5-record salmon lift threshold).

## Deciding the 351 rows (next)

Most rows follow from a few answers, so the session opens with a short discussion and then moves. Counts are from `data-raw/logs/presence_check_402/disagreements.csv` (bcfishobs newest record 2026-10-10).

### Where each class stands

| Class | Rows | Proposed | Status |
|---|---|---|---|
| Marked present, no counting record | 24 | read each: 12 no record (six UDEN cells, the Ulkatcho test; KTSU CH and ST; BBAR SK; CARP KO; DRIR CH; TAYR ST), 8 releases only (LPRO RB on 90), 4 undated only (UEUT char, GUIC DV) | to read together |
| KO absent, recorded | 137 | add where recorded (KO goes from 4 modelled groups to about 141, 63 in the Fraser) | operator leaning add (2026-10-31); confirm |
| Salmon (SK, PK, CM, CO, CH) absent, recorded | 134 | a salmon rule informed by the measurement below | to discuss |
| ST absent, recorded | 34 | same as salmon | to discuss |
| BT, WCT, CT, GR, RB absent, recorded | 22 | add where the rule is met | to confirm |
| A single record, none since 1990 | 44 (across the classes above) | the one-record rule says add; the alternative is keep absent with a note | to discuss |
| Group already carries a presence note | 46 (across the classes above) | read the note before deciding | to read |

### Discussion agenda (start of session)

1. KO: confirm add.
2. Single pre-1990 records: count them, or keep absent with a note?
3. Salmon and steelhead: which of the tests below should decide a cell?
4. The 24 present cells: keep (outside knowledge, stocking) or remove.

### Finer grain for salmon and steelhead (measure first)

A group cell is coarse: one record anywhere in the group counts. Per cell, measure from records and barriers already in fwapg (a query, not a model run):

- **Reachable:** records below the species' first natural barrier, or above a lifted one, against records above an unlifted one (more likely a misidentification or an unflagged release).
- **Living there or passing through:** records on the main stem that flows through the group against records on tributaries. A cell recorded only on the through-flowing main stem may mean migrants.
- **Independent evidence**, where loaded: user habitat classification, FISS sites.

A likely rule from it: add where at least one record since the floor is on an accessible tributary.

## Plan

1. **Measure:** a per-cell table for the 168 salmon and steelhead rows (reachable, main stem or tributary, independent evidence), committed under `data-raw/logs/presence_check_402/`, with the story line extended.
2. **Decide:** record each decision in `configs/default/wsg_species_presence_review.csv` (`decision`, `reviewer`, `review_date`), by class rule and then by hand for the residue.
3. **Apply:** a script writes `keep|add|remove` decisions into `configs/default/overrides/wsg_species_presence.csv`, each changed cell with a `notes` entry naming the rule (acceptance item 2). The check re-runs and the decided rows drop out of its flags.
4. **Release:** a new `acc` vocabulary row (the presence species columns are in the `acc` spec), a version bump in the PR, a provenance re-stamp. The changed groups re-model at the next provincial run (#377's runs row).

## Acceptance

- The disagreement list for all groups is committed under `data-raw/logs/`, with each row's counts and dates.
- Every row the operator changes carries a note naming the rule.

Related: #292, #153, #290, #400.




## Exploration at the plan gate (2026-10-31)

- `bcfishobs.observations` keeps each record's UTM (`utm_zone`, `utm_easting`, `utm_northing`, all 375,962 rows), its 50k watershed code (`new_watershed_code`, 375,903), `gazetted_name` (314,351), `waterbody_identifier`, `match_type` and `distance_to_stream`. match_type: A 181,420; D 122,443; C 31,726; B 21,890; E 18,483.
- `fresh_default.barriers` holds every barrier with `blocks_species` for all 13 species regardless of presence, in 241 groups: GRADIENT (three species classes), FALLS 3,294, USER_DEFINITE 226; crossings and dams too (not natural, never blocking access).
- BC Data Catalogue: "Provincial Fish Ranges - Watersheds" (`4e66ac86-aec6-4d79-8462-9e8daf0c0339`), "Provincial Fish Ranges - Generalized" (`e88a7041-2f71-4732-b237-80446d29f38e`), "BC Historical Fish Distribution - Zones (50,000)" (`b665c14f-3d29-414b-b232-cba2a9c3cc55`) and "- Points (50,000)" (`3b723ef2-abd4-4722-abea-9a51258eae15`).
- Zotero (group 4733734, via the Web API; the MCP lacks its env vars and the local API needs Zotero running): McPhail & Baxter 1996 `SUENJEU8`; McPhail & Carveth 1993 `44PTFGQ3`; Roberge et al. 2002 `B3TYJ9I9`; Ericksen et al. 2009 `XBVCXFAG` (duplicates `BCBNSQ7B`, `WZJXVVJL`). McPhail 2007 is absent.
- Operator (2026-10-31) at the gate: KO homework on historic access (Kootenay Lake: fish reached above Bonnington Falls before the end of the last ice age; above never-passable barriers with no rearing lake, KO records are errors). Single records are species-dependent (a lone CCT in the Elk is an error; a lone DV in KOTL is a BT). Many UTMs were typed wrong; elevation and 25–30 % gradients flag implausible records; loneliness is a reason only after the other screens.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Zotero MCP: missing ZOTERO_LIBRARY_ID / ZOTERO_API_KEY | Use the `/zotero-api` skill's Web API with `~/.zotero-api-key` (operator) |
