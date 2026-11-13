#!/usr/bin/env bash
# scripts/update_hosts.sh
#
# Update fresh and link on m4, m1 and cypher. fresh is installed at the tag
# link's DESCRIPTION pins in `Remotes:` (link#269), never at fresh's main, so
# this script cannot put a host on a fresh no other host installs; bumping
# fresh is a DESCRIPTION edit. link, which nothing pins, is installed at main's
# head.
#
# Install method per host: pak (`pak::pkg_install("<owner>/<pkg>@<ref>")`),
# which writes RemoteSha, the identity link's pre-flight compares against; then
# any FRESH_GIT_SHA / FRESH_GIT_DIRTY pin is removed from ~/.Renviron, since an
# old pin there would outrank RemoteSha. On cypher, and everywhere under
# --tarball, the older path: R CMD INSTALL of a source tarball fetched by sha
# (pak's libpath bug r-lib/pak#658 on cypher), which writes no Remote* fields,
# so fresh's commit is pinned in ~/.Renviron instead.
#
# Usage:
#   scripts/update_hosts.sh                    # both packages on all 3 hosts
#   scripts/update_hosts.sh fresh              # fresh only
#   scripts/update_hosts.sh link cypher        # link on cypher only
#   scripts/update_hosts.sh --dry-run          # print the refs and per-host plan; install nothing
#   scripts/update_hosts.sh --tarball m1       # the tarball path on m1 too
#
# The host the script runs on is installed locally, never over ssh to itself:
# LNK_HOST_ALIAS, else `hostname -s`.
#
# Total wall: ~3-5 min for both packages across all 3 hosts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKGS=()
HOSTS=()
DRY_RUN=0
TARBALL=0
for arg in "$@"; do
  case "$arg" in
    link|fresh) PKGS+=("$arg") ;;
    m4|m1|cypher) HOSTS+=("$arg") ;;
    --dry-run) DRY_RUN=1 ;;
    --tarball) TARBALL=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done
