#!/usr/bin/env bash
# launch.sh — the provincial `default` run for link#361, exactly as launched.
# Decisions: planning/active/task_plan.md "Decided at the gate". Buckets from
# buckets_default.md (measured minutes, equal speeds): first --focal is the
# dispatcher, the rest job1, job2, job3 in order. Run DETACHED, from a clean
# tree on the pushed branch, with bash >= 4 (the script re-execs the driver under
# the same bash, `$BASH`; a bare `bash` resolved to /bin/bash 3.2 under nohup):
#
#   cd ~/Projects/repo/link && nohup /opt/homebrew/bin/bash \
#     data-raw/logs/provincial_361/launch.sh > data-raw/logs/provincial_361/run.log 2>&1 &
#   disown
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
date -u > data-raw/logs/provincial_361/run.started
exec "$BASH" data-raw/study_area_run.sh \
  --cy-workspaces=job1,job2,job3 \
  --focal=ADMS,BBAR,BIGC,BLAR,BONP,BOWR,BRID,CARR,CHES,CHIL,CHIR,CHWK,CLWR,COTR,DEAD,DOGC,DRIR,EUCH,EUCL,FRAN,FRCN,GRNL,GUIC,HARR,HERR,HOLB,HORS,KHTZ,KTSU,LCHL,LCHR,LEUT,LFRA,LILL,LNIC,LNRS,LNTH,LSAL,LTRE,MAHD,MCGR,MFRA,MIDR,MORK,MURT,MUSK,NARC,NAZR,NECR,NICL,OKAN,QUES,SAJR,SALR,SETN,SEYM,SHUL,STHM,STUL,STUR,TABR,TAKL,TASR,THOM,TWAC,UCHR,UEUT,UFRA,UNRS,UNTH,UNUR,USHU,UTRE,WILL \
  --focal=CAMB,CARP,COMX,COWN,CRKD,FINA,FINL,FIRE,FOXR,GRAI,INGR,INKR,KINR,KISK,KITL,LBIR,LBTN,LHAF,LNAR,LOMI,LPCE,LPET,LRDO,MBNK,MESI,MILL,MORI,MURR,NAHR,NAKR,NASC,NASR,NATR,NBNK,OSPK,OWIK,PARA,PARS,PCEA,PINE,SAHD,SHER,SIML,SQAM,TAHS,TAYR,TOOD,TSAY,TSEA,UBIR,UBTN,UHAF,UNAR,UOMI,UPCE,UPET,WORC \
  --focal=ALBN,ATLL,BARR,BEAV,BLUR,CHUK,COAL,CRYL,DEAL,DEAR,DUNE,FONT,FROG,GATA,GLAR,HAYR,ISKR,JENR,KAHN,KAKC,KCHL,KETL,KITR,KLAR,KLIN,KNIG,KSHR,KUMR,KUSR,LDEN,LFRT,LIAR,LISR,LKEC,LMUS,LPRO,LRAN,LSIK,LSTR,MDEA,MESC,MFRT,MMUS,MPRO,MSTR,NECL,PITR,PORI,SAHT,SALM,SHEK,SPAT,STIR,SWIR,TAHR,TATR,TESR,TOAD,TSIT,TURN,TUTR,TUYR,UDEN,UFRT,UISR,UJER,UKEC,ULRD,UMUS,UPRO,USIK,USTK,VICT \
  --focal=ATNA,BABL,BABR,BELA,BRKS,BULK,BULL,CANO,CLAY,CLRH,COLR,DUNC,ELKR,GOLD,HOMA,JERV,KEEC,KHOR,KISP,KLUM,KOTL,KOTR,LARL,LKEL,LSKE,MORR,MSKE,NEVI,NIEL,NIMP,PARK,REVL,SANJ,SKGT,SLOC,SMAR,SMOK,SUST,TOBA,UARL,USKE,ZYMO \
  --config=default --schema=fresh_default \
  --run-label=provincial-241-default-361 \
  --recompute-jobs=8 \
  --refresh-primitives
