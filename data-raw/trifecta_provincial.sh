#!/usr/bin/env bash
# Provincial parity orchestrator — dispatch across M4 + M1 + N cyphers.
# Each host runs `run_provincial_parity.R --wsgs=<bucket> --config=<bundle>`
# (resume-safe; skips WSGs whose RDS already exists). After all hosts
# finish, pulls every host's RDS files back to M4, binds them, and writes
# `<TS>_annotated.csv` against `research/bcfp_divergence_taxonomy.yml`.
#
# Bucket allocation: greedy LPT (Longest Processing Time first) computed
# inline at dispatch time when `_per_wsg_times.csv` files exist from any
# prior run. WSGs are sorted by M4-equivalent intrinsic work; each is
# assigned to the host with the lowest projected finish time. Without
# prior timing data, falls back to a deterministic ceil(n/(2+N_CY)) split.
# Per-host `--<host>-bucket=` overrides still take precedence.
#
# Usage:
#   ./trifecta_provincial.sh                          # 3-host default: M4 + M1 + 1 cypher
#   ./trifecta_provincial.sh --with-mapping-code      # per-WSG mapping_code lens
#   ./trifecta_provincial.sh --cy-workspaces=job1,job2,job3   # 5-host: 3 cyphers
#   ./trifecta_provincial.sh --wsgs=ADMS,BULK,DEAD --no-cyphers   # M4+M1, 3 WSGs
#   ./trifecta_provincial.sh --force --no-cyphers     # force re-run, M4+M1 only
#
# CLI flags:
#   --config=<name>           bundle (default: bcfishpass)
#   --schema=<name>           override cfg$pipeline$schema
#   --rds-dir=<name>          override per-bundle RDS dir
#   --wsgs=<csv>              restrict to a subset of the bundle's WSG list
#                             (intersected with bundle presence-filtered set;
#                              unknown WSGs error loud)
#   --no-cyphers              skip cypher hosts entirely; dispatch M4+M1 only
#   --force                   forward --force to the per-host Rscript
#                             (bypasses both PG-state and RDS resume gates)
#   --host-speeds=<csv>       per-host speed factor vs M4 (default: m4=1.0,m1=0.83,cy=1.83).
#                             Higher = slower. Used in LPT bucket projection.
#                             Per-cypher overrides via --host-speeds=...,cy1=1.83,cy2=2.10
#   --m4-bucket=<csv>         override LPT plan for M4
#   --m1-bucket=<csv>         override LPT plan for M1
#   --cy-bucket=<csv>         single-cypher override (only valid with 1 workspace)
#   --cy-workspaces=<csv>     comma-list of cypher tofu workspaces (default: "default")
#   --cyN-bucket=<csv>        per-cypher override (1-indexed, e.g. --cy1-bucket=...)
#   --with-mapping-code       pass through to run_provincial_parity.R
#   --skip-preflight          skip version-match check (debug only)
#
# Estimated wall: ~2 hours single-cypher, ~50-60 min 3-cypher,
# ~30-40 min M4+M1 only (16-WSG default-bundle smoke test).

set -euo pipefail

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
CONFIG="bcfishpass"
SCHEMA=""
RDS_DIR=""
M4_OVERRIDE=""
M1_OVERRIDE=""
CY_OVERRIDE=""
CY_WORKSPACES="default"
HOST_SPEEDS="m4=1.0,m1=0.79,cy=1.23"
# Time-multiplier vs M4 baseline; LARGER = SLOWER = fewer WSGs assigned by LPT.
# (The LPT formula reads `candidate = load + m4_equiv * host_factor` —
#  smaller factor = less per-WSG cost on that host = more WSGs assigned.)
#
# Calibrated 2026-05-13 from per-WSG medians on the bcfishpass-122 dispatch:
#   m4   101s/WSG → 1.00  (Apple M4 Max, 32GB shared_buffers + 14 parallel workers)
#   m1    80s/WSG → 0.79  (Apple M1 MBP, 8GB shared_buffers — fresh#199 over-tuning)
#   cy   124s/WSG → 1.23  (8vCPU/32GB DO droplet, 32GB host preset)
# If you spin c-class or m-class droplets, override via --host-speeds.
declare -A CYN_BUCKETS=()
WITH_MAPPING_CODE=""
SKIP_PREFLIGHT=0
WSGS_FILTER=""
NO_CYPHERS=0
FORCE_FLAG=""

for arg in "$@"; do
  case "$arg" in
    --config=*)         CONFIG="${arg#--config=}" ;;
    --schema=*)         SCHEMA="${arg#--schema=}" ;;
    --rds-dir=*)        RDS_DIR="${arg#--rds-dir=}" ;;
    --wsgs=*)           WSGS_FILTER="${arg#--wsgs=}" ;;
    --no-cyphers)       NO_CYPHERS=1 ;;
    --force)            FORCE_FLAG="--force" ;;
    --host-speeds=*)    HOST_SPEEDS="${arg#--host-speeds=}" ;;
    --m4-bucket=*)      M4_OVERRIDE="${arg#--m4-bucket=}" ;;
    --m1-bucket=*)      M1_OVERRIDE="${arg#--m1-bucket=}" ;;
    --cy-bucket=*)      CY_OVERRIDE="${arg#--cy-bucket=}" ;;
    --cy-workspaces=*)  CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --cy[1-9]-bucket=*)
      N="${arg#--cy}"; N="${N%-bucket=*}"
      CYN_BUCKETS[$N]="${arg#--cy${N}-bucket=}"
      ;;
    --with-mapping-code) WITH_MAPPING_CODE="--with-mapping-code" ;;
    --skip-preflight)    SKIP_PREFLIGHT=1 ;;
  esac
