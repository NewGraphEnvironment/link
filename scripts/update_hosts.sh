#!/usr/bin/env bash
# scripts/update_hosts.sh
#
# Update link + fresh on M4 (local) + M1 + cypher to the latest main.
# Bypasses pak (which has the libpath bug r-lib/pak#658 on cypher) by
# using R CMD INSTALL on a downloaded source tarball — slower per host
# than a binary install but reliable everywhere.
#
# Usage:
#   scripts/update_hosts.sh              # update both packages on all 3 hosts
#   scripts/update_hosts.sh fresh        # update fresh only
#   scripts/update_hosts.sh link cypher  # update link on cypher only
#
# Total wall: ~3-5 min for both packages across all 3 hosts.
#
# Tracks: r-lib/pak#658 workaround. Once cypher snapshot is fixed (rtj
# issue TBD), this script can drop the cypher-sudo branch and just use
# pak::pkg_install everywhere.

set -euo pipefail

PKGS=()
HOSTS=()
for arg in "$@"; do
  case "$arg" in
    link|fresh) PKGS+=("$arg") ;;
    m4|m1|cypher) HOSTS+=("$arg") ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done
[ ${#PKGS[@]} -eq 0 ] && PKGS=(fresh link)
[ ${#HOSTS[@]} -eq 0 ] && HOSTS=(m4 m1 cypher)

# Install via R CMD INSTALL of a fresh GitHub source tarball.
# Source > binary because:
#   1. r-universe binaries are R-version-specific; cypher's R 4.6 vs M4/M1's
#      R 4.5 mismatch surfaces as the pak#658 bug
#   2. link + fresh are pure-R packages — source install is fast (~10s each)
#   3. One canonical recipe across all hosts
install_remote() {
  local host="$1" pkg="$2"
  local need_sudo=""
  [ "$host" = "cypher" ] && need_sudo="sudo "
  local cmd
  cmd="set -e
    cd /tmp
    rm -rf '${pkg}-main' '${pkg}-main.tar.gz'
    curl -sSL -o '${pkg}-main.tar.gz' 'https://github.com/NewGraphEnvironment/${pkg}/archive/refs/heads/main.tar.gz'
    tar xzf '${pkg}-main.tar.gz'
    ${need_sudo}R CMD INSTALL '${pkg}-main' 2>&1 | tail -3
    rm -rf '${pkg}-main' '${pkg}-main.tar.gz'
    Rscript -e 'cat(\"${pkg}=\", as.character(packageVersion(\"${pkg}\")), \"\\n\", sep=\"\")'
  "
  if [ "$host" = "m4" ]; then
    bash -c "$cmd"
  else
    ssh -o ConnectTimeout=10 "$host" "$cmd"
  fi
}

for h in "${HOSTS[@]}"; do
  echo "=== $h ==="
  for pkg in "${PKGS[@]}"; do
    install_remote "$h" "$pkg"
  done
done
