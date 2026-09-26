# Literature review for link#284: CH and BT gradient and channel-width thresholds

**Compiled:** 2026-09-26. **Produced by:** a single agent. It read the local Zotero library through read-only SQLite, OCR'd two scanned PDFs, and searched the web. Nothing in Zotero was added or edited.

## How to read this file

- **Units.** "%" means percent gradient. The model stores gradient as a proportion, so 4.49 % is 0.0449. Width is labelled **BFW** (bankfull), **wetted**, or "channel width (unspecified)", which means the source does not say which.
- **Kind** tells you what sort of number each value is:
  - **param**: a model parameter someone chose.
  - **HSI**: a habitat suitability or intrinsic-potential (IP) curve breakpoint.
  - **max-obs**: the largest value observed.
  - **dist**: a statistic describing where fish were found.
  - **pref**: a preference or optimum.
  - **expert**: expert opinion.
  - **qual**: a qualitative statement only.
- **Zotero MCP did not work.** Every call failed with `Missing required environment variables ZOTERO_LIBRARY_ID and ZOTERO_API_KEY`. I queried a copy of `zotero.sqlite` instead and read the `.zotero-ft-cache` files or ran `pdftotext` on the PDFs.
- **Two sources were OCR'd with tesseract.** Bjornn & Reiser 1991 and Ford et al. 1995 are scanned images with no text layer. Their quotes may carry minor OCR noise.
- **Current link values match an upstream file exactly.** They are the same as bcfishpass `parameters/example_newgraph/parameters_habitat_thresholds.csv` (smnorris/bcfishpass@a702229).

---

## 0. Where the current thresholds come from (question 6)

| Parameter set | CH spawn grad max | CH spawn CW min | CH rear grad max | CH rear CW min | BT spawn grad max | BT spawn CW min | BT rear grad max | BT rear CW min | Source |
|---|---|---|---|---|---|---|---|---|---|
| **link now** (= bcfp `example_newgraph`) | 0.0449 | 4 | 0.0549 | 1.5 | 0.0549 | 2 | 0.1049 | 1.5 | smnorris/bcfishpass@a702229 `parameters/example_newgraph/`. Its README says these are "slightly more generous than CWF thresholds to capture more areas for review". |
| bcfp `example_cwf` | 0.03 | 4 (plus MAD 0.46 m³/s) | 0.05 | 1.5 (plus MAD 0.28–100) | 0.0549 | 2 | 0.1049 | 1.5 | Same commit, `parameters/example_cwf/`. README: "gradient/discharge thresholds are as per literature (compiled/provided by CWF)". |
| bcfp `example_fptwg` | 0.04 | 4 | 0.05 | 1.5 | 0.05 | 2 | 0.074 | 1.5 | Same commit, `parameters/example_fptwg/`. No rationale file. |
| **Rebellato et al. 2024**, Table 1 (p. 6). CWF technical report; bcfp docs name it as the source for salmon and steelhead values. | 0–3 % | 4 m (no citation in the table) | 0–5 % | 1.5 m (no citation) | not covered | – | – | – | https://cwf-fcf.org/en/resources/research-papers/BC_report_formatted_final.pdf |

What each part of that table rests on:

- **CH spawning gradient 0–3 %.** Rebellato cites Busch et al. 2013 and Cooney & Holzer 2006.
- **CH spawning discharge 0.46–322.5 m³/s.** Rebellato cites Bjornn & Reiser 1991, Neuman & Newcombe 1977, Woll et al. 2017, Roberge et al. 2002, and Raleigh & Miller 1986.
- **CH rearing gradient 0–5 %.** Rebellato cites Woll et al. 2017 and Porter et al. 2008. I found **no 5 % cutoff in Porter et al. 2008**: a full-text grep for "5 %" and "0.05" came up empty. Woll et al. 2017 Table 17 uses 3–7 % and >7 %, not 5 % (see §1).
- **CH rearing discharge 0.28–100 m³/s.** Rebellato cites Agrawal et al. 2005.
- **The 4 m CH spawning width is the one width with a traceable origin.** Woll et al. 2017 (Zotero `woll_etal2017SalmonEcological`) Table 16, p. 84, rates CH spawning "Not Suitable" for "Channel size < 4m". Rebellato cites Woll for discharge, not width, so this link is my inference.
- **The 1.5 m rearing widths have no literature citation.** bcfp `docs/03_model_habitat_linear.md` says only: "Channel width thresholds are designed to eliminate very small streams from consideration."
- **BT has no cited source anywhere in bcfishpass.** Rebellato covers salmon and steelhead only.
- **FPTWG BT rearing 0.074 matches a Porter number, but that is my observation.** It equals Porter et al. 2008's rainbow trout CART split ("gradient >= 7.4 %", p. 67). No source says it was taken from there.