[ ${#PKGS[@]} -eq 0 ] && PKGS=(fresh link)
[ ${#HOSTS[@]} -eq 0 ] && HOSTS=(m4 m1 cypher)
LOCAL_HOST="${LNK_HOST_ALIAS:-$(hostname -s)}"

# The ref DESCRIPTION's Remotes: pins for a package (`NewGraphEnvironment/<pkg>@<ref>`),
# or nothing when it is not pinned.
remotes_ref() {   # $1 = pkg
  awk -v p="NewGraphEnvironment/$1@" '
    /^Remotes:/ { on = 1 }
    on && /^[A-Za-z]/ && !/^Remotes:/ { on = 0 }
    on { n = split($0, a, /[ ,\t]+/); for (i = 1; i <= n; i++) if (index(a[i], p) == 1) { print substr(a[i], length(p) + 1); exit } }
  ' "$REPO_ROOT/DESCRIPTION"
}

# The ref each package is installed at: fresh at its pin, which must exist; link at main.
pkg_ref() {   # $1 = pkg
  local ref
  ref=$(remotes_ref "$1")
  if [ "$1" = "fresh" ] && [ -z "$ref" ]; then
    echo "FATAL: DESCRIPTION's Remotes: does not pin NewGraphEnvironment/fresh@<tag>;" >&2
    echo "  refusing to fall back to fresh's main (link#269)." >&2
    return 1
  fi
  printf '%s' "${ref:-main}"
}

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
resolve_sha() {   # $1 = pkg, $2 = ref (a tag or a branch). Prints the sha, or exits non-zero.
  local sha
  sha=$(curl -sSL -H 'Accept: application/vnd.github.sha' \
        "https://api.github.com/repos/NewGraphEnvironment/$1/commits/$2") || return 1
  # Anchored, because an API error body is a 200-with-JSON and would otherwise
  # be written into the env var as if it were a commit.
  printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$' || return 1
  printf '%s' "$sha"
}

# Run a command on a host: locally on the host this runs on, else over ssh.
on_host() {   # $1 = host, $2 = command
  if [ "$1" = "$LOCAL_HOST" ]; then
    bash -c "$2"
  else
    ssh -o ConnectTimeout=10 "$1" "$2"
  fi
}

# The same, judged by what the command printed: over Tailscale SSH to a Mac, ssh
# exits 0 whatever the remote command returned, so a command this script must
# stop on ends by printing __UH_OK__ and its absence is the failure.
on_host_checked() {   # $1 = host, $2 = command (ending in `echo __UH_OK__`), $3 = what it is
  local out rc=0
  out=$(on_host "$1" "$2" 2>&1) || rc=$?
  printf '%s\n' "$out" | grep -v '^__UH_OK__$' || true
  if [ "$rc" != 0 ] || ! printf '%s\n' "$out" | grep -qx '__UH_OK__'; then
    echo "FATAL: $3 on $1 failed (no completion marker; exit $rc)" >&2
    exit 1
  fi
}

# pak where it works: it writes RemoteSha, so the installed build names its own
# commit, which must be the one resolved here. An old FRESH_GIT_SHA pin in
# ~/.Renviron would outrank RemoteSha (link's resolver reads the env first), so
# it is removed once the install is confirmed.
install_pak() {
  local host="$1" pkg="$2" ref="$3" sha="$4"
  local upkg cmd unpin=""
  upkg=$(printf '%s' "$pkg" | tr '[:lower:]' '[:upper:]')
  if [ "$pkg" = "fresh" ]; then
    unpin="
    RENV=\"\$HOME/.Renviron\"
    if [ -f \"\$RENV\" ]; then
      RENV_UMASK=\$(umask); umask 077
      RC=0
      grep -vE '^(${upkg}_GIT_SHA|${upkg}_GIT_DIRTY)=' \"\$RENV\" > \"\$RENV.tmp\" || RC=\$?
      if [ \"\$RC\" -gt 1 ]; then
        echo 'FATAL: could not read ~/.Renviron; refusing to overwrite it' >&2
        rm -f \"\$RENV.tmp\"; exit 1
      fi
      mv \"\$RENV.tmp\" \"\$RENV\"; chmod 600 \"\$RENV\"; umask \"\$RENV_UMASK\"
    fi"
  fi
  # link without its dependencies: pak resolves link@main's own Remotes: and would
  # reinstall fresh at main's pin over the one just installed (0.52.0 back to 0.48.0
  # on m4, 2026-11-02). fresh's RemoteSha is checked again after link (below).
  # fresh at pak's default (NA: hard dependencies only); TRUE would add its Suggests,
  # among them a private remote a host without a usable GitHub token cannot install.
  local deps="NA"
  [ "$pkg" != "link" ] || deps="FALSE"
  cmd="set -e
    Rscript -e 'pak::pkg_install(\"NewGraphEnvironment/${pkg}@${ref}\", upgrade = FALSE, ask = FALSE, dependencies = ${deps})'
    got=\$(Rscript -e 'cat(utils::packageDescription(\"${pkg}\")\$RemoteSha)')
    if [ \"\$got\" != '${sha}' ]; then
      echo \"FATAL: ${pkg} installed with RemoteSha \$got, not ${sha} (${ref}); nothing unpinned\" >&2
      exit 1
    fi${unpin}
    echo '${pkg}_sha=${sha} (${ref}, pak)'
    Rscript -e 'cat(\"${pkg}=\", as.character(packageVersion(\"${pkg}\")), \"\\n\", sep=\"\")'
    echo __UH_OK__
  "
  on_host_checked "$host" "$cmd" "install of $pkg"
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
  on_host "$host" "$cmd"
}

# Resolve each package's sha ONCE, before any host is touched. Resolving
# per (host, pkg) is six API calls over the script's 3-5 minutes, and a push
# in that window leaves hosts on different commits — the exact axis
# fresh_sha-as-a-parity-key and study_area_verify.sql's cross-host assertion
# now refuse a run over. One resolve, one commit, every host.
declare -a SHAS=() REFS=()
FRESH_SHA=""
for pkg in "${PKGS[@]}"; do
  ref=$(pkg_ref "$pkg") || exit 1
  if ! sha=$(resolve_sha "$pkg" "$ref"); then
    echo "FATAL: could not resolve $pkg@$ref to a commit from the GitHub API." >&2
    echo "  Refusing to install unpinned: fresh would log fresh_sha NULL and" >&2
    echo "  study_area_run.sh would refuse the run at pre-flight." >&2
    exit 1
  fi
  REFS+=("$ref")
  SHAS+=("$sha")
  [ "$pkg" != fresh ] || FRESH_SHA="$sha"
  echo "resolved $pkg@$ref -> ${sha:0:12}"
done
# wet is pinned too; recorded here, installed by cypher_prep.sh and by hand.
wet_ref=$(remotes_ref wet)
[ -z "$wet_ref" ] || echo "note: DESCRIPTION pins wet@$wet_ref (not installed by this script)"
echo "local host: $LOCAL_HOST (installed without ssh)"

for h in "${HOSTS[@]}"; do
  echo "=== $h ==="
  i=0
  for pkg in "${PKGS[@]}"; do
    if [ "$h" = "cypher" ] || [ "$TARBALL" = 1 ]; then how=tarball; else how=pak; fi
    where=ssh; [ "$h" != "$LOCAL_HOST" ] || where=local
    if [ "$DRY_RUN" = 1 ]; then
      echo "  would install $pkg@${REFS[$i]} (${SHAS[$i]:0:12}) by $how, $where"
    elif [ "$how" = pak ]; then
      install_pak "$h" "$pkg" "${REFS[$i]}" "${SHAS[$i]}"
    else
      install_remote "$h" "$pkg" "${SHAS[$i]}"
    fi
    i=$((i + 1))
  done
  # Whatever installed after it, fresh must still be the pinned build on this host.
  if [ "$DRY_RUN" = 0 ] && [ -n "$FRESH_SHA" ] && [ "$h" != "cypher" ] && [ "$TARBALL" = 0 ]; then
    on_host_checked "$h" "got=\$(Rscript -e 'cat(utils::packageDescription(\"fresh\")\$RemoteSha)'); [ \"\$got\" = '$FRESH_SHA' ] || { echo \"fresh on $h is \$got after the installs, not $FRESH_SHA\" >&2; exit 1; }; echo __UH_OK__" "fresh's RemoteSha check"
  fi
done
