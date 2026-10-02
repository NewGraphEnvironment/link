# Literature review for link#302: discharge (MAD) bounds for BT, GR, KO and RB

**Compiled:** 2026-10-02 · **Issue:** #302 (relates #284, #286, #299) · **Produced by:** one agent,
reading the local Zotero library read-only (`zotero.sqlite?immutable=1`, `.zotero-ft-cache`
files, `pdftotext` of PDFs, tesseract OCR of one scanned PDF) plus a few web searches.
Nothing in Zotero was added or edited. Prior review this builds on:
`planning/archive/2026-09-issue-284-ch-bt-habitat-thresholds/literature.md`.

## How to read this file

- **Flow measure** says which statistic a number is. They are not interchangeable:
  - **MAD**: mean annual discharge (also "mean annual flow", MAF). What link's `mad_m3s` is.
  - **SUM**: mean summer flow (modelled). In snowmelt basins this is usually below MAD.
  - **SPT**: discharge measured or estimated at spawning time (one visit).
  - **LSF**: a spot estimate of late-summer low flow.
  - **FRESH**: discharge during the spring freshet. Usually well above MAD.
- **Conversions** from cfs to m³/s use 1 cfs = 0.0283168 m³/s, and both values are shown.
  Anything converted from width to discharge is labelled **inference**, with the equation
  that was used.
- **Kind**: **doc** = a number the source states; **expert** = an author's judgement;
  **inference** = this review's own derivation. An inference is never a documented value.
- Pages are the printed page numbers unless marked "pdf p.".
- Zotero keys are the **parent item** keys. Where an attachment has no parent item, the
  attachment key is given and marked "(att)".

---

## 0. Where the existing bcfishpass/CWF MAD values come from

bcfishpass `parameters/example_cwf/parameters_habitat_thresholds.csv`
(smnorris/bcfishpass@f8db4b9) is the copy that link's bundles carry. Its docs
(`docs/03_model_habitat_linear.md`) send the reader to Rebellato et al. 2024 Table 1 for
salmon and steelhead. They say discharge thresholds are "taken from the literature and,
where unavailable in the literature, derived from known fish spawning locations".