done

# --no-cyphers wipes the cypher workspace list so the rest of the
# script sees a zero-cypher plan. Bash array init from an empty string
# via `read -r -a` produces a single-element array containing "" —
# clear it explicitly to get a true empty list.
if [ "$NO_CYPHERS" -eq 1 ]; then
  CY_WORKSPACES=""
fi

EXTRA_ARGS="--config=$CONFIG"
[ -n "$SCHEMA" ]            && EXTRA_ARGS="$EXTRA_ARGS --schema=$SCHEMA"
[ -n "$RDS_DIR" ]           && EXTRA_ARGS="$EXTRA_ARGS --rds-dir=$RDS_DIR"
[ -n "$WITH_MAPPING_CODE" ] && EXTRA_ARGS="$EXTRA_ARGS $WITH_MAPPING_CODE"
[ -n "$FORCE_FLAG" ]        && EXTRA_ARGS="$EXTRA_ARGS $FORCE_FLAG"

# Parse cypher workspace list into array. Empty CY_WORKSPACES (set by
# --no-cyphers) yields N_CY=0; all `for ((i=0; i<N_CY; i++))` loops
# below become no-ops naturally.
if [ -z "$CY_WORKSPACES" ]; then
  CY_WS_ARR=()
else
  IFS=',' read -r -a CY_WS_ARR <<< "$CY_WORKSPACES"
fi
N_CY=${#CY_WS_ARR[@]}

# --cy-bucket is only valid with exactly 1 cypher workspace.
if [ -n "$CY_OVERRIDE" ] && [ "$N_CY" -ne 1 ]; then
  echo "ERROR: --cy-bucket= only valid with a single cypher workspace." >&2
  echo "  Use --cy1-bucket= ... --cy${N_CY}-bucket= for N cyphers." >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/data-raw/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d%H%M)
ORCH_LOG="$LOG_DIR/${TS}_trifecta_provincial_orchestrator.txt"

# ---------------------------------------------------------------------------
# Bucket allocation. Greedy LPT (Longest Processing Time first):
#   1. Read every host's most-recent `_per_wsg_times.csv` for actual times
#   2. Convert each WSG's recorded time to M4-equivalent intrinsic work
#      (divide by host's observed slowness factor from the run that
#      produced the row)
#   3. Sort WSGs descending by m4_equiv; assign each to the host with the
#      lowest projected finish time (current_load + m4_equiv * host_factor)
#
# Host factors are passed via --host-speeds (defaults: m4=1.0, m1=0.83,
# cy=1.83). Per-cypher overrides via --host-speeds=...,cy1=1.83,cy2=2.10
# applied when the workspace name is `jobN`. Falls back to the generic
# `cy` factor for any cypher workspace.
#
# When no `_per_wsg_times.csv` exists yet, falls back to a deterministic
# ceil(n/H) split (H = 2 + N_CY hosts).
#
# Manual --m4-bucket / --m1-bucket / --cyN-bucket overrides ALWAYS take
# precedence over the computed LPT plan.
# ---------------------------------------------------------------------------
SPLIT_R="$LOG_DIR/${TS}_trifecta_provincial_split.R"
cat > "$SPLIT_R" <<SPLIT_EOF
suppressPackageStartupMessages({})

# Canonical WSG list (bundle species presence-filtered, link#157)
cfg <- link::lnk_config("$CONFIG")
loaded <- link::lnk_load_overrides(cfg)
wsg_pres <- loaded\$wsg_species_presence
spp_cols <- tolower(cfg\$species)
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1,
                 function(r) any(r %in% c("t","TRUE",TRUE)))
all_wsgs <- sort(wsg_pres\$watershed_group_code[has_spp])

