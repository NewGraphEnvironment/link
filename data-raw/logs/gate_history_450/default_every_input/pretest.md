# Pre-run gate (link#372)

- config `default` (chain: default): no build of it or of any config it extends on this database, so every input counts as changed (link#450)
- link `f05c30f40a04..f05c30f40a04`; fresh `v0.52.0..v0.52.0`
- per input 2 groups; bound 3 x last minutes (`fresh_nohistory_x.log`, or `data-raw/logs/build_minutes.csv` where newer, scaled to m1 at speed 1.31; 60 min where neither has the group), floor 5 min; statement bound <= 30 min

## Changed files (0)

| repo | file | inputs |
|---|---|---|
| link | `(no` | crossings, dams, gradient, near_river_conn, obs_upstream, observations, segments |

## Inputs

### crossings (`data-raw/pretest/crossings.sql`)

Top five among groups the config models: BULK 1,780; HORS 1,156; MCGR 1,081; ELKR 792; PARS 773.

### dams (`data-raw/pretest/dams.sql`)

Top five among groups the config models: OKAN 233; SAJR 109; VICT 106; STHM 95; MFRA 75.

### gradient (`data-raw/pretest/gradient.sql`)

Top five among groups the config models: SETN 41,783; TOAD 32,051; OWIK 28,138; FINL 20,536; TOBA 20,354.

### near_river_conn (`data-raw/pretest/near_river_conn.sql`)

Top five among groups the config models: QUES 63,347; TAKL 32,346; CHIR 25,003; PCEA 19,000; LEUT 15,448.

### obs_upstream (`data-raw/pretest/obs_upstream.sql`)

Top five among groups the config models: LFRA 126,143; HARR 102,474; FRCN 87,488; LARL 58,912; SETN 43,683.

### observations (`data-raw/pretest/observations.sql`)

Top five among groups the config models: LFRA 29,180; UPCE 18,022; OKAN 15,352; LARL 12,180; SQAM 10,849.

### segments (`data-raw/pretest/segments.sql`)

Top five among groups the config models: SETN 66,083; TOAD 60,416; LIAR 53,476; OWIK 49,093; MORK 43,086.

## Picks

| group | inputs | last minutes (here) | measured on | from | bound (min) | statement bound (min) |
|---|---|---|---|---|---|---|
| QUES | near_river_conn | 18.8 | cypher-job3 | record | 56.3 | 30 |
| BULK | crossings | 6.6 | cypher-job1 | record | 19.9 | 20 |
| SETN | gradient,segments | 6.3 | m1 | record | 19.0 | 20 |
| LFRA | obs_upstream,observations | 6.2 | cypher-job1 | record | 18.6 | 19 |
| TOAD | gradient,segments | 3.5 | m1 | record | 10.4 | 11 |
| OKAN | dams | 3.1 | cypher-job2 | record | 9.2 | 10 |
| HARR | obs_upstream | 2.8 | m4 | record | 8.5 | 9 |
| TAKL | near_river_conn | 2.8 | cypher-job3 | record | 8.4 | 9 |
| UPCE | observations | 2.3 | cypher-job1 | record | 6.8 | 7 |
| HORS | crossings | 1.5 | m4 | record | 5.0 | 5 |
| SAJR | dams | 1.2 | cypher-job1 | record | 5.0 | 5 |

Estimated modelling: 55.1 min (sum of last minutes).