| Species · stage | bcfp `example_cwf` | Rebellato 2024 Table 1 (p. 6) | Sources Rebellato cites | What this review found in those sources |
|---|---|---|---|---|
| CH spawn | min 0.46, max 9999 | 0.46–322.5 m³/s MAD | Bjornn & Reiser 1991; Neuman & Newcombe 1977; Woll et al. 2017; Roberge et al. 2002; Raleigh & Miller 1986 | **0.46 was not found in any cited source read.** B&R 1991 (OCR) has no species discharge threshold. Its Fig. 4.4 (p. 90) plots fall Chinook spawnable area against discharge on an axis running 0–5.66 m³/s. Neuman & Newcombe 1977 (OCR, 52 pp.) reviews methods: Tennant percentages of MAF (pdf p. 6) and depth/velocity at redds (App. 3). No stream-size discharge threshold appears in its readable text. Woll 2017 gives a width rule (CH spawn "Channel size < 4m" = Not Suitable, Table 16, p. 84) and no discharge threshold. Roberge 2002 has no species discharge threshold (full-text grep). Raleigh & Miller 1986 was not checked. |
| CH rear | 0.28–100 | 0.28–100 | Agrawal et al. 2005 | **0.28 is documented.** Sheer et al. 2009 summarises Agrawal for juvenile fall CH as "minimum mean annual discharge = 0.28 m3/s" (pp. 13–14). Agrawal's Fig. 1 (p. 10) CH discharge curve sits at 1.0 from just above 0 to the axis end at 100 m³/s and never declines. **100 is therefore the axis limit, not a biological cap (inference).** |
| CO spawn | 0.164, max 9999 | 0.164–59.15 | B&R 1991; Sloat et al. 2017; N&N 1977; Woll 2017; McMahon 1983 | 0.164 not found (Sloat 2017 and McMahon 1983 not checked). Woll 2017 has CO spawn "Channel size < 2m" (Table 18, p. 87). |
| CO rear | 0.03–40 | 0.03–40 | Agrawal 2005; Burnett et al. 2007 | **0.03 not found.** Sheer 2009 p. 9 summarises Agrawal coho as "minimum mean annual discharge = 0.01 m3/s". On the cap: Agrawal Fig. 1 coho is 1.0 to about 20 m³/s, falls to 0.5 near 78 m³/s, then stays flat at 0.5. Burnett 2007 (p. 68): the coho curve "declines at mean annual stream flows exceeding 21.24 m3/s and assigns a score of 0.5 for flows exceeding 76.45 m3/s". **Neither source ever reaches 0, so 40 is not a cap in either one.** |
| SK spawn | 0.175, max 9999 | 0.175–65 | B&R 1991; Woll 2017; N&N 1977; Roberge 2002 | Not found. Woll has SK spawn "Channel size < 2m" (Table 14, p. 81). |
| ST spawn | 0.447, max 9999 | 0.447–75 | B&R 1991; N&N 1977; Roberge 2002 | Not found in B&R, N&N or Roberge. |
| ST rear | 0.02–60 | 0.02–60 | Agrawal 2005; Burnett 2007 | **0.02 not stated in text.** Agrawal Fig. 1 steelhead is 0 at 0 and 1.0 from just above 0, then declines to 0.75 near 78 m³/s. Sheer 2009 p. 19 redraws it with a 0–0.10 m³/s axis and states no number. Burnett 2007 p. 68: steelhead index scores "are high across a broad range of mean annual stream flows". No cap at 60. |
| CM spawn | 0.02312 | ">0.023" | none in the literature | Rebellato p. 5: thresholds were "not available in the literature for Chum or Pink salmon, so these were estimated based on known spawning locations … (PSE)". |
| PK spawn | 0.41133 | ">0.411" | none in the literature | Same as CM. |
| WCT spawn | 0.164–**59.15** | not covered | – | Rebellato covers salmon and steelhead only. WCT's values are identical to the CO row (0.164–59.15 and 0.03–40). WCT is the **only** `example_cwf` row whose `spawn_mad_max` is not 9999. **Inference:** the row was copied from coho, upper bound included. |
| WCT rear | 0.03–40 | not covered | – | Same as WCT spawn. |
| BT, GR, KO, RB | none | not covered | – | bcfp added BT gradient/width defaults to `example_cwf` in a22cf2a (2026-03) without any MAD. |

Three points that matter for #302:

1. **Rebellato's upper MAD bounds were not carried into bcfp spawning.** Every bcfp
   `spawn_mad_max` is 9999 except WCT.
2. **Rebellato states that their caps excluded habitat fish actually use.** On p. 13:
   "the mean annual discharge thresholds used for spawning were lower than those used by
   all fish. For example, spawning and rearing areas for Chinook Salmon in the mainstem
   North Thompson River (DFO 1999) have mean annual discharge estimates of 425.9 m3/s …
   rivers with high mean annual discharge … were excluded from IP models …
   underestimating habitat extent."
3. **The spawning minimums (0.46, 0.164, 0.175, 0.447) could not be traced to a page in
   any cited source this review read.** Treat them as unverified.

**A coincidence worth recording (inference, not provenance).** The Woll et al. 2017
width–MAF equation (§3 below) maps 0.175 m³/s to 4.03 m and 0.164 m³/s to 3.91 m. It maps
0.03 m³/s to 1.76 m and 0.02 m³/s to 1.45 m, which sit close to the 1.5 m rearing width.
Nothing documents that Rebellato used this conversion.

---

## 1. Evidence table

Kinds: doc / expert / inference. "–" means the source gives no number.