# --wsgs subset filter. Intersect with the bundle's presence-filtered
# WSG set; error loud on any unknown WSG so a typo doesn't silently
# drop work.
wsgs_filter_csv <- "$WSGS_FILTER"
if (nzchar(wsgs_filter_csv)) {
  requested <- trimws(strsplit(wsgs_filter_csv, ",", fixed = TRUE)[[1]])
  unknown <- setdiff(requested, all_wsgs)
  if (length(unknown) > 0L) {
    stop("--wsgs contains WSGs not in the bundle presence-filtered set: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  all_wsgs <- sort(intersect(all_wsgs, requested))
  cat("[LPT] --wsgs subset: ", length(all_wsgs), " of ",
      length(requested), " requested kept\n", sep = "")
}

# Parse --host-speeds=m4=1.0,m1=0.83,cy=1.83 into a named numeric vector
parse_speeds <- function(s) {
  pairs <- strsplit(s, ",", fixed = TRUE)[[1]]
  vec <- numeric(0)
  for (p in pairs) {
    kv <- strsplit(p, "=", fixed = TRUE)[[1]]
    if (length(kv) != 2L) stop("bad --host-speeds entry: ", p)
    vec[trimws(kv[1])] <- as.numeric(kv[2])
  }
  vec
}
speeds <- parse_speeds("$HOST_SPEEDS")
if (!all(c("m4","m1","cy") %in% names(speeds))) {
  stop("--host-speeds must include m4, m1, cy (got: ",
       paste(names(speeds), collapse = ","), ")")
}

# Hosts in the plan: m4, m1, cy1..cyN_CY (each cypher workspace is its
# own host). Per-cypher speed: take \`cyN\` from --host-speeds if present,
# else fall back to the generic \`cy\` factor.
#
# Phantom-cy guard for the --no-cyphers / empty workspace list case:
# R's \`paste0("cy", integer(0))\` returns \`"cy"\` (length 1) due to
# constant recycling, which would put a non-existent cypher in
# host_keys. Three-branch the construction to keep n_cy = 0 honest.
cy_ws_csv <- "$CY_WORKSPACES"
cy_ws <- if (nzchar(cy_ws_csv)) {
  strsplit(cy_ws_csv, ",", fixed = TRUE)[[1]]
} else {
  character(0)
}
n_cy <- length(cy_ws)
cy_host_keys <- if (n_cy == 0L) {
  character(0)
} else if (n_cy == 1L) {
  "cy"
} else {
  paste0("cy", seq_len(n_cy))
}
host_keys <- c("m4", "m1", cy_host_keys)
host_factor <- numeric(length(host_keys))
names(host_factor) <- host_keys
host_factor["m4"] <- speeds["m4"]
host_factor["m1"] <- speeds["m1"]
for (i in seq_along(cy_host_keys)) {
  k <- cy_host_keys[i]
  host_factor[k] <- if (!is.na(speeds[k])) speeds[k] else speeds["cy"]
}

# Per-WSG timing CSVs from prior runs (any host, any run). Drop rows with
# status != "ok" so error-stub rows don't pollute the time estimates.
logs_root <- "$LOG_DIR"
csv_dirs <- file.path(logs_root,
                      c("provincial_parity",
                        paste0("provincial_", "$CONFIG")))
csv_dirs <- unique(csv_dirs[dir.exists(csv_dirs)])
csvs <- unlist(lapply(csv_dirs, function(d)
  list.files(d, pattern = "_per_wsg_times\\\\.csv\$", full.names = TRUE)))

times <- if (length(csvs) > 0L) {
  rows <- do.call(rbind, lapply(csvs, function(p) {
    df <- tryCatch(read.csv(p, stringsAsFactors = FALSE),
                   error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    # Map nodename -> short code. Fallback: drop unknown hosts.
    df\$host_short <- ifelse(grepl("MacBook-Pro-2", df\$host),       "m4",
                      ifelse(grepl("Allans|MacBook-Pro\$", df\$host), "m1",
                      ifelse(grepl("cypher", df\$host),               "cy",
                             NA_character_)))
    ok <- df[df\$status == "ok" & !is.na(df\$host_short), ]
    ok[, c("wsg", "elapsed_s", "host_short")]
  }))
  rows
} else {
  NULL
}

# Compute per-WSG M4-equivalent intrinsic work. Back-normalize each
# sample's elapsed by the CLI host_factor (the same factor the LPT
# projection uses). This is consistent and avoids a feedback loop:
# using OBSERVED per-host mean as the divisor inflates the factor when
# prior buckets were imbalanced (large WSGs on cy + small on m4 →
# observed mean ratio reflects bucket bias × true slowness, not
# slowness alone), and subsequent runs amplify the imbalance.
#
# Note: this trusts --host-speeds as ground truth. Update the defaults
# (or the CLI value) when host speeds drift — re-measure with an ADMS
# smoke on each host.
buckets <- vector("list", length(host_keys))
names(buckets) <- host_keys
load <- numeric(length(host_keys))
names(load) <- host_keys

if (!is.null(times) && nrow(times) > 0L) {
  # Tag any rows whose host_short isn't a recognized key with NA and
  # warn — silent drops let new/renamed hosts vanish from the LPT input.
  unknown_hosts <- setdiff(unique(times\$host_short), c("m4", "m1", "cy"))
  if (length(unknown_hosts) > 0L) {
    cat("[LPT] WARN: dropped ", sum(times\$host_short %in% unknown_hosts),
        " timing rows with unrecognized host_short: ",
        paste(unknown_hosts, collapse = ", "), "\n", sep = "")
    times <- times[!(times\$host_short %in% unknown_hosts), ]
  }
  # Back-normalize: elapsed / host_factor[host_short]. Cypher rows use
  # the generic "cy" factor (per-cypher overrides like cy1/cy2 apply
  # only to the LPT projection step, not to back-normalization — the
  # CSV's host_short is always "cy", never "cy1").
  norm_factor <- speeds[c("m4", "m1", "cy")]
  times\$m4_equiv <- times\$elapsed_s / norm_factor[times\$host_short]
  per_wsg <- aggregate(m4_equiv ~ wsg, data = times, FUN = median)
  cat("[LPT] timing CSVs found: ", length(csvs),
      "  WSGs with samples: ", nrow(per_wsg), "\n", sep = "")
  cat("[LPT] back-normalize host_factor (--host-speeds): ",
      paste0(names(norm_factor), "=", round(norm_factor, 2),
             collapse = ", "), "\n", sep = "")

  # Reconcile against canonical: missing WSGs get the median m4_equiv.
  missing_wsgs <- setdiff(all_wsgs, per_wsg\$wsg)
  if (length(missing_wsgs) > 0L) {
    med <- median(per_wsg\$m4_equiv, na.rm = TRUE)
    per_wsg <- rbind(per_wsg,
      data.frame(wsg = missing_wsgs, m4_equiv = med))
    cat("[LPT] WSGs missing from timing CSVs (assigned median ",
        round(med, 1), "s): ", length(missing_wsgs), "\n", sep = "")
  }
  per_wsg <- per_wsg[per_wsg\$wsg %in% all_wsgs, , drop = FALSE]
  per_wsg <- per_wsg[order(-per_wsg\$m4_equiv), ]

  # Greedy LPT assignment
  for (i in seq_len(nrow(per_wsg))) {
    candidate <- load + per_wsg\$m4_equiv[i] * host_factor
    pick <- names(which.min(candidate))
    buckets[[pick]] <- c(buckets[[pick]], per_wsg\$wsg[i])
    load[pick] <- candidate[pick]
  }
  cat("[LPT] projected finish (min): ",
      paste0(names(load), "=", round(load/60, 1),
             collapse = ", "), "\n", sep = "")
} else {
  # Fallback: host_speeds-weighted alphabetical split. Each host gets
  # floor((n * speed_factor) / sum(speed_factors)) WSGs; remainder
  # distributed to highest-factor hosts first. Without this weighting,
  # equal-split sends 217/5 = 44 WSGs to every host — cyphers finish in
  # 60% of M4's wall and M4 in 83% of M1's wall, wasting cypher capacity
  # AND making M1 the long pole. (Bug discovered 2026-05-13 mid-dispatch;
  # host_factor from --host-speeds is required for fair fallback.)
  cat("[LPT] no timing CSVs found; using host_speeds-weighted split\n")
  n <- length(all_wsgs)
  weights <- host_factor[host_keys]
  share <- weights / sum(weights)
  sizes <- floor(n * share)
  remainder <- n - sum(sizes)
  if (remainder > 0) {
    ord <- order(-weights)
    for (i in seq_len(remainder)) sizes[ord[i]] <- sizes[ord[i]] + 1
  }
  cat("[LPT] weighted sizes: ",
      paste0(names(sizes), "=", sizes, collapse = ", "), "\n", sep = "")
  lo <- 1L
  for (i in seq_along(host_keys)) {
    if (sizes[i] == 0) {
      buckets[[host_keys[i]]] <- character(0)
      next
    }
    hi <- lo + sizes[i] - 1L
    buckets[[host_keys[i]]] <- all_wsgs[lo:hi]
    lo <- hi + 1L
  }
}

# Emit shell-parseable assignments
for (h in host_keys) {
  cat(toupper(h), "=", paste(buckets[[h]], collapse = ","), "\n", sep = "")
}
SPLIT_EOF

SPLIT_OUT=$(Rscript "$SPLIT_R" 2>&1) || {
  rc=$?
  echo "ERROR: split/LPT R script failed (rc=$rc):" >&2
  echo "$SPLIT_OUT" >&2
  exit "$rc"
}
echo "$SPLIT_OUT" | grep -E "^\[LPT\]" || true

M4_WSGS=$(echo "$SPLIT_OUT" | awk -F'=' '$1=="M4" {print $2}')
M1_WSGS=$(echo "$SPLIT_OUT" | awk -F'=' '$1=="M1" {print $2}')

# Apply M4 + M1 manual overrides
[ -n "$M4_OVERRIDE" ] && M4_WSGS="$M4_OVERRIDE"
[ -n "$M1_OVERRIDE" ] && M1_WSGS="$M1_OVERRIDE"

# Resolve per-cypher buckets: LPT plan -> per-cypher override.
CY_BUCKETS=()
for ((i=0; i<N_CY; i++)); do
  KEY=""
  if [ "$N_CY" -eq 1 ]; then
    KEY="CY"
  else
    KEY="CY$((i+1))"
  fi
  BUCKET=$(echo "$SPLIT_OUT" | awk -F'=' -v k="$KEY" '$1==k {print $2}')
  # Per-cypher manual overrides
  if [ "$N_CY" -eq 1 ] && [ -n "$CY_OVERRIDE" ]; then
    BUCKET="$CY_OVERRIDE"
  fi
  N_INDEX=$((i+1))
  if [ -n "${CYN_BUCKETS[$N_INDEX]:-}" ]; then
    BUCKET="${CYN_BUCKETS[$N_INDEX]}"
  fi
  CY_BUCKETS+=("$BUCKET")
done

# Guard against silent empty dispatch. An empty bucket would dispatch
# `Rscript run_provincial_parity.R --wsgs=` (empty string), which the
# R script accepts without error and processes 0 WSGs. Every host
# "succeeds" with no work done — the orchestrator reports exit=0 and
# 0 RDS files, masking the upstream split failure.
if [ -z "$M4_WSGS" ] || [ -z "$M1_WSGS" ]; then
  echo "ERROR: LPT/split produced an empty bucket for M4 or M1." >&2
  echo "  M4='$M4_WSGS'  M1='$M1_WSGS'" >&2
  echo "  Inspect: $SPLIT_R" >&2
  echo "$SPLIT_OUT" | head -30 >&2
  exit 4
fi
for ((i=0; i<N_CY; i++)); do
  if [ -z "${CY_BUCKETS[$i]}" ]; then
    echo "ERROR: LPT/split produced an empty bucket for cypher[${CY_WS_ARR[$i]}]." >&2
    echo "  Use --cy$((i+1))-bucket=<csv> to provide manually, or fix the LPT input." >&2
    echo "$SPLIT_OUT" | head -30 >&2
    exit 4
  fi
done

# ---------------------------------------------------------------------------
# Per-bundle RDS dir name (used for SCP pull-back later).
# ---------------------------------------------------------------------------
RDS_DIR_NAME="provincial_${CONFIG}"
[ "$CONFIG" = "bcfishpass" ] && RDS_DIR_NAME="provincial_parity"
mkdir -p "$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME"

# ---------------------------------------------------------------------------
# Pre-flight: link + fresh package versions must agree across all hosts.
# Without this, a stale install on one cypher silently produces different
# rollup numbers; the provincial run looks fine but bcfp parity diffs
# include version drift, not just methodology drift.
# ---------------------------------------------------------------------------
preflight() {
  local hosts=("$@")
  local m4_link m4_fresh
  m4_link=$(Rscript -e 'cat(as.character(packageVersion("link")))')
  m4_fresh=$(Rscript -e 'cat(as.character(packageVersion("fresh")))')
  echo "[preflight] m4 link=$m4_link fresh=$m4_fresh"
  local fail=0
  for spec in "${hosts[@]}"; do
    local host_type="${spec%%:*}"  # 'ssh' or 'cypher'
    local host_id="${spec#*:}"
    local link_v fresh_v
    if [ "$host_type" = "ssh" ]; then
      # Single ssh round-trip; captures both into a 'link\nfresh\n' result.
      local out
      out=$(ssh "$host_id" 'Rscript -e "cat(as.character(packageVersion(\"link\")), as.character(packageVersion(\"fresh\")), sep=\"\n\")"' 2>/dev/null || echo "ERROR")
      link_v=$(echo "$out" | sed -n '1p')
      fresh_v=$(echo "$out" | sed -n '2p')
    else
      # cypher: TF_WORKSPACE=<name>, derive droplet IP, ssh to cypher@<ip>
      local ws="$host_id"
      local cy_ip
      cy_ip=$(cd "$REPO_ROOT/../rtj/env/do/dev/cypher" && TF_WORKSPACE="$ws" tofu output -raw droplet_ip 2>/dev/null || echo "")
      if [ -z "$cy_ip" ]; then
        echo "  [preflight] cypher workspace '$ws': no droplet_ip (is cypher up?)" >&2
        fail=1
        continue
      fi
      local out
      out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "cypher@$cy_ip" 'Rscript -e "cat(as.character(packageVersion(\"link\")), as.character(packageVersion(\"fresh\")), sep=\"\n\")"' 2>/dev/null || echo "ERROR")
      link_v=$(echo "$out" | sed -n '1p')
      fresh_v=$(echo "$out" | sed -n '2p')
      host_id="cypher-${ws}@${cy_ip}"
    fi
    echo "[preflight] $host_id link=$link_v fresh=$fresh_v"
    if [ "$link_v" != "$m4_link" ] || [ "$fresh_v" != "$m4_fresh" ]; then
      echo "  ERROR: version mismatch vs m4 (link=$m4_link fresh=$m4_fresh)" >&2
      fail=1
    fi
  done
  return $fail
}

if [ "$SKIP_PREFLIGHT" -eq 0 ]; then
  HOSTS=("ssh:m1")
  for ws in "${CY_WS_ARR[@]}"; do
    HOSTS+=("cypher:${ws}")
  done
  if ! preflight "${HOSTS[@]}"; then
    echo "ERROR: pre-flight version check failed — aborting dispatch." >&2
    echo "  Fix mismatches or re-run with --skip-preflight." >&2
    exit 3
  fi
fi

# Tee from here on
exec > >(tee -a "$ORCH_LOG") 2>&1

# count_csv: portable count of comma-separated entries (0 for empty string)
count_csv() {
  if [ -z "$1" ]; then echo 0; else echo "$1" | tr ',' '\n' | wc -l; fi
}
M4_COUNT=$(count_csv "$M4_WSGS")
M1_COUNT=$(count_csv "$M1_WSGS")
CY_TOTAL=0
for bucket in "${CY_BUCKETS[@]}"; do
  CY_TOTAL=$((CY_TOTAL + $(count_csv "$bucket")))
done
TOTAL=$((M4_COUNT + M1_COUNT + CY_TOTAL))

echo "============================================"
echo "[trifecta-provincial] dispatch start: $(date '+%H:%M:%S')"
echo "  total WSGs: $TOTAL  (m4=$M4_COUNT  m1=$M1_COUNT  cypher_total=$CY_TOTAL)"
echo "  config: $CONFIG  with_mapping_code: ${WITH_MAPPING_CODE:-no}"
echo "  m4     bucket: $M4_WSGS"
echo "  m1     bucket: $M1_WSGS"
for ((i=0; i<N_CY; i++)); do
  echo "  cypher[${CY_WS_ARR[$i]}] bucket: ${CY_BUCKETS[$i]}"
done
echo "============================================"

# ---------------------------------------------------------------------------
# Build per-cypher wrap scripts. Each cypher needs its own SSH tunnel to
# db_newgraph (the tunnel is per-cypher, not per-orchestrator — each cypher
# opens its own connection to localhost:63333 -> db_newgraph:5432 from
# inside its own droplet).
# ---------------------------------------------------------------------------
declare -a CY_SHELL_PATHS=()
for ((i=0; i<N_CY; i++)); do
  WS="${CY_WS_ARR[$i]}"
  BUCKET="${CY_BUCKETS[$i]}"
  CY_SHELL="$LOG_DIR/${TS}_trifecta_provincial_cypher_${WS}.sh"
  cat > "$CY_SHELL" <<CYPHER_EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \\
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \\
    -L 63333:127.0.0.1:5432 db_newgraph -N &
TUNNEL_PID=\$!
trap 'kill \$TUNNEL_PID 2>/dev/null || true' EXIT
for _ in \$(seq 1 10); do
  nc -z localhost 63333 2>/dev/null && break
  sleep 0.5
done
cd ~/Projects/repo/link/data-raw
Rscript run_provincial_parity.R "--wsgs=$BUCKET" $EXTRA_ARGS
CYPHER_EOF
  chmod +x "$CY_SHELL"
  CY_SHELL_PATHS+=("$CY_SHELL")
done

# ---------------------------------------------------------------------------
# Dispatch all hosts in parallel.
# ---------------------------------------------------------------------------
START=$(date +%s)

# m4 (local) — uses same inline-tunnel pattern as cyphers so the run
# is idempotent on tunnel state. If an existing persistent tunnel on
# 63333 is up, `ssh -L 63333` warns "Address already in use" and the
# existing tunnel is reused; the trap-kill at exit kills only the new
# (bind-failed) ssh PID, preserving the operator's persistent tunnel.
M4_LOG="$LOG_DIR/${TS}_trifecta_provincial_m4.txt"
M4_SHELL="$LOG_DIR/${TS}_trifecta_provincial_m4.sh"
cat > "$M4_SHELL" <<M4_EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \\
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \\
    -L 63333:127.0.0.1:5432 db_newgraph -N &
TUNNEL_PID=\$!
trap 'kill \$TUNNEL_PID 2>/dev/null || true' EXIT
for _ in \$(seq 1 10); do
  nc -z localhost 63333 2>/dev/null && break
  sleep 0.5
done
cd $REPO_ROOT/data-raw
Rscript run_provincial_parity.R "--wsgs=$M4_WSGS" $EXTRA_ARGS
M4_EOF
chmod +x "$M4_SHELL"
( bash "$M4_SHELL" > "$M4_LOG" 2>&1 ) &
M4_PID=$!

# m1 (ssh) — reverse-forwards M4's bcfp tunnel into M1's localhost:63333
# via `ssh -R`. M1 does NOT need its own db_newgraph identity authorized
# (it doesn't; the pre-2026-05-13 runs worked only because the operator
# had manually opened a persistent tunnel on M1 using their interactive
# key, and prior runs happened to land while that tunnel was still up).
#
# Requirements:
#   - M4 must have the bcfp tunnel up on localhost:63333. The m4 block
#     above ensures this (idempotent inline tunnel).
#   - M1 must allow reverse port-forwards (OpenSSH default = yes).
#   - Nothing else listening on M1's port 63333 (M1 has no persistent
#     tunnel; this is free in practice).
M1_LOG="$LOG_DIR/${TS}_trifecta_provincial_m1.txt"
( ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -R 63333:127.0.0.1:63333 m1 \
    "cd ~/Projects/repo/link/data-raw && Rscript run_provincial_parity.R '--wsgs=$M1_WSGS' $EXTRA_ARGS" \
    > "$M1_LOG" 2>&1 ) &
M1_PID=$!

# N cyphers (parallel)
declare -a CY_PIDS=()
declare -a CY_LOGS=()
for ((i=0; i<N_CY; i++)); do
  WS="${CY_WS_ARR[$i]}"
  CY_LOG="$LOG_DIR/${TS}_trifecta_provincial_cypher_${WS}.txt"
  CY_LOGS+=("$CY_LOG")
  if [ "$WS" = "default" ]; then
    ( bash "$REPO_ROOT/../rtj/scripts/cypher/cypher_run.sh" "${CY_SHELL_PATHS[$i]}" > "$CY_LOG" 2>&1 ) &
  else
    ( bash "$REPO_ROOT/../rtj/scripts/cypher/cypher_run.sh" --workspace "$WS" "${CY_SHELL_PATHS[$i]}" > "$CY_LOG" 2>&1 ) &
  fi
  CY_PIDS+=($!)
done

echo "[dispatch] m4 PID=$M4_PID  m1 PID=$M1_PID  cyphers PIDs=${CY_PIDS[*]}"
echo "[dispatch] tail logs:"
echo "  $M4_LOG"
echo "  $M1_LOG"
for log in "${CY_LOGS[@]}"; do echo "  $log"; done

M4_EXIT=0; M1_EXIT=0
declare -a CY_EXITS=()
wait $M4_PID || M4_EXIT=$?
wait $M1_PID || M1_EXIT=$?
for pid in "${CY_PIDS[@]}"; do
  E=0
  wait "$pid" || E=$?
  CY_EXITS+=("$E")
done

END=$(date +%s)
ELAPSED=$((END - START))

echo "============================================"
printf '[trifecta-provincial] elapsed: %dh%02dm%02ds\n' \
       $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))
