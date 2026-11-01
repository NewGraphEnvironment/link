# GUIC CH record above 1,400 m: misplaced (#402, Decision 2)

Record: bcfishobs.observations observation_key 091612fd01, fish_observation_point_id 117513,
source "FDIS Database: fshclctn_id 146376", 2012-08-15, juvenile chinook, matched (type A) to
blue_line_key 356111950, an unnamed order-2 tributary at 1,581 m.

Source: EcoCat report 42693, "Fish Collection Permit KA12-81148 Guichon Creek"
(Summit Environmental Consultants, Dec 2012): "Fish salvage completed in order for the Lower
Nicola Indian Band to place riprap in the creek channel for scour protection."
Page: http://a100.gov.bc.ca/pub/acat/public/viewReport.do?reportId=42693
Data file: https://a100.gov.bc.ca/pub/acat/documents/r42693/KA12-81148_1401992130885_1991802827.xls
(pulled 2026-11-01, 3,809,792 bytes; not committed, fetch it from the link).

What the permit file says:
- Step 1 sites 1 and 2: Guichon Creek, 00000GUIC, UTM 10 639474 E 5607899 N, method "GIS".
  Site 3: Guichon Creek, UTM 10 652001 E 5558004 N.
- Step 2: chinook juveniles at sites 1 (4 fish, 67-142 mm) and 2 (1 fish, 70 mm), minnow traps.

Placed on FWA (fwapg, 2026-11-01):
- Sites 1-2 point: 50.6063 N, 121.0289 W. 7 m from blue_line_key 356111950 (1,581 m) and
  83 m from the Guichon Creek headwaters (blue_line_key 356364119, order 3, 1,567 m).
- Site 3 point: 50.1547 N, 120.8721 W. 2 m from Guichon Creek's main stem (order 7, 597 m),
  near the Nicola, where Lower Nicola Indian Band's reaches are.

Reading: the record's coordinates are the submitter's own for sites 1-2, and they put a
riprap salvage for Lower Nicola Indian Band in the creek's headwaters, 50 km and about 1,000 m
above site 3. The fish are real; the location is wrong. The likely site is lower Guichon Creek.

Effect: GUIC is already marked present for CH (8 CH records in GUIC, 1991-2012), so no cell
changes. The record should be a data_error (misplaced) row in observation_exclusions.csv in the
applying PR, and it must not be read as chinook passing a gradient barrier in the
access-gradient review (it sits above a GRADIENT barrier with no other record).