| Species | Stage | Bound | Value | Flow measure | Source | Page / table | Notes |
|---|---|---|---|---|---|---|---|
| BT | spawn | min (observed) | redds at **0.25 m³/s** (Colbourne upper mainstem, 2 redds on foot), 0.30 (Crocker, 2), 0.41 (Reynolds, 11), 0.51 (Missinka trib., 5); 0.75–1.6 at the other redd-bearing reaches | SPT: measured from depth-velocity transects, 11–26 Sep, after spawning | Hagen et al. 2015 | Table 2, p. 31 | Parsnip and northern BC; 15 reaches with data. Reaches with **zero** redds were at 0.12 (Table trib.), 1.5, 2.0 and 2.9 m³/s. Text, p. 30: calibration reaches spanned "0.12 to 2.9 m3/s in discharge, and from 3.5 to 18 m wetted width". Kind: doc. |
| BT | spawn | min (survey design) | streams "<2 m wetted width" not surveyed; "corresponds with the limit of habitat use for migratory bull trout spawners" | width, not flow | Hagen et al. 2015 | p. 23, §4.1.2 | Kind: expert. Because of this design, the Table 2 minimum is censored from below. |
| BT | spawn | min (converted) | 2 m → **0.040 m³/s** (1.40 cfs) | MAD | Woll et al. 2017 equation applied to Hagen's 2 m | – | **Inference.** Woll's equation is fitted in Alaska to channel (not wetted) width. |
| BT | spawn | max | **no source gives one** | – | – | – | The only "no redds" large reach is Attichika lower mainstem at 2.9 m³/s (Hagen Table 2), a single reach. Williston adfluvial BT spawn mostly in 5th–6th order streams (Hagen & Weber 2019 p. 21; prior review). |
| BT | rear (juvenile) | min | summer flow **< 0.0057 m³/s** trimmed, "approximates a wetted width ≤1.0 m … because trout are rare in such small streams" | SUM (modelled VIC mean summer flow, 30-year average) | Isaak et al. 2015 | p. 2542 | Natal habitat for BT and cutthroat; occurrence data are juvenile-based. Kind: doc (a parameter choice). In snowmelt basins MAD is larger than SUM, so the MAD equivalent is larger than 0.0057 (inference, size unknown). |
| BT | rear | min | occurrence "very unlikely in streams less than 2 m wetted width" | width | Dunham & Chandler 2001, citing Dunham & Rieman 1999 | p. 26 | Washington. Width only. |
| BT | rear | min | BFW < 3.05 m = LOW capacity class (not zero) | width | Porter et al. 2008 | p. 67 | Thompson CART. Width only. |
| BT | rear | max | **no source gives one** | – | Porter 2008 p. 67: BFW > 3.35 m = HIGH, with no upper class. Isaak 2015 applies no upper flow trim. | – | – |
| DV | any | – | **no DV-specific discharge source found** | – | – | – | link pools inland DV into BT (`species_pooling.csv`). |
| GR | spawn | min (observed) | peak spawning at **0.21 m³/s** (2014) and **0.25 m³/s** (2015); flow receded to 0.10–0.12 m³/s by emergence | FRESH / SPT | House 2021 (TRU MSc), citing ERM 2015/2016 | p. 76 (Fig. 3-4 and text) | Pigeon Stream Diversion, Ekati, NWT: a **constructed** channel built as offsetting habitat, "discharge < 1 m3/s" (p. 80). Spawning sits on the falling limb of the freshet, so the channel's MAD is likely lower than 0.21 (inference). |
| GR | spawn | max (observed) | Fond du Lac River "spawning discharge in the order of 400 m3/s" | SPT | House 2021, citing Golder Associates 2013 | p. 80 | Saskatchewan. Grayling spawn in large rivers. |
| GR | spawn | qualitative | "Small (~10 m wide), medium gradient tributary streams" are spawning and rearing habitat for fluvial and adfluvial populations; spawning also in "mainstem rivers, large and small tributaries … intermittent streams" | width / qual | Stewart et al. 2007 (DFO NWT) | Table 1, p. 4; p. 11 | No discharge number. |
| GR | spawn | qualitative | "Grayling spawn in a wide variety of habitats, including mainstem rivers, large and small tributaries" | qual | Stamford et al. 2017 (FWCP synthesis) | p. 10 | Williston. |
| GR | rear | min / max | **no discharge number in any source** | – | Stamford et al. 2017 p. 10: reaches that warm quickly are prime spawning and early-rearing habitat "but can also be too small and possibly warm for adult rearing". Stewart 2007 Table 1: rivers are feeding and overwintering habitat. Roberge 2002 (Arctic grayling text before Table 73): grayling inhabit "large cold rivers, and smaller, rocky tributary streams". | – | Adults rear in the Anzac and Table rivers and the Parsnip mainstem (Parsnip trend reports). The literature argues against a cap; it gives no minimum. |
| KO | spawn | observed range | spawning in lower Davidson Creek at **MAD 0.369–0.403 m³/s**; not in middle Davidson (MAD 0.281–0.345), because "kokanee do not migrate this high" | MAD (watershed model nodes) | AMEC 2015, Blackwater Instream Flow Study | §3.2.1 | Nechako Plateau, BC. The upstream limit is attributed to migration, not to flow. Kind: doc. |
| KO | spawn | observed (lower) | KO spawn in reaches 1–3 of Creek 661, whose mouth has **MAD 0.283 m³/s**. The modelled section's upstream end, used by RB only, has MAD 0.105 | MAD | AMEC 2015 | §3.2.3 (Creek 661) | KO spawning therefore occurs at MAD ≤ 0.283 and above 0.105. The exact MAD at the KO upstream limit is not stated. KO absent from Creek 705 (MAD 0.239–0.258), reason not given. |
| KO | spawn | max (observed) | "stream spawner counts of the Upper Duncan" River, which has "mean annual discharge of 62.5 m3/s" | MAD | Weir & Irvine 2023 (DDMMON-17) | text cache, near p. 18 | Kind: doc (MAD and spawning both stated). |
| KO | spawn | max (observed) | Lower Duncan River discharge "200-250 m3/s" at the start of the kokanee spawning and staging period | SPT (dam outflow, regulated) | Lawrence et al. 2012 (DDMMON-7) | Results | Regulated river. |
| KO | spawn | qualitative | spawning habitat type "lake tributaries or lake beaches" | qual | Ford et al. 1995 | kokanee summary table (OCR) | No size threshold. |
| KO | rear | – | lake only; out of scope | – | – | – | – |
| RB | spawn + rear | min (observed) | RB spawning and rearing in upper Creek 661 ("only used by rainbow trout"), where the section's upstream end has **MAD 0.105 m³/s** | MAD | AMEC 2015 | §3.2.3 | Middle Davidson (MAD 0.281–0.345) and Creek 705 (0.239–0.258) are also good RB spawning and rearing habitat (§3.2.1, §3.2.4). |
| RB | rear (0+) | min (observed) | 0+ RB at Henkel Ck site H2 ("Estimate 1 cfs flow", channel width ≈ 2 m; 18 fish) and Nadina R. site N2 ("Surface flow is intermittent and estimated at 1 cfs"; 143 fish over 2 passes). **1 cfs = 0.028 m³/s** | LSF (Aug 1987 spot estimate) | Bustard 1988 (Francois Lake tributaries) | pdf pp. 78 and 90 (App. 4 site forms); Henkel text pdf p. 29 | Henkel watershed is 50 km² with mostly subsurface late-summer flow. A late-summer flow is far below MAD (inference). |
| RB/ST | rear (juvenile) | min/max envelope | South-central California Coast ESU: lower bound complete **0.000763**, 95 % **0.002**, consensus 0.0061; upper bound consensus 0.09257, 95 % 0.26984, complete 0.280266 m³s⁻¹. Southern California ESU: 0.000254 / 0.0008 / 0.00229 and 0.09842 / 0.15412 / 0.181588 | SUM ("Summer Discharge") | Boughton & Goslin 2006, Table 8, reproduced in Sheer et al. 2009 | Sheer p. 21 | Anadromous juvenile O. mykiss, southern range. The upper bound reflects the streams sampled, not avoidance (inference). Poor transfer to interior BC. |
| RB/ST | rear | curve | steelhead suitability 0 only at 0; 1.0 to ~20 m³/s; 0.75 at ≥ ~78 m³/s | MAD | Agrawal et al. 2005 | Fig. 1, p. 10 | Never reaches 0 at high flow, so there is no cap. |
| RB | rear | width | BFW < 2.05 m = MEDIUM (no LOW or zero class for small streams with gradient 0.85–7.4 %); BFW ≥ 8.05 m = MEDIUM | width | Porter et al. 2008 | p. 67 | No small-stream exclusion and no large-stream exclusion. |
| RB | rear | drainage area | small streams (< 13 km²) "predominantly occupied by cutthroat"; large (> 130 km²) by steelhead | drainage area | Hartman & Gill 1968 (**not in Zotero**; abstract only via web) | abstract | Coastal SW BC, anadromous context. This is relative dominance, not absence. |
| RB | spawn / rear | max | **no source gives one** | – | – | – | RB use the Nadina, Stellako and similar rivers (Bustard 1988). Porter 2008 has no zero class at large widths. |

