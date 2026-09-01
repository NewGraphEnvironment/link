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
# `R CMD INSTALL` of a source tarball writes NO Remote* fields, so a package
# installed this way has no recoverable commit identity: link's
# .lnk_pkg_git_state() finds no RemoteSha and no .git, and the run logs a NULL
# fresh_sha. That was tolerated until link#264 made the column load-bearing —
# it is now a pre-flight failure and a study_area_verify.sql RAISE.
#
# So this script records what it installed. Two details, both load-bearing:
#
#   * The SHA is resolved from the GitHub API FIRST and the tarball is then
#     fetched BY THAT SHA, not by `refs/heads/main`. Fetching main and
#     recording a separately-resolved sha races: a push between the two calls
#     makes the recorded sha describe code this host never installed, which is
#     precisely the lie the field exists to prevent.
#   * `_GIT_DIRTY=false` is a fact, not an optimism: a published commit's
#     tarball is not a working tree and has no uncommitted state.
#
# These are the same ~/.Renviron keys `data-raw/cypher_prep.sh` owns. Both
# write the truth about whatever they just installed, so whichever ran last is
# correct — but do not add a third writer without re-reading both.
resolve_sha() {   # $1 = pkg. Prints the sha, or exits non-zero.
  local sha
  sha=$(curl -sSL -H 'Accept: application/vnd.github.sha' \
        "https://api.github.com/repos/NewGraphEnvironment/$1/commits/main") || return 1
  # Anchored, because an API error body is a 200-with-JSON and would otherwise
  # be written into the env var as if it were a commit.
  printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$' || return 1
  printf '%s' "$sha"
}

install_remote() {
  local host="$1" pkg="$2" sha="$3"
  local need_sudo="" upkg pin=""
  [ "$host" = "cypher" ] && need_sudo="sudo "
  upkg=$(printf '%s' "$pkg" | tr '[:lower:]' '[:upper:]')

  # ONLY fresh gets an env pin, and link deliberately does not.
  #
  # link's identity on every host is the CHECKOUT: the dispatcher runs it via
  # `LNK_LOAD=loadall` from ~/Projects/repo/link, and .lnk_pkg_git_state()
  # takes the env var ahead of the .git walk. Writing LINK_GIT_SHA here would
  # therefore pin log.link_sha to main's tarball commit rather than the branch
  # that actually ran, and — worse — LINK_GIT_DIRTY=false would make
  # log.link_dirty FALSE on every dispatcher row forever. That is link#257
  # reintroduced pointing the dangerous way: the field exists to say "this SHA
  # cannot be trusted", and a permanent false is the one value that cannot.
  #
  # fresh has no checkout on these hosts and no Remote* fields after a tarball
  # install, so an env pin is the only identity available to it.
  if [ "$pkg" = "fresh" ]; then
    pin="
    RENV=\"\$HOME/.Renviron\"
    touch \"\$RENV\"
    RENV_UMASK=\$(umask); umask 077
    RC=0
    grep -vE '^(${upkg}_GIT_SHA|${upkg}_GIT_DIRTY)=' \"\$RENV\" > \"\$RENV.tmp\" || RC=\$?
    if [ \"\$RC\" -gt 1 ]; then
      echo 'FATAL: could not read ~/.Renviron; refusing to overwrite it' >&2
      rm -f \"\$RENV.tmp\"; exit 1
    fi
    mv \"\$RENV.tmp\" \"\$RENV\"
    printf '${upkg}_GIT_SHA=%s\\n'   '${sha}' >> \"\$RENV\"
    printf '${upkg}_GIT_DIRTY=%s\\n' 'false'  >> \"\$RENV\"
    chmod 600 \"\$RENV\"; umask \"\$RENV_UMASK\"
    echo '${pkg}_sha=${sha}'"
  fi

  local cmd
  # `R CMD INSTALL ... | tail -3` reports TAIL's exit status, which is 0 for a
  # healthy tail whatever the install did — and `set -e` does not propagate
  # through a pipeline. A failed install would then reach the pin block and
  # stamp FRESH_GIT_SHA for a build that never happened, satisfying the
  # pre-flight gate, the parity check and every verify assertion with exactly
  # the lie they exist to catch. Quieter still when the old version is present:
  # packageVersion() succeeds and nothing looks wrong at all.
  #
  # Tempfile + explicit status check, the same idiom cypher_prep.sh uses for
  # its pak and snapshot blocks, so the pin is unreachable unless the install
  # returned 0.
  cmd="set -e
    cd /tmp
    rm -rf '${pkg}-${sha}' '${pkg}-${sha}.tar.gz'
    curl -sSL -o '${pkg}-${sha}.tar.gz' 'https://github.com/NewGraphEnvironment/${pkg}/archive/${sha}.tar.gz'
    tar xzf '${pkg}-${sha}.tar.gz'
    TMP_INSTALL=\$(mktemp)
    if ! ${need_sudo}R CMD INSTALL '${pkg}-${sha}' > \"\$TMP_INSTALL\" 2>&1; then
      echo 'FATAL: R CMD INSTALL of ${pkg} failed; nothing pinned. Log:' >&2
      tail -20 \"\$TMP_INSTALL\" >&2
      rm -f \"\$TMP_INSTALL\"; rm -rf '${pkg}-${sha}' '${pkg}-${sha}.tar.gz'
      exit 1
    fi
    tail -3 \"\$TMP_INSTALL\"
    rm -f \"\$TMP_INSTALL\"
    rm -rf '${pkg}-${sha}' '${pkg}-${sha}.tar.gz'${pin}
    Rscript -e 'cat(\"${pkg}=\", as.character(packageVersion(\"${pkg}\")), \"\\n\", sep=\"\")'
  "
  if [ "$host" = "m4" ]; then
    bash -c "$cmd"
  else
    ssh -o ConnectTimeout=10 "$host" "$cmd"
  fi
}

# Resolve each package's sha ONCE, before any host is touched. Resolving
# per (host, pkg) is six API calls over the script's 3-5 minutes, and a push
# in that window leaves hosts on different commits — the exact axis
# fresh_sha-as-a-parity-key and study_area_verify.sql's cross-host assertion
# now refuse a run over. One resolve, one commit, every host.
declare -a SHAS=()
for pkg in "${PKGS[@]}"; do
  if ! sha=$(resolve_sha "$pkg"); then
    echo "FATAL: could not resolve $pkg main sha from the GitHub API." >&2
    echo "  Refusing to install unpinned: fresh would log fresh_sha NULL and" >&2
    echo "  study_area_run.sh would refuse the run at pre-flight." >&2
    exit 1
  fi
  SHAS+=("$sha")
  echo "resolved $pkg -> ${sha:0:12}"
done

for h in "${HOSTS[@]}"; do
  echo "=== $h ==="
  i=0
  for pkg in "${PKGS[@]}"; do
    install_remote "$h" "$pkg" "${SHAS[$i]}"
    i=$((i + 1))
  done
done
