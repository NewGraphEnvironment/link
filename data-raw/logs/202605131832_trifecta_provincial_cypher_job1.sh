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
Rscript run_provincial_parity.R "--wsgs=GLAR,GOLD,GRAI,GUIC,HARR,HERR,HOLB,HOMA,HORS,INGR,INKR,ISKR,JENR,JERV,KEEC,KETL,KHOR,KHTZ,KINR,KISK,KISP,KITL,KITR,KLAR,KLIN,KLUM,KNIG,KOTL,KOTR,KSHR,KTSU,KUMR,LARL,LBIR,LBTN,LCHL,LCHR,LDEN,LFRA,LHAF,LIAR,LILL,LISR,LKEL,LMUS,LNAR,LNIC,LNTH,LOMI,LPCE,LPRO,LRAN,LRDO,LSAL,LSKE" --config=bcfishpass --with-mapping-code