---

## 2. Width ↔ discharge conversions found

| Relationship | Units | Region | Source | Page |
|---|---|---|---|---|
| **w = 1.710 Q^0.471** | w = channel width (m), Q = mean annual flow (ft³/s) | Nushagak and Kvichak, Alaska | Woll et al. 2017 | p. 36 (Fig. 16) |
| **ACW = 2.19108 + 1.32366 · √D** | ACW = active channel width (units not stated in Agrawal; presumably m); D = MAD (ft³/s) | coastal Oregon (Burnett et al. 2003) | Agrawal et al. 2005, footnote 9 | p. 5 |
| summer flow 0.0057 m³/s ≈ wetted width ≤ 1.0 m | SUM | northern Rockies | Isaak et al. 2015, citing Peterson et al. 2013a | p. 2542 |
| depth: h = 0.360 Q^0.198 | m, ft³/s MAF | Alaska | Woll et al. 2017 | p. 36 |

Applied to link's current width minima. **All values here are inference.**

| width (m) | Woll → MAD | Burnett ACW → MAD |
|---|---|---|
| 1.0 | 0.32 cfs = 0.0091 m³/s | undefined (ACW ≥ 2.19 m at D = 0) |
| 1.5 (BT/GR/RB rear min) | 0.757 cfs = 0.0214 m³/s | undefined |
| 2.0 (BT/KO/RB spawn min) | 1.395 cfs = 0.0395 m³/s | undefined |
| 3.05 (Porter BT LOW/HIGH split) | 3.416 cfs = 0.0967 m³/s | – |
| 4.0 (GR spawn min) | 6.075 cfs = 0.172 m³/s | 1.868 cfs = 0.0529 m³/s |
| 5.0 | 9.757 cfs = 0.276 m³/s | 4.503 cfs = 0.128 m³/s |

