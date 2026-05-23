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
Rscript run_provincial_parity.R "--wsgs=PINE,FINA,LOMI,BABR,BLUR,CAMB,CLAY,COTR,DRIR,FINL,GLAR,HOLB,JERV,KISK,KOTL,LBIR,LIAR,LNIC,LSAL,MESC,MORK,NAKR,NBNK,OSPK,PORI,SANJ,SKGT,STUL,TASR,TOBA,UARL,UFRA,UNTH,USIK,ZYMO,BARR,TWAC,GUIC" --config=bcfishpass --with-mapping-code