printf '  m4     exit=%d  log=%s\n' "$M4_EXIT" "$M4_LOG"
printf '  m1     exit=%d  log=%s\n' "$M1_EXIT" "$M1_LOG"
for ((i=0; i<N_CY; i++)); do
  printf '  cypher[%s] exit=%d  log=%s\n' "${CY_WS_ARR[$i]}" "${CY_EXITS[$i]}" "${CY_LOGS[$i]}"
done
echo "============================================"

# ---------------------------------------------------------------------------
# Pull cypher-side R logs back. cypher_run.sh writes the actual Rscript
# stdout/stderr to `rtj/scripts/cypher/logs/<TS>_cypher-run_*.txt`.
# Without this step, the orchestrator's per-host log only captures the
# wrapper init (tunnel setup) — cypher-side R errors (e.g. INSERT
# failures from DDL drift) are invisible until someone goes hunting
# in rtj's logs dir. Land them alongside m4/m1 logs so the headline
# below can reflect what actually happened.
# ---------------------------------------------------------------------------
RTJ_CY_LOGDIR="$REPO_ROOT/../rtj/scripts/cypher/logs"
for ((i=0; i<N_CY; i++)); do
  WS="${CY_WS_ARR[$i]}"
  # cypher_run.sh names: <RUN_TS>_cypher-run_<workload-name>_<ws>.txt
  # The wrap script (CY_SHELL_PATHS[i]) is named with TS — derive its basename
  CY_WRAP_BASE=$(basename "${CY_SHELL_PATHS[$i]}" .sh)
  # Find the most-recent cypher-run log for this workload + workspace.
  # `|| true` guards the pipefail trap: ls exits non-zero on no-match,
  # which would otherwise abort the script via $(... | ...) command-sub.
  CY_R_LOG=$(ls -1t "$RTJ_CY_LOGDIR"/*_cypher-run_"${CY_WRAP_BASE}"_"${WS}".txt 2>/dev/null | head -1 || true)
  if [ -n "$CY_R_LOG" ] && [ -f "$CY_R_LOG" ]; then
    cp "$CY_R_LOG" "$LOG_DIR/${TS}_trifecta_provincial_cypher_${WS}_R.txt"
  fi
done

# ---------------------------------------------------------------------------
# Pull RDS files back to M4.
#   M1: via ~/.ssh/config alias
#   Each cypher: via TF_WORKSPACE-resolved droplet IP
# ---------------------------------------------------------------------------
echo
echo "[trifecta-provincial] pulling m1 RDS files"
scp -q "m1:~/Projects/repo/link/data-raw/logs/$RDS_DIR_NAME/*.rds" \
    "$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME/" 2>&1 | tail -3 || true

for ((i=0; i<N_CY; i++)); do
  WS="${CY_WS_ARR[$i]}"
  CY_IP=$(cd "$REPO_ROOT/../rtj/env/do/dev/cypher" && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null || echo "")
  if [ -z "$CY_IP" ]; then
    echo "[trifecta-provincial] WARN: workspace '$WS' has no droplet_ip — skipping pull"
    continue
  fi
  echo "[trifecta-provincial] pulling cypher[$WS] RDS files (cypher@$CY_IP)"
  scp -q "cypher@$CY_IP:/home/cypher/Projects/repo/link/data-raw/logs/$RDS_DIR_NAME/*.rds" \
      "$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME/" 2>&1 | tail -3 || true
done

# Final inventory + truth-in-headline error-stub vs OK count. Without
# this, `217 / 217` could be 217 error stubs (e.g. cypher DDL drift
# silently produced 93 stubs on 2026-05-12). Inspect each RDS and
# count.
echo
TOTAL_RDS=$(find "$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME" -maxdepth 1 \
              -name '*.rds' 2>/dev/null | wc -l | tr -d ' ')
if [ "$TOTAL_RDS" -gt 0 ]; then
  # `[.]rds$` is character-class form — equivalent to `\\.rds$` but
  # avoids backslash-eat surprises through shell quoting layers.
  RDS_COUNTS=$(Rscript -e '
files <- list.files(commandArgs(trailingOnly = TRUE)[1],
                    pattern = "[.]rds$", full.names = TRUE)
n_ok <- 0; n_err <- 0
for (f in files) {
  x <- tryCatch(readRDS(f), error = function(e) NULL); if (is.null(x)) next
  if (is.list(x) && !is.data.frame(x) && "error" %in% names(x)) n_err <- n_err + 1
  else n_ok <- n_ok + 1
}
cat(n_ok, n_err)
' "$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME" 2>/dev/null || echo "0 0")
  # Default-coerce in case Rscript hiccuped: empty string in arithmetic
  # comparison aborts under `set -e`.
  N_OK=$(echo "$RDS_COUNTS" | awk '{print $1+0}')
  N_ERR=$(echo "$RDS_COUNTS" | awk '{print $2+0}')
  N_OK=${N_OK:-0}; N_ERR=${N_ERR:-0}
  echo "[trifecta-provincial] local RDS: $TOTAL_RDS / $TOTAL pulled — $N_OK OK, $N_ERR errors"
  if [ "$N_ERR" -gt 0 ]; then
    echo "[trifecta-provincial] WARN: $N_ERR error-stub RDS found. Inspect cypher-side R logs:"
    ls "$LOG_DIR/${TS}_trifecta_provincial_cypher_"*_R.txt 2>/dev/null | sed 's/^/  /' || true
  fi
else
  echo "[trifecta-provincial] local RDS file count: 0 / $TOTAL (no files pulled — all hosts failed?)"
fi

# ---------------------------------------------------------------------------
# Aggregate annotation: bind all RDS, lnk_parity_annotate against the
# taxonomy YAML, write <TS>_annotated.csv. Acceptance check (Phase 7):
# zero rows with class==UNEXPLAINED AND |diff_pct|>=2.
# ---------------------------------------------------------------------------
ANNOTATED_CSV="$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME/${TS}_annotated.csv"
TAXONOMY="$REPO_ROOT/research/bcfp_divergence_taxonomy.yml"

if [ -f "$TAXONOMY" ]; then
  echo
  echo "[trifecta-provincial] aggregating + annotating $TOTAL_RDS RDS files"
  Rscript - <<RSCRIPT_EOF
suppressPackageStartupMessages({library(link)})
rds_files <- list.files("$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME",
                        pattern = "\\\\.rds\$", full.names = TRUE)
rollup_list <- lapply(rds_files, function(f) {
  x <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  if (is.list(x) && !is.data.frame(x) && "error" %in% names(x)) return(NULL)
  if (is.list(x) && !is.data.frame(x) && "rollup" %in% names(x)) return(x\$rollup)
  if (is.data.frame(x)) return(x)
  NULL
})
rollup_all <- do.call(rbind, Filter(Negate(is.null), rollup_list))
if (is.null(rollup_all) || nrow(rollup_all) == 0L) {
  cat("[annotate] no rollup rows to annotate\n")
  quit(status = 1)
}
annotated <- lnk_parity_annotate(rollup_all, taxonomy = "$TAXONOMY",
                                 to = "$ANNOTATED_CSV")
cat("[annotate] rows:", nrow(annotated), "\n")
cat("[annotate] class breakdown:\n")
print(table(annotated\$class, useNA = "ifany"))
unexp <- annotated[annotated\$class == "UNEXPLAINED" &
                   abs(annotated\$diff_pct) >= 2, ]
cat("[annotate] UNEXPLAINED with |diff_pct| >= 2: ", nrow(unexp), "\n", sep="")
if (nrow(unexp) > 0) {
  cat("  acceptance bar (zero UNEXPLAINED >=2%) NOT met — investigate.\n")
} else {
  cat("  acceptance bar met.\n")
}
RSCRIPT_EOF
  echo "[trifecta-provincial] annotated CSV: $ANNOTATED_CSV"
else
  echo "[trifecta-provincial] WARN: taxonomy YAML not at $TAXONOMY — skipping annotation"
fi

# ---------------------------------------------------------------------------
# Exit non-zero if any host failed
# ---------------------------------------------------------------------------
if [ $M4_EXIT -ne 0 ] || [ $M1_EXIT -ne 0 ]; then exit 1; fi
for e in "${CY_EXITS[@]}"; do [ "$e" -ne 0 ] && exit 1; done
exit 0
