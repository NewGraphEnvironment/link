# Review round 4 (#317) — doc fixes from round 3

## Clean

(a) RUNBOOK.md structure (lines 737-785): the #310 bullet (738) now holds all its
sub-bullets contiguously, including the `waterbody_key` sub-sub-bullet under "Rollups
split..." (760-761) and the `lnk_habitat_validate()` / ha-vs-km bullets (762-766). The
#317 bullet (767) follows as a sibling top-level bullet with its own five sub-bullets
(768-784); the MAD bullet (785) resumes after it. No orphaned or mis-parented items.

(b) Numbers, drop = connection / (rearing + connection) on link_value:
- ADMS SK 159.058 / 229.852 = 69.2 % (measure.csv; summary.csv bcfp side identical 159.1 / 229.9)
- BULK 37.82 / 64.56 = 58.6 % -> 59
- NECR 89.21 / 161.82 = 55.1 % -> 55
- CHWK 48.30 / 62.92 = 76.8 % -> 77
- NASR 45.27 / 57.52 = 78.7 % -> 79
- THOM 131.98 / 158.71 = 83.2 % -> 83
- QUES 2625.05 / 2758.54 = 95.2 % -> 95 (ref side 2632.15 / 2765.64 = 95.2 %)
- NATR KO 213.008 / 345.428 = 61.7 % -> 62; no bcfp value in summary.csv
- Range 55-95 % over seven WSGs, SK parity 0.0 % on six bcfishpass-config WSGs
  (BULK, CHWK, NASR, NECR, QUES, THOM; BBAR has no SK reference), connection km within
  0.3 % (QUES -0.3) — all match.

(c) No new false claim. "the same on both sides" for SK holds on all seven (ADMS via
summary.csv bcfp columns, six via parity_bcfishpass.csv ref_value); "KO has no
bcfishpass reference" matches summary.csv (NA). "Applying the rule to link alone would
have read SK as -69 %" is consistent with the ADMS 69 % drop.