The two conversions disagree by about 3× at 4 m, and **neither is from BC**. bcfishpass's
BC channel-width model (Poisson Consulting) is built from upstream area and precipitation,
not from discharge. No BC width–MAD relationship was found in the library. **Suggestion:**
link has modelled width and `mad_m3s` on the same segments in the discharge-covered
groups, and fitting the empirical relation there would be BC-native.

---

## 3. Verdicts per species × stage

**BT spawning.**
- **Minimum:** no source gives a MAD minimum. The best quantitative evidence is Hagen et
  al. 2015: redds were found at September spawning-time discharges as low as
  **0.25–0.30 m³/s**, and none in the one 0.12 m³/s reach. That is n = 15 reaches, measured
  in September, and censored by a survey design that skipped streams under 2 m wetted
  width. The 2 m wetted-width expert limit converts to roughly **0.04 m³/s MAD** under
  Woll's Alaskan equation (inference).
- So the literature brackets a MAD minimum loosely, somewhere around 0.04 to 0.3 m³/s.
  #302's measure-first distribution of `mad_m3s` at BT spawning locations should set it.
- **Maximum:** nothing supports a cap; use 9999.

**BT rearing.**
- **Minimum:** the only discharge number is Isaak et al. 2015's summer-flow trim of
  **0.0057 m³/s**, about 1 m wetted width. Its MAD equivalent is larger (by an amount not
  known). Width evidence (Dunham: 2 m wetted; Porter: < 3.05 m BFW is LOW, not zero) points
  to a rearing minimum **below** the spawning minimum, which matches the 1.5 m vs 2 m width
  split link already uses.