Access thresholds:

- **Species list.** bcfishpass docs (`02_model_access.html`): Pacific salmon 15 %, steelhead and WCT 20 %, **bull trout 25 %**. No citation is given.
- **Where 15 % for salmon comes from.** Rebellato et al. 2024 (p. 4): "Chinook, Sockeye and Coho salmon pass gradients up to 16% (WDFW 2009)". In BC data, "98% of Chinook (n=8,323) ... observations had a maximum downstream gradient of 15%. Based on these results, gradients ≥15% were considered barriers for all Pacific salmon". Kind: dist + param.
- **Where 25 % for BT comes from.** Norris & Mount 2016 (Zotero `norris_mount2016Fishpassage`), p. 6, §2.1.3.1: "25% was used as the maximum gradient for fish passage in Version 1 of the model and is still the gradient barrier threshold most often used". Barriers are segments of at least 100 m in classes of 10/15/20/25/30 %. Porter et al. 2014 (Zotero `porter_etal2014SkeenaSalmon`) pp. 8 and 47: the provincial model's criteria "are based on the strong swimming abilities of bull trout". So 25 % is a BT-derived provincial default, not a published passage limit.
- **FPTWG protocol has no habitat thresholds.** Fish Passage Technical Working Group 2014 (Zotero `fishpassagetechnicalworkinggroup2014FishPassage`) contains no gradient or width thresholds; I checked the full text.

The rearing "bridge" rule:

- **It is a bcfishpass rule.** bcfp `03_model_habitat_linear.md`: CH and BT rearing must be "<10km upstream of spawning with no stream segment of slope exceeding 5%" (BT: ">=5%").
- **No literature origin found.** Nothing states 5 % or 10 km as a connectivity rule.
- **Nearest analogue.** Cooney & Holzer 2006 exclude reaches ">5%" as spawning and rearing for yearling CH (see §1).

---

## 1. Chinook salmon (CH)

