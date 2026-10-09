# Task: PCEA: link (bcfishpass config) flags different BT rearing segments than bcfishpass (−8.2 km connection, +30.3 km other) (#324)

**If done:** we know why link on the `bcfishpass` config flags different BT rearing segments than bcfishpass in PCEA, and either fix it or record it as an annotated divergence. **If never:** a segment-level replication gap stays unexplained. Today it is within the 5 % parity tolerance (+1.87 %).

## Phase 1: Segment-level diff instrument
- [ ] `data-raw/rearing_diff_segments.R` (args: WSG, species; default PCEA bt): interval-overlap
      join of `fresh.streams` × `streams_habitat_<sp>` (full PK join) against
      `fresh.streams_vw_bcfp` (`rearing_<sp> IN (1,2)`), carrying both sides' edge type,
      gradient, channel width, waterbody/lake-connection (`.lnk_sql_lake_connection()`),
      access, spawning
- [ ] Assert reconciliation inside the script: overlap total = both sides' network km, and
      link-only − bcfp-only = the parity-cross-section rearing diff (incl. connection lines)
- [ ] Stamped output to `data-raw/logs/rearing_diff_324/` (link/fresh SHA, run time, view row count)

## Phase 2: Bucket and explain PCEA
- [ ] Bucket each flow by edge type, waterbody, gradient (link segment vs bcfp segment),
      channel width, access code, spawning / cluster context
- [ ] Test the segment-granularity gradient hypothesis directly (link sub-segment gradients
      under a bcfp segment vs that segment's gradient)
- [ ] Explain the −8.2 km connection gap (the single 5.5 km blk, `access_bt = 2`; read
      `research/bcfp_view_column_coding.md` for code 2)
- [ ] Row-level spot check of the largest blk in each bucket against the rules
      (`configs/bcfishpass/rules.yaml`, fresh's compiled SQL) and bcfp's `load_habitat_linear_bt.sql`
      at `smnorris/bcfishpass@620dbe4`

## Phase 3: Controls
- [ ] Same diff on FINA, PARS, LKEL: are the gross flows present there and cancelling,
      or PCEA-specific?

## Phase 4: Resolve and record
- [ ] If an annotated divergence: entry in `research/bcfp_divergence_taxonomy.yml`
      (mechanism, sign, km), `research/` write-up with Verified / Issues / Produced-by header,
      log README with Measurement + Evidence
- [ ] If a link defect: fix + test here when it is small and in link; a fresh defect or a
      larger change gets its own issue with the repro (drafted for review), named in the PR
- [ ] Edit #324's body with the finding; CLAUDE.md status; RUNBOOK only if mechanics change

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