- **Maximum:** none supported; use 9999.

**GR spawning.**
- **Minimum:** no MAD number in the literature. Grayling spawned at freshet flows of
  **0.21–0.25 m³/s** in a constructed NWT channel, which is the smallest stream with a
  number. Its MAD is likely lower (inference). Qualitative sources say "small (~10 m wide)"
  tributaries and also intermittent streams. The current 4 m width minimum (≈ 0.05–0.17
  m³/s by conversion) has no discharge-literature backing.
- **Maximum:** a cap is contradicted. Grayling spawn in rivers with spawning-time
  discharge of about 400 m³/s (Fond du Lac). Use 9999.

**GR rearing.**
- **Minimum:** no discharge number. One qualitative statement says small, warm tributaries
  may be too small for **adult** rearing, but they are prime for fry. It does not support a
  single minimum.
- **Maximum:** adults use large rivers, so a cap is contradicted. Use 9999. Set the minimum
  from observations.

**KO spawning.**
- **Minimum:** documented spawning in BC streams at **MAD 0.369–0.403 m³/s** and in a
  creek whose mouth MAD is **0.283 m³/s** (AMEC 2015). In both, the upstream limit is
  attributed to how far kokanee migrate, not to flow. No literature minimum exists.
  0.28 m³/s is an observed value, not a threshold.
- **Maximum:** a cap is contradicted. Kokanee spawn in the Upper Duncan River
  (**MAD 62.5 m³/s**) and stage in the Lower Duncan at 200–250 m³/s. Use 9999.
- KO rearing is lake only and is not in scope.

**RB spawning and rearing (resident).**
- **Minimum:** documented spawning and rearing at **MAD ≈ 0.105 m³/s** (upper Creek 661).
  0+ fish were found at late-summer flows of about **0.028 m³/s** (1 cfs), including an
  intermittent reach. California juvenile O. mykiss envelopes reach summer flows of
  **0.002 m³/s**. Discharge-based IP curves (Agrawal, Burnett) give steelhead zero
  suitability only at about 0. A low rearing minimum is consistent with all of this, in
  the range of bcfp's ST 0.02 or CO 0.03 m³/s, but none of it is a fitted RB threshold.
  The spawning minimum should be at or above the rearing minimum (by analogy with every
  other species); no RB-specific spawning number exists below 0.105.
- **Maximum:** nothing supports a cap; use 9999.

**Across all four species.**
- **No source supports a MAD maximum.** Rebellato et al. 2024 explicitly concede that
  their upper bounds excluded used habitat.
- **No source gives a fitted MAD minimum for BT, GR, KO or RB.** Every number above is an
  observation at sites, a summer or spawning-time flow, or a width converted with a
  non-BC equation.
- The literature can bound and sanity-check values; it cannot set them. #302's
  observation-based distribution, scored out-of-sample, has to.

---

## 4. Gaps and things not read

- **Unverified:** the CH/CO/SK/ST spawning minimums 0.46 / 0.164 / 0.175 / 0.447. The
  following cited sources were not checked: Sloat et al. 2017, McMahon 1983, Raleigh &
  Miller 1986 (Zotero `QVS9MZ3G`), and Neuman & Newcombe 1977 App. 3. That appendix's
  rotated tables were not OCR-readable.
