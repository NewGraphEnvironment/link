# Progress

## Session 2026-04-12/13
- Discovered non-minimal barrier removal as root cause of segment count gap (149% → 1.3%)
- Discovered base segment filters (localcode_ltree IS NOT NULL)
- Built sequential breaking pipeline matching bcfishpass order
- Proved all species within 5% on ADMS
- Synced bcfishpass CSVs to link/inst/extdata/bcfishpass/
- Synced channel_width from tunnel (75,736 field measurements)
- Synced bcfishpass fork: main = upstream mirror, newgraph = our branch
- Wired: user_barriers_definite, observation_exclusions, user_crossings_misc
- Reverted: user_barriers_definite_control (regression, wrong application point)
- Found missing indexes → 35x classification speedup, filed fresh#150
- Reopened fresh#147 for BULK SK spawning -39.9%
- Species now resolved dynamically from parameters_habitat_dimensions_bcfishpass.csv + wsg_species_presence.csv
- Commits: a4a52aa, 9d0c871
