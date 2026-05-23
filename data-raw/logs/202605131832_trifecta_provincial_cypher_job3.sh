#!/usr/bin/env bash
set -euo pipefail
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -L 63333:127.0.0.1:5432 db_newgraph -N &
TUNNEL_PID=$!
trap 'kill $TUNNEL_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 10); do
  nc -z localhost 63333 2>/dev/null && break
  sleep 0.5
done
cd ~/Projects/repo/link/data-raw
Rscript run_provincial_parity.R "--wsgs=SMOK,SPAT,SQAM,STHM,STIR,STUL,STUR,SUST,SWIR,TABR,TAHR,TAHS,TAKL,TASR,TATR,TAYR,TESR,THOM,TOAD,TOBA,TOOD,TSAY,TSIT,TURN,TUYR,TWAC,UARL,UBIR,UBTN,UCHR,UDEN,UEUT,UFRA,UHAF,UJER,UKEC,ULRD,UMUS,UNAR,UNRS,UNTH,UNUR,UOMI,UPCE,UPRO,USHU,USIK,USKE,USTK,UTRE,VICT,WILL,WORC,ZYMO" --config=bcfishpass --with-mapping-code
