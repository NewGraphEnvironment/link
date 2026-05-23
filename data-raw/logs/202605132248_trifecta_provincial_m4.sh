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
cd /Users/airvine/Projects/repo/link/data-raw
Rscript run_provincial_parity.R "--wsgs=TOAD,FROG,WORC,ISKR,BBAR,BOWR,CARP,CHES,CLWR,DEAD,DUNE,FIRE,FOXR,GRAI,HORS,KEEC,KISP,KNIG,KSHR,LCHL,LISR,LPCE,LSKE,LTRE,MIDR,MPRO,NASC,NECL,NIEL,PARK,REVL,SEYM,SMOK,STIR,SWIR,TAYR,TSAY,UBIR,UHAF,ULRD,UOMI,USTK,UPCE,DOGC,CANO,STUR" --config=bcfishpass --with-mapping-code