| Threshold | Value / range | Kind | Source (Zotero key; URL/DOI) | Page | Notes |
|---|---|---|---|---|---|
| **Spawning gradient, max: stream-type (interior, yearling)** | ">5%" excluded as spawning/rearing | expert + param | Cooney & Holzer 2006, Appendix C, ICTRT (`cooney_holzer2006AppendixInterior`) | C-7/C-8, "Determining Upstream and Downstream Extents" | "Stream reaches with gradients above 5% were also excluded as spawning/rearing areas for yearling Chinook salmon populations based on expert opinion and on a review of index reach data sets". Gradient is % over a 200 m reach. |
| Spawning gradient: stream-type, HSI table | BFW 3.7–25 m: 0–0.5 % Med/High/High; 0.5–1.5 % Low/Med/High; 1.5–4.0 % Low/Low/Med; **4.0–7.0 % Negligible/Low/Low; >7.0 % None**. BFW 25–50 m: 0–0.5 % None/Med/Med; ≥0.5 % None | HSI | Same source, Table C-1 | C-16 | The three ratings are for confined / moderate / wide valleys. The table allows some rating up to 7 %, but the text excludes >5 %. |
| Parr density vs gradient (stream-type) | "relatively high at gradients below 1.0 to 1.5 %"; "low at gradients exceeding 1.5 to 2.0 percent" | dist | Same source | C-10/C-11, "Gradient" | Idaho parr data (IDFG). |
| **Spawning gradient, max: ocean-type (coastal, fall/subyearling)** | Score 1 at 0–2 %; declining to **0.05 at 4 %**; 0.05 for 4–7 %; **0 above 7 %** | HSI | Busch et al. 2011/2013 (`busch_etal2011LandscapeLevelModel`, `shallinbusch_etal2013LANDSCAPELEVELMODEL`). River Res. Appl. 29(3):297–312, DOI 10.1002/rra.1597 | Table I, "Channel gradient" | "Chinook salmon have been found spawning in reaches up to 7% gradient (Montgomery et al., 1999; Sheer and Steel, 2006; Cooney et al., 2007)". Lower Columbia fall CH. |
| Spawning gradient: ocean-type, observed distribution | Chinook zone correlates with slopes **<1 %**; 100 % of Clearwater chinook-zone length has slope <0.03; ">0.03 reaches in rain-dominated systems should not support fall-spawning salmonids" | dist | Montgomery et al. 1999, CJFAS 56:377–387, DOI 10.1139/f98-181 (not in Zotero; http://skagitcoop.org/wp-content/uploads/ctpaper.pdf) | pp. 380–381, Table 2 | Western Washington, fall CH. Only 1 redd was seen in step–pool channels (Skagit). |
| Spawning gradient, general, BC compilation | "<1%" | dist (cited) | Roberge et al. 2002, Table 60 (`roberge_etal2002LifeHistory`) | p. 72 | Taken from Montgomery et al. 1999 (Skagit). |
| **Spawning gradient, min** | **No minimum found.** Every source's lowest class starts at 0 % and scores suitable (C&H: 0–0.5 % Med/High; Busch: 0–2 % = 1; Rebellato: "0–3"). | – | as above | – | No literature supports a 0.25 % floor. Low-gradient exclusions in the literature are for lakes and reservoirs (Busch) or very wide rivers (C&H: BF >50 m = None). |
| Spawning gradient, BC provincial parameter | 0–3 % | param | Rebellato et al. 2024, Table 1 | p. 6 | Cites Busch 2013 and Cooney & Holzer 2006. |
| **Spawning channel width, min: stream-type** | Lower limit **3.6 m wetted** (Table C-1: **BF <3.7 m = None**) | param (95th-percentile-low of redd reaches) | Cooney & Holzer 2006 | C-8 to C-9, "Stream Width"; C-16 | Based on "the 95th percentile low value for bankfull and wetted width" of redd-count index reaches. Sheer et al. 2009 p. 13 summarises C&H as "limited to reaches wider than 5.7 m". |
| Spawning channel width, min: ocean-type | "Channels **≤4 m** wide are assumed unsuitable" (BFW); spawning "infrequent in reaches less than **3 to 5 m** wide"; full suitability >20 m | HSI | Busch et al. 2011/2013 | "Channel width", Table I | Sheer et al. 2009 (p. 13) summarises Busch as "bankfull width <2 m" being a natural barrier. |
| Spawning channel size, min | "Channel size < 4m" = Not Suitable | HSI | Woll et al. 2017, Table 16 (`woll_etal2017SalmonEcological`) | p. 84 | Nushagak/Kvichak, Alaska. Likely origin of the 4 m bcfp width (inference). |
| Spawning stream order | Anadromous CH "spawned in a few third-order streams, but most were found in fourth- and fifth-order streams" | dist | Bjornn & Reiser 1991 (`bjornn_reiser1991HabitatRequirements`), citing Boehne & House 1983 | p. 89 | Oregon coast and Cascades. First-order streams "were not used by salmonids". |
| Spawning discharge, min | 0.46 m³/s (range 0.46–322.5) | param | Rebellato et al. 2024, Table 1 | p. 6 | Cites B&R 1991, Neuman & Newcombe 1977, Woll 2017, Roberge 2002, Raleigh & Miller 1986. |
| Spawning gravel patch | "about 6 m² of spawning gravel with a minimum width of 1 m" | HSI note | Raleigh et al. 1986, USFWS Biol. Rep. 82(10.122) (`raleigh_etal1986HabitatSuitablility`) | p. 22 | This is patch width, **not** stream width. The HSI model has **no gradient variable**. |
| **Rearing gradient, max** | Juveniles 0–8 % max; "very low IP value > 3.5%"; min MAD 0.28 m³/s | HSI | Agrawal et al. 2005, via Sheer et al. 2009 (`agrawal_etalPREDICTINGPOTENTIAL`, `sheer_etal2009DevelopmentManagement`) | Sheer p. 13–14 | Juvenile fall-run CH, N. California. Agrawal's own curves are figures only (Fig. 1). |
| Rearing gradient: stream order and gradient HSI | Suitability 1 for "Gradient 3-7%"; 0 for "Gradient >7%"; "Upstream gradient never exceeds 2%" | HSI | Woll et al. 2017, Table 17 | p. 85 | The table layout is garbled in the text layer; confirm against the PDF. Stream order 5–9 is high, 1–4 lower. |
| Rearing gradient: juvenile CPUE classes, BC interior | HIGH if gradient ≥3.25 % and BFW <2.6 m; MODERATE if ≥3.25 % and BFW ≥2.6 m, or <3.25 % and BFW <15 m; LOW if <3.25 % and BFW ≥15 m | dist (CART) | Porter et al. 2008, ESSA/FSP Y081231 (`porter_etal2008DevelopingFish`) | p. 67 | Thompson EDU FDIS electrofishing. The authors say classes are "not statistically significant" (p. 66). This does **not** support 5 % as a max. |
| Rearing gradient: non-natal, ocean-type | "channels steeper than **6.5%** [did] not have juvenile Chinook salmon present" | max-obs | Beamer et al. 2013 (`beamer_etal2013JUVENILECHINOOK`) | "Stream channel slope" section (TOC p. 51) | Whidbey Basin small streams. Surveyed slopes ranged <1 % to ~40 %. |
| Rearing gradient, BC provincial parameter | 0–5 % | param | Rebellato et al. 2024, Table 1 | p. 6 | Cites Woll 2017 and Porter 2008. Neither states 5 % (see §0). |
| Rearing gradient and width, BC observation | Juveniles in streams with "average bank-full width of 0.5 m" and "average watershed gradient of 1.2%" | dist (cited) | Roberge et al. 2002 citing Porter et al. 2000 (`porter_etal2000PredictiveModels`) | p. 71–72, Table 60 | The "0.5 m" figure is implausible and is probably a transcription error in Roberge. Check Porter et al. 2000 Table 2 before using it. |
| **Rearing min stream size** | MAD ≥0.28 m³/s (range 0.28–100); CW 1.5 m | param | Rebellato et al. 2024, Table 1 (discharge from Agrawal 2005; width uncited) | p. 6 | – |
| Rearing stream size: stream-type observation | CH juveniles >1 mile up only in tributaries "with stream widths averaging more than 18 feet (5.5 m)" | dist | Partridge & Platts 1978 (`partridge_platts1978Rearingchinook`) | text (no page captured) | South Fork Salmon River, Idaho. |
| **Access gradient** | 15 % (BC). Also 16 % (WA; Busch ">16%"; Sheer 2009: "16% for Chinook"). Also 20 % over >200 m (Cooney & Holzer, all ICB salmon/steelhead) | param / dist | Rebellato 2024 p. 4; Busch Table I text; Sheer et al. 2009 p. 26; Cooney & Holzer C-7 | – | Supports the current 0.15. |

## 2. Bull trout (BT)

| Threshold | Value / range | Kind | Source (Zotero key; URL/DOI) | Page | Notes |
|---|---|---|---|---|---|
| **Spawning gradient, max: reach scale** | **No numeric reach-scale maximum found.** | – | – | – | Every review states it qualitatively (rows below). |
| Spawning site gradient | "bull trout spawn in low gradient areas (**<1%**)" | dist (redd site) | Ford et al. 1995 (`ford_etal1995LiteratureReviews`), citing McPhail & Murray 1979 | p. 124 | Arrow Lake tributaries (adfluvial). This is microhabitat, not the reach gradient a GIS model sees. |
| Spawning gradient, qualitative | Sites "characterized ... by relatively low gradients" | qual | McPhail & Baxter 1996, BC Fish. Mgmt Rep. 104 (not in Zotero; https://www.nwcouncil.org/sites/default/files/App67_RevBT_LifeHist.pdf) | pp. 5–6, §3.1.1 | Mostly Columbia-system observations. |
| Spawning gradient, qualitative (contradictory) | Table 67 lists spawning gradient as "high". Text says "presumably in high gradient (Baxter and McPhail 1996)" and elsewhere "shallow (30–60 cm) low gradient areas" | qual | Roberge et al. 2002 | pp. 79–82, Table 67 | No number. |
| Adfluvial spawning, qualitative | Flathead adfluvial BT "preferentially select larger, lower gradient tributary reaches" (Graham et al. 1981) | qual | Hagen & Weber 2019 (`hagen_weber2019Limitingfactorsa`) | p. 21 | – |
| **Spawning + rearing (natal) gradient, max** | Reaches with slope **>15 %** trimmed ("<1% of species occurrences in regional fish database") | max-obs / param | Isaak et al. 2015, Global Change Biol. 21:2540–2553, DOI 10.1111/gcb.12879 (not in Zotero) | p. 2542, Materials and methods | Northern Rockies, juvenile-based occupancy. Relevant to both BT spawning and rearing max. |
| Natal habitat gradient distribution | BT cold-water habitats: slope **mean 7.96 %, median 7.89 %, min 1.62 %, max 14.7 %**; occupancy "negatively affected" by slope | dist | Isaak et al. 2015, Table 2 | p. 2544 | n = 512 habitats. Habitat-average slope, and the network was already trimmed at 15 %. |
| **Spawning stream size, min: migratory** | "No streams of **<2 m wetted width** were surveyed for spawning activity. In the personal experience of the authors, this corresponds with the limit of habitat use for migratory bull trout spawners." | expert | Hagen et al. 2015 (`hagen_etal2015Criticalhabitats`) | p. 22, §4.1.2 | Parsnip and Pack, BC. **Supports 2 m, but as wetted width** (the model uses channel width). |
| Spawning stream order: adfluvial, large-bodied (Williston) | Most important spawning reaches are "medium-sized reaches/tributaries of **5th and 6th order** streams" | dist | Hagen & Weber 2019 p. 21; Hagen & Sary 2023 (`hagen_sary2023BullTrout`) p. 3 | – | – |
| Spawning survey scope (Williston) | Potentially suitable reaches: "Generally: **3rd order and larger** tributaries of 10 km length or more" | param (survey design) | Hagen et al. 2020 (`hagen_etal2020CriticalSpawning`) | p. 30, fn 9 | – |
| Spawning and rearing stream size, BC general | "clean, cold stream reaches of small-to-moderate size (approximately **3rd order streams, and smaller**), where spawning and rearing take place for all Bull Trout populations" | qual/expert | BC MWLRS 2023 Management Plan (`b_c_ministryofwaterlandandresourcestewardship2023ManagementPlan`) | p. 16, §3.3 | This conflicts with the Williston 5th–6th order finding. Life history (resident vs adfluvial) probably explains the gap. |
| Spawning habitat type | "small streams" | qual | Ford et al. 1995, BT summary table | p. 117 | – |
| Resident vs migratory streams | Stream-resident streams "are smaller and have higher gradients than those occupied by adfluvial and fluvial populations" | qual | McPhail & Baxter 1996 | p. 13, §3.5.1.1 | – |
| Rearing and resident stream order | "second- to fourth-order streams"; "often were not found in the smallest headwater streams" (Mullan et al. 1992); "occurred most frequently in third- and fourth-order streams" (Shepard et al. 1984b) | dist (cited) | Rieman & McIntyre 1993, USFS GTR INT-302 (not in Zotero; https://www.fs.usda.gov/rm/pubs_int/int_gtr302.pdf) | "Habitat Relationships" (pdf p. 6; printed page not captured) | – |
| **Juvenile occurrence, min stream size** | Occurrence "positively associated with stream width, with occurrence very unlikely in streams less than **2 m wetted width**" (Dunham & Rieman 1999). Studies believe BT "select larger habitats (e.g., > 2 m in width)" | dist | Dunham & Chandler 2001, WA CMER 01-103 (not in Zotero; https://dnr.wa.gov/sites/default/files/2025-05/fp_cmer_01_103.pdf) | pp. 3 and 26 | WA sampled sites: gradient 0–10.02 % (mean 1.37 %), mean width 3.61–37.65 m (Table 2, p. 17). |
| Juvenile min stream size (flow) | Summer flow <0.0057 m³/s "approximates a wetted width ≤1.0 m" and was trimmed "because trout are rare in such small streams" | param | Isaak et al. 2015 | p. 2542 | – |
| Juvenile rearing capacity vs width (BC interior) | BFW <3.05 m = LOW; BFW 3.05–3.35 m with gradient <9.75 % = LOW, ≥9.75 % = MEDIUM; BFW >3.35 m = HIGH | dist (CART) | Porter et al. 2008 | p. 67 | "Bull trout showed the highest CPUE in higher gradient streams" (p. 66). |
| **Rearing gradient, max** | Natal/juvenile habitat trimmed at **15 %** (<1 % of occurrences above it) | max-obs | Isaak et al. 2015 | p. 2542 | Closest literature number to the current 0.1049. |
| **Use of steep (>5 %, >10 %) reaches** | Last-fish (resident BT-only) reaches: **7.5, 10, 20 and 22.5 %** | max-obs | Trotter 2000, TFW-ISAG1-00-001 (not in Zotero; geo.nwifc.org CMER), deriving from Ziller 1992 graphs | p. 9 | Four Sprague River (OR) headwater streams. Resident fish, mostly <190 mm FL. |
| Use of steep reaches, BC | BT had "highest CPUE in higher gradient streams" (Thompson). A MEDIUM class is defined at ≥9.75 % | dist | Porter et al. 2008 | pp. 66–67 | – |
| Juvenile microhabitat | Pools with velocity <0.25 m/s up to 1 m deep; runs <0.5 m/s, ~0.25 m deep | pref | Ford et al. 1995, citing McPhail & Murray 1979 | p. 120 | No gradient given. |
| Juvenile gradient range, Idaho | Snippet: "95% of reaches containing Bull Trout occurred at ... gradients between 0.3% and 11.6%"; occurrence and density "peaked at intermediate values" | dist | Voss et al. 2023, TAFS 152(6):835–848, DOI 10.1002/tafs.10443 (not in Zotero) | – | **Unverified.** Seen only in a search-engine summary. The full text is paywalled (403 and abstract only). |
| **Access gradient** | 25 % (BC provincial default, BT-based) | param | Norris & Mount 2016 p. 6; Porter et al. 2014 pp. 8, 47 | – | Compare Isaak 2015's 15 % occurrence envelope and the 20–22.5 % last-fish reaches (Trotter 2000). |

---

## Not in Zotero: suggested additions

1. Rebellato, B.D. et al. 2024. *Effects of rail infrastructure on Pacific salmon and steelhead habitat connectivity in British Columbia.* Canadian Wildlife Federation technical report. https://cwf-fcf.org/en/resources/research-papers/BC_report_formatted_final.pdf. This is the documented origin of bcfishpass CH thresholds.
2. Montgomery, D.R., Beamer, E.M., Pess, G.R. & Quinn, T.P. 1999. Channel type and salmonid spawning distribution and abundance. CJFAS 56:377–387. DOI 10.1139/f98-181.
3. Isaak, D.J. et al. 2015. The cold-water climate shield. Global Change Biology 21:2540–2553. DOI 10.1111/gcb.12879.
4. McPhail, J.D. & Baxter, J.S. 1996. A review of bull trout life-history and habitat use in relation to compensation and improvement opportunities. BC Fisheries Management Report 104.
5. Rieman, B.E. & McIntyre, J.D. 1993. Demographic and habitat requirements for conservation of bull trout. USFS GTR INT-302.
6. Dunham, J.B. & Chandler, G.L. 2001. Models to predict suitable habitat for juvenile bull trout in Washington State. CMER 01-103.
7. Dunham, J.B. & Rieman, B.E. 1999. Metapopulation structure of bull trout. Ecological Applications 9:642–655. This is the primary source for the <2 m wetted-width finding; I did not read it.
8. Trotter, P.C. 2000. Headwater fishes and their uppermost habitats. TFW-ISAG1-00-001. Also the primary it draws on: Ziller 1992.
9. Voss, N.S., Bowersox, B.J. & Quist, M.C. 2023. TAFS 152:835–848. DOI 10.1002/tafs.10443. Paywalled.
10. Healey, M.C. 1991. Life history of chinook salmon. In *Pacific Salmon Life Histories*, pp. 311–393. Not found in Zotero; I did not read it.
11. Fraley, J.J. & Shepard, B.B. 1989. Northwest Science 63:133–143. Not read.
12. Baxter, C.V. & Hauer, F.R. 2000. CJFAS 57:1470–1481. DOI 10.1139/f00-056. Not read.
13. Neuman, H.R. & Newcombe, C.P. 1977. Minimum acceptable stream flows in BC. Fish. Mgmt Rep. 70. Cited by Rebellato for discharge.

Housekeeping: Zotero has several duplicate records, for example `porter_etal2008DevelopingFish` in libraries 1, 6 and 9, and `cooney_holzer2006AppendixInterior` / `cooney_holzerAppendixInterior`. `bjornn_reiser1991HabitatRequirements` and `ford_etal1995LiteratureReviews` are image-only PDFs with no text layer.

## Gaps

- **BT spawning reach-gradient maximum.** No numeric reach-scale maximum exists in any source read. The 0.05 (FPTWG) and 0.0549 (link) values are uncited. The literature offers only:
  - <1 % at redd sites (McPhail & Murray via Ford 1995);
  - "relatively low gradients" (McPhail & Baxter 1996);
  - a 15 % natal-habitat envelope (Isaak 2015).
- **BT rearing gradient maximum.** 0.1049 (link) and 0.074 (FPTWG) are uncited. 0.074 equals Porter 2008's rainbow trout split, which may be a coincidence. The nearest evidence is:
  - the Isaak 2015 15 % trim and a 14.7 % max habitat slope;
  - last-fish reaches of 20–22.5 % for residents;
  - the Voss 2023 "0.3–11.6 %" (unverified).
- **BT by life history.** No source gives separate numeric gradient or width thresholds for resident vs fluvial vs adfluvial BT. Only qualitative contrasts exist:
  - residents live in smaller, steeper streams (McPhail & Baxter 1996);
  - Williston adfluvial fish spawn in 5th–6th order streams, and ≥2 m wetted width (Hagen 2015/2019).
- **Wetted vs bankfull for BT 2 m.** Both sources for 2 m say wetted width (Hagen 2015; Dunham & Rieman 1999). The model's 2 m is applied to modelled channel width. No source converts between the two.
- **CH rearing 5 %.** Rebellato attributes it to Woll 2017 and Porter 2008, but neither states 5 %. The only 5 % found is Cooney & Holzer's expert-opinion exclusion for yearling CH spawning and rearing.
- **CH rearing and spawning 1.5 m widths.** No literature origin. bcfp calls them a small-stream filter.
- **Rearing-to-spawning bridge (5 %, 10 km).** No literature origin found. It appears to be a bcfishpass design rule.
- **Stream-type vs ocean-type split for BC.** The stream-type numbers are from interior Columbia (Cooney & Holzer). The ocean-type numbers are from the Lower Columbia, western Washington and Alaska. No BC-specific CH spawning-gradient study was found.
- **Unread primary sources.** Healey 1991, Fraley & Shepard 1989, Baxter & Hauer 2000, Dunham & Rieman 1999, and the Agrawal 2005 figure curves were not read. Porter et al. 2000 Table 2 was unparseable in the text cache.
