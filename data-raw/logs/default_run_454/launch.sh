#!/usr/bin/env bash
# launch.sh — the provincial default run for link#454, exactly as launched.
# Decisions: planning/active/task_plan.md "Decided at the gate". Buckets from
# buckets.md (study_area_buckets.R --atom=group --config=default on fresh's 246 groups,
# minutes from fresh_default_history, KTSU and OKAN at the median, plan.tsv kept for the
# calibrator): first --focal is the dispatcher (m4), then worker1 (m1), then job1, job2, job3.
# BCFISHOBS_DIR must name a clean clone of bcfishobs at the HEAD the hosts load from.
# Run DETACHED, from a clean tree on the pushed branch, with bash >= 5.1:
#
#   BCFISHOBS_DIR=<clean clone> nohup /opt/homebrew/bin/bash \
#     data-raw/logs/default_run_454/launch.sh > data-raw/logs/default_run_454/run.log 2>&1 &
#   disown
#
# PREFLIGHT=1 runs the same command with --preflight-only (no spend).
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${BCFISHOBS_DIR:?set BCFISHOBS_DIR to a clean bcfishobs clone}"
export BCFISHOBS_DIR
pre=()
[ "${PREFLIGHT:-0}" = 1 ] && pre=(--preflight-only)
[ "${PREFLIGHT:-0}" = 1 ] || date -u > data-raw/logs/default_run_454/run.started
exec "$BASH" data-raw/study_area_run.sh "${pre[@]}" \
  --workers=m1 \
  --cy-workspaces=job1,job2,job3 \
  --buckets-exact \
  --focal=HARR,FRCN,THOM,LNIC,STHM,GUIC,SHUL,USHU,BRID,LCHR,TWAC,BLAR,HORS,TABR,LSAL,MIDR,DRIR,LIAR,MMUS,LKEC,UMUS,MDEA,LPCE,LHAF,UBTN,MILL,UHAF,OSPK,LSTR,MESC,KLAR,SLOC,LSKE,LKEL,MORR,LNAR,NASR,TAYR,SHER,SAHD,KITL,BRKS,JERV,KEEC,KHTZ,KSHR,PARK,SALM,SMOK,UNUR,VICT,WORC \
  --focal=SETN,BBAR,DEAD,CLWR,DOGC,GRNL,BIGC,NARC,TASR,MORK,WILL,NECR,SALR,STUR,LNRS,UNRS,BEAV,MFRT,TOAD,UFRT,LBTN,PARA,PARS,LOMI,MESI,FOXR,BARR,MSTR,USTK,BULL,CLRH,COLR,KLUM,ZYMO,USKE,LBIR,TESR,GLAR,JENR,SWIR,NAKR,TSEA,ATLL,TSAY,CLAY,COMX,COWN,HOMA,KNIG,NBNK,NEVI,NIEL,OWIK,PORI,SEYM \
  --focal=LFRA,NICL,MURT,CHIR,SAJR,COTR,EUCL,BOWR,CHIL,MUSK,FRAN,LTRE,COAL,FONT,LPRO,LSIK,KAHN,LRAN,USIK,BLUR,DEAL,FROG,GATA,PINE,UPCE,NATR,FINL,DUNC,REVL,SMAR,CANO,KOTR,BULK,SUST,UBIR,NAHR,UPET,LDEN,CAMB,KETL,KITR,KTSU,MORI,SIML,TOBA \
  --focal=LILL,BONP,ADMS,UNTH,MAHD,MFRA,UCHR,CARR,EUCH,NAZR,MCGR,UFRA,HERR,LEUT,DUNE,LFRT,LMUS,ULRD,KISK,CARP,CRKD,FIRE,STIR,TUYR,PITR,UISR,SPAT,LARL,KHOR,KISP,MSKE,KINR,UNAR,UJER,TUTR,ALBN,GRAI,KLIN,MBNK,NECL,OKAN,SKGT,SQAM,TAHS,TATR \
  --focal=CHWK,LNTH,QUES,LCHL,CHES,STUL,UTRE,UEUT,TAKL,DEAR,MPRO,UKEC,UPRO,CRYL,TURN,MURR,PCEA,FINA,INGR,TOOD,UOMI,LISR,ISKR,TAHR,KAKC,KOTL,UARL,ELKR,BABR,BABL,INKR,LPET,KUSR,BELA,ATNA,UDEN,GOLD,HOLB,KUMR,LRDO,NASC,NIMP,SANJ,TSIT \
  --config=default --schema=fresh_default \
  --run-label=default-provincial-454 \
  --recompute-jobs=8 \
  --statement-timeout=30 \
  --auto-install