- **Not checked:** the CO rearing 0.03 (Sheer gives Agrawal's coho minimum as 0.01) and the
  rearing caps 40 and 60, which look like readings off Agrawal Fig. 1 axes (inference).
- **Paywalled, not read:** two Michigan grayling habitat papers that may use stream size
  or flow. Goble et al. 2021, J. Fish Wildl. Manage. 12(2):540; and "A landscape approach
  for identifying potential reestablishment sites … Arctic grayling … in Michigan",
  Hydrobiologia 849:1397–1415 (2022), DOI 10.1007/s10750-021-04791-8.
- **Seen in a search result only, not read:** USFWS, "Arctic Grayling Spawning Access
  Minimum Requirements Analysis Framework Workbook" (Montana).
- **Read for discharge, nothing found:**
  - Keeley & Slaney 1996: microhabitat depth/velocity only, no discharge or stream size.
  - Roberge et al. 2002: no species discharge thresholds.
  - McPhail & Baxter 1996, Rieman & McIntyre 1993, Hagen & Weber 2019, Hagen et al. 2020,
    Hagen & Sary 2023, BC BT Management Plan 2023: no discharge thresholds.
  - The Parsnip grayling reports (Bottoms et al. 2023, Hagen & Stamford 2023, Martins et
    al. 2022): no discharge thresholds.
- **DV:** no DV-specific discharge source.
- **No BC-fitted width–MAD relation** in the library.

---

## 5. References

1. Rebellato, B., et al. 2024. *Effects of rail infrastructure on Pacific salmon and steelhead habitat connectivity in British Columbia.* Canadian Wildlife Federation. https://cwf-fcf.org/en/resources/research-papers/BC_report_formatted_final.pdf — Zotero `Z8AUF79B`.
2. Agrawal, A., Schick, R.S., Bjorkstedt, E.P., et al. 2005. *Predicting the potential for historical coho, Chinook and steelhead habitat in northern California.* NOAA-TM-NMFS-SWFSC-379. — Zotero `A4SLUPQH`.
3. Sheer, M.B., Busch, D.S., et al. 2009. *Development and management of fish intrinsic potential data and methodologies: State of the IP 2008 summary report.* PNAMP Series 2009-004 (USGS). — Zotero `MWMTV4UZ`.
4. Burnett, K.M., Reeves, G.H., Miller, D.J., Clarke, S., Vance-Borland, K., Christiansen, K. 2007. Distribution of salmon-habitat potential relative to landscape characteristics and implications for conservation. *Ecological Applications* 17(1):66–80. — Zotero `UJLHGGJA`.
5. Woll, C., Albert, D., Whited, D. 2017. *A preliminary classification and mapping of salmon ecological systems in the Nushagak and Kvichak watersheds, Alaska.* The Nature Conservancy. — Zotero `JBW4EK3H`.
6. Bjornn, T.C., Reiser, D.W. 1991. Habitat requirements of salmonids in streams. *AFS Special Publication* 19:83–138. — OCR from prior review (citekey `bjornn_reiser1991HabitatRequirements`).
7. Neuman, H.R., Newcombe, C.P. 1977. *Minimum acceptable stream flows in British Columbia: a review.* BC Fish & Wildlife Branch, Fisheries Management Report 70. — Zotero `KS2IV6PC` / `I44TTT4S`; scanned, OCR'd here.
8. Roberge, M., et al. 2002. *Life history characteristics of freshwater fishes occurring in British Columbia and the Yukon, with major emphasis on stream habitat characteristics.* Can. MS Rep. Fish. Aquat. Sci. 2611. — Zotero `9GNZYYVS` (duplicates `B3TYJ9I9`, `LFB9P7A2`).
9. Hagen, J., Williamson, S., Stamford, M., Pillipow, R. 2015. *Critical habitats for bull trout and Arctic grayling within the Parsnip River and Pack River watersheds.* Prepared for McLeod Lake Indian Band. — Zotero `NCS2F8F8` (duplicate `DLR4ZPAU`).
10. Isaak, D.J., et al. 2015. The cold-water climate shield: delineating refugia for preserving salmonid fishes through the 21st century. *Global Change Biology* 21:2540–2553. DOI 10.1111/gcb.12879. — Zotero `X9HPSBV4`.
11. Dunham, J.B., Chandler, G.L. 2001. *Models to predict suitable habitat for juvenile bull trout in Washington State.* CMER 01-103. — Zotero `V9QT2NM2`.
12. Porter, M., et al. 2008. *Developing fish habitat models for broad-scale forest planning in the southern interior of B.C.* ESSA/FSP Y081231. — Zotero `8QNTR5CZ`.
13. House, P.A. 2021. *Interdisciplinary approaches to enhance biological data collection and understanding of Arctic grayling (Thymallus arcticus) spawning behaviour.* MSc thesis, Thompson Rivers University. — Zotero `GGDPSJFE` (att).
14. Stewart, D.B., Mochnacz, N.J., Reist, J.D., Carmichael, T.J., Sawatzky, C.D. 2007. *Fish life history and habitat use in the Northwest Territories: Arctic grayling (Thymallus arcticus).* Can. MS Rep. Fish. Aquat. Sci. 2797. — Zotero `5TIJUF5Q`.
15. Stamford, M., Hagen, J., Williamson, S. 2017. *FWCP Arctic grayling synthesis report.* FWCP Peace Region. — Zotero `DWW6U2TF`.
16. AMEC Environment & Infrastructure. 2015. *Blackwater Gold Project, Appendix 5.1.2.6D: Instream Flow Study.* Prepared for New Gold Inc. — Zotero `5VYWA6XA` (text cache only; PDF not on this machine).
17. Weir, T., Irvine, A. 2023. *Duncan Reservoir kokanee stock assessment, implementation year 3 (2018) and 2016–2018 synthesis report* (DDMMON-17). — Zotero `2CJGDYHM`.
18. Lawrence, C., Irvine, R., Porto, L. 2012. *Duncan Dam Project Water Use Plan: Lower Duncan River water quality monitoring (DDMMON-7), year 2 synthesis report.* — Zotero `K3UBXFSV` (att).
19. Bustard, D. 1988. *Assessment of rainbow trout recruitment from streams tributary to Francois Lake.* Prepared for BC Conservation Foundation. — Zotero `A65W895X`.
20. Ford, B.S., et al. 1995. *Literature reviews of the life history, habitat requirements and mitigation/compensation strategies for thirteen sport fish species in the Peace, Liard and Columbia River drainages of British Columbia.* Can. MS Rep. Fish. Aquat. Sci. 2321. — Zotero `BYBWUKUG`; scanned, OCR from prior review.
21. Keeley, E.R., Slaney, P.A. 1996. *Quantitative measures of rearing and spawning habitat characteristics for stream-dwelling salmonids.* WRP Project Report 4. — Zotero `2DFMCG9L`.
22. Lewis, A., Ganshorn, K. 2007. *Literature review of habitat productivity models for Pacific salmon species.* Ecofish Research, for DFO. — Zotero attachment `5J6W8GS8` (att). Context only (MAD as an indicator); no species thresholds.
23. Hartman, G.F., Gill, C.A. 1968. Distributions of juvenile steelhead and cutthroat trout (*Salmo gairdneri* and *S. clarki clarki*) within streams in southwestern British Columbia. *J. Fish. Res. Board Can.* 25(1):33–48. DOI 10.1139/f68-004. — **Not in Zotero**; abstract only.
24. Boughton, D.A., Goslin, M. 2006. *Potential steelhead over-summering habitat in the south-central/southern California coast recovery domain: maps based on the envelope method.* NOAA-TM-NMFS-SWFSC-391. — **Not in Zotero**; read only via Sheer et al. 2009 Table 8.
25. Peterson, D.P., Rieman, B.E., Young, M.K., Brammer, J.A. 2013. Patch size but not short-term isolation influences occurrence of westslope cutthroat trout above human-made barriers. *Ecology of Freshwater Fish* (volume/pages not verified) — **Not in Zotero; not read** (cited by Isaak for the flow–width link).
26. smnorris/bcfishpass@f8db4b9: `parameters/example_cwf/parameters_habitat_thresholds.csv` and `docs/03_model_habitat_linear.md`. Local clone.
