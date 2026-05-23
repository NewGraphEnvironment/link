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
Rscript run_provincial_parity.R "--wsgs=OWIK,UNAR,SLOC,BABL,BIGC,BULL,CHWK,COMX,DEAR,EUCL,FRCN,HERR,JENR,KINR,KLIN,LARL,LHAF,LNAR,LRDO,MCGR,MORI,NAHR,NAZR,OKAN,PCEA,SALR,SIML,STHM,TAHR,THOM,TUYR,UEUT,UNRS,USHU,WILL,MAHD,TAHS,LKEL" --config=bcfishpass --with-mapping-code
