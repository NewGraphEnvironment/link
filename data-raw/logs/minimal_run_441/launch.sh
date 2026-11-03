#!/usr/bin/env bash
# launch.sh — the provincial default_minimal run for link#441, exactly as launched.
# Decisions: planning/active/task_plan.md "Launch decisions: the provincial run". Buckets from
# buckets.md (study_area_buckets.R --atom=group on 246 focal groups, minutes from
# fresh_default_history, KTSU and OKAN at the median, plan.tsv kept for the calibrator):
# first --focal is the dispatcher (m4), then worker1 (m1), then job1, job2, job3.
# BCFISHOBS_DIR must name a clean clone of bcfishobs at the HEAD the hosts load from;
# the operator checkout holds files that are not this work, and the pre-flight refuses a dirty one.
# Run DETACHED, from a clean tree on the pushed branch, with bash >= 5.1:
#
#   BCFISHOBS_DIR=<clean clone> nohup /opt/homebrew/bin/bash \
#     data-raw/logs/minimal_run_441/launch.sh > data-raw/logs/minimal_run_441/run.log 2>&1 &
#   disown
#
# PREFLIGHT=1 runs the same command with --preflight-only (no spend).
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${BCFISHOBS_DIR:?set BCFISHOBS_DIR to a clean bcfishobs clone}"
export BCFISHOBS_DIR
pre=()
[ "${PREFLIGHT:-0}" = 1 ] && pre=(--preflight-only)
[ "${PREFLIGHT:-0}" = 1 ] || date -u > data-raw/logs/minimal_run_441/run.started
exec "$BASH" data-raw/study_area_run.sh "${pre[@]}" \
  --workers=m1 \
  --cy-workspaces=job1,job2,job3 \
  --buckets-exact \
  --focal=FRCN,SETN,BONP,LNIC,NICL,LCHR,NARC,TASR,EUCL,STUR,LNRS,LSIK,KAHN,LKEC,LRAN,BLUR,DEAL,KISK,MURR,UPCE,PARS,FIRE,LSTR,STIR,PITR,SLOC,DUNC,SMAR,CANO,LKEL,KINR,UNAR,INKR,NAKR,SHER,SAHD,ALBN,HOLB,HOMA,KUMR,MBNK,OKAN,OWIK,PARK,PORI,SMOK,TATR,WORC \
  --focal=HARR,CHWK,SHUL,MFRA,USHU,COTR,BLAR,CARR,HORS,LCHL,NAZR,MUSK,CHES,FRAN,LEUT,TAKL,MFRT,COAL,UFRT,LPRO,ULRD,USIK,TURN,LBTN,PCEA,FINA,INGR,MESC,TUYR,CLRH,KLUM,MSKE,LNAR,TESR,JENR,LPET,UPET,ATLL,BELA,ATNA,KITL,BRKS,GOLD,JERV,KEEC,KITR,NIMP,SIML,TAHS \
  --focal=THOM,BBAR,DEAD,LNTH,CLWR,UNTH,MURT,BRID,TWAC,UCHR,TABR,BOWR,CHIL,SALR,STUL,UTRE,MIDR,DUNE,LMUS,DEAR,UMUS,GATA,PINE,NATR,OSPK,UOMI,BARR,ISKR,USTK,SPAT,BULL,KHOR,BULK,BABR,MORR,TAYR,NAHR,KUSR,CLAY,COMX,COWN,KETL,KLIN,LRDO,NECL,SQAM,TOBA,VICT \
  --focal=LFRA,LILL,STHM,DOGC,MAHD,SAJR,EUCH,MORK,NECR,HERR,UEUT,UNRS,DRIR,BEAV,LIAR,FONT,MMUS,UKEC,UPRO,CRYL,LPCE,MILL,UHAF,CRKD,FINL,FOXR,LISR,UISR,KOTL,UARL,KISP,ZYMO,BABL,LBIR,UBIR,GLAR,SWIR,TUTR,TSAY,UDEN,GRAI,KSHR,MORI,NBNK,NIEL,SALM,SEYM,SKGT \
  --focal=ADMS,GRNL,GUIC,BIGC,CHIR,QUES,LSAL,WILL,MCGR,UFRA,LTRE,LFRT,TOAD,MPRO,MDEA,FROG,LHAF,UBTN,PARA,CARP,LOMI,MESI,TOOD,MSTR,TAHR,KAKC,KLAR,LARL,REVL,ELKR,KOTR,COLR,LSKE,SUST,USKE,NASR,UJER,TSEA,LDEN,CAMB,KHTZ,KNIG,KTSU,NASC,NEVI,SANJ,TSIT,UNUR \
  --config=default_minimal --schema=fresh_default_minimal \
  --run-label=minimal-provincial-441 \
  --recompute-jobs=8 \
  --statement-timeout=30 \
  --auto-install
