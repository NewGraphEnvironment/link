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
Rscript run_provincial_parity.R "--wsgs=KLUM,KHOR,UDEN,ATNA,BELA,BULK,CHIL,COLR,DEAL,EUCH,FRAN,HARR,INKR,KHTZ,KLAR,KUMR,LFRA,LMUS,LRAN,MBNK,MMUS,MURR,NATR,NIMP,PARS,SALM,SHUL,SQAM,TABR,TESR,TURN,UCHR,UMUS,UPRO,VICT,MESI,BLAR,NEVI" --config=bcfishpass --with-mapping-code
