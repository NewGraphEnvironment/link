# Progress — README: lead with intrinsic habitat potential (#338)

## Session 2026-10-14

- Plan-mode exploration; two research reports (exemplar READMEs and guides; survey of 21 NGE package READMEs)
- Operator decisions at the gate: pkgdown index stays auto-generated (prefix families group it); README convention grows as a new soul `conventions/readme.md` through the 13-repo README wave; fresh pin bump goes to its own issue
- Operator framing: three pillars (intrinsic habitat potential, connectivity modelling, trackable rules); bcfishpass named in a "Data and methods it builds on" section; company credit in citations for Zenodo
- Found: link's ORCID fails R's checksum; no CITATION.cff; company absent from Authors@R
- Created branch `338-readme-lead-with-intrinsic-habitat-poten` off main; scaffolded PWF baseline with approved phases
- Next: Phase 1

## Session 2026-10-14 (implementation)

- Phase 1: research and convention draft v0 in findings (d9ea2d9)
- Phase 2: DESCRIPTION Title / Description / Authors@R (c902792)
- Phase 3: README, `data-raw/readme_figure.R`, `man/figures/readme-pars.png`, NOTICE (dd6bdba)
- Phase 3b: CITATION.cff + `update-citation-cff.yaml` (23943ee)
- Phase 4: filed soul#416 (README convention draft v0) and link#339 (fresh pin); edited soul#40 (company credit, ORCID sweep) and link#338 (tasks)
- Verified: every function the README names is exported; README links return 200; the live site serves man/figures from reference/figures; CI strips CLAUDE.md before the pkgdown build (live CLAUDE.html is 404)
