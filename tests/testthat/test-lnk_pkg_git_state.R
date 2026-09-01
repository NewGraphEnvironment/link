# Package code identity: `.lnk_pkg_git_state()` and its two wrappers (link#264).
#
# `fresh_sha` was NULL on every dispatcher row of the first provenanced run,
# and the standing explanation -- "m1 installs fresh locally, RemoteType local,
# no RemoteSha" -- was measured false on 2026-09-01. The SHA was in
# `packageDescription("fresh")$RemoteSha` the whole time; the resolver walked
# an env var and then a `.git` an installed package does not have.
#
# Both known answers per tier, from real installs wherever one exists, because
# the defect was never in the logic -- it was in which sources the logic
# consulted, and a mock supplies whatever source the test author already
# believed in.

skip_if_no_git <- function() {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
}

# The tier-2 skip condition, keyed on a fact INDEPENDENT of the function under
# test. Gating on `.lnk_pkg_remote_sha()` itself was the first draft, and a
# restore-the-bug probe showed why it was worthless: patching that function to
# return NA — the exact pre-change behaviour — turned all five tier-2 tests
# into SKIPs and the file reported FAIL 0. It could not go red for the
# regression it exists to catch.
#
# `RemoteType` is written by the same install step and read by nothing in link,
# so it moves only when the install method genuinely changes.
skip_unless_fresh_is_git_installed <- function() {
  skip_if_not_installed("fresh")
  d <- suppressWarnings(utils::packageDescription("fresh"))
  skip_if(!is.list(d) ||
            !isTRUE(d$RemoteType %in% c("github", "git", "gitlab", "bitbucket")),
          "installed fresh is not a git-backed install - tier 2 unexercised")
}

# --- .lnk_pkg_remote_sha ----------------------------------------------------

test_that("premise: fresh carries a RemoteSha and a base package does not", {
  # The premise the whole DESCRIPTION tier rests on, asserted beside the
  # behaviour rather than assumed by it. If a future install method stops
  # recording RemoteSha, THIS fails and names the real cause, instead of the
  # tier tests failing and blaming the resolver.
  skip_unless_fresh_is_git_installed()
  expect_match(.lnk_pkg_remote_sha("fresh"), "^[0-9a-f]{40}$")

  # A `RemoteType: standard` install (CRAN, PPM, r-universe) writes the package
  # VERSION into RemoteSha. 278 of 300 packages in this library carry a non-hex
  # value there. The resolver must decline those, or `fresh_sha` becomes
  # "0.33.0" in a column two consumers read as a commit.
  version_shaped <- Filter(
    function(p) {
      d <- suppressWarnings(utils::packageDescription(p))
      is.list(d) && !is.null(d$RemoteSha) &&
        !grepl("^[0-9a-f]{7,40}$", d$RemoteSha)
    },
    utils::installed.packages()[, "Package"])
  skip_if(length(version_shaped) == 0L, "no version-shaped RemoteSha installed")
  expect_true(all(vapply(version_shaped,
                         function(p) is.na(.lnk_pkg_remote_sha(p)),
                         logical(1))))

  # `stats` ships with R and can never carry Remote* fields, so it is the
  # deterministic negative -- unlike `link`, whose answer depends on whether
  # the suite runs under load_all or against a pak-installed copy.
  expect_true(is.na(.lnk_pkg_remote_sha("stats")))
})

test_that(".lnk_pkg_remote_sha is NA for a package that is not installed", {
  # packageDescription() returns a bare NA rather than a list here, and
  # `NA$RemoteSha` is an error, not NULL.
  expect_true(is.na(.lnk_pkg_remote_sha("nosuchpkg")))
})

# --- tier 1: the env override -----------------------------------------------

test_that("the env vars win over every other tier", {
  skip_if_not_installed("fresh")
  withr::local_envvar(FRESH_GIT_SHA = "deadbeefdeadbeef",
                      FRESH_GIT_DIRTY = "1")
  st <- .lnk_pkg_git_state("fresh")
  expect_identical(st$sha, "deadbeefdeadbeef")
  expect_true(st$dirty)
  expect_identical(st$source, "env")

  # Premise: the tier below would have answered differently. Without this the
  # test passes for a resolver that only ever reads the env.
  withr::local_envvar(FRESH_GIT_SHA = "", FRESH_GIT_DIRTY = "")
  expect_false(identical(.lnk_pkg_git_state("fresh")$sha, "deadbeefdeadbeef"))
})

test_that("an env dirty of 0 is FALSE, not merely non-empty", {
  withr::local_envvar(LINK_GIT_DIRTY = "0")
  expect_false(.lnk_pkg_git_dirty("link"))
  withr::local_envvar(LINK_GIT_DIRTY = "true")
  expect_true(.lnk_pkg_git_dirty("link"))
})

# --- tier 2: RemoteSha from the installed DESCRIPTION -----------------------

test_that("an installed package resolves its sha from RemoteSha", {
  # The defect this issue exists to fix: 15 of 39 rows had a fresh_sha, and
  # the 24 that did not were on the host where the value was sitting in the
  # DESCRIPTION unread.
  skip_unless_fresh_is_git_installed()
  withr::local_envvar(FRESH_GIT_SHA = "", FRESH_GIT_DIRTY = "")
  remote <- .lnk_pkg_remote_sha("fresh")

  st <- .lnk_pkg_git_state("fresh")
  expect_identical(st$sha, remote)
  expect_identical(st$source, "remote_sha")
})

test_that("a RemoteSha install reads CLEAN, never NA", {
  # `fresh_dirty` was NULL on all 39 rows. A pak install from a published git
  # ref is by construction not a working tree, so FALSE is the honest answer
  # and NA is not -- "provenance unknown" and "provenance clean" are different
  # facts and only one of them lets the SHA be trusted.
  skip_if_not_installed("fresh")
  withr::local_envvar(FRESH_GIT_SHA = "", FRESH_GIT_DIRTY = "")
  skip_unless_fresh_is_git_installed()

  d <- .lnk_pkg_git_state("fresh")$dirty
  expect_false(is.na(d))
  expect_false(d)
})

test_that("an env sha with no env dirty still resolves dirty - the cypher case", {
  # Exactly a cypher: cypher_prep.sh has always written FRESH_GIT_SHA and
  # never FRESH_GIT_DIRTY. Under a single-tier-wins design the env would take
  # the whole state and dirty would stay NA, which is the column being fixed.
  # sha and dirty resolve through their OWN tier lists for this reason.
  skip_unless_fresh_is_git_installed()
  # Read from the DESCRIPTION rather than hardcoded, because the equality with
  # RemoteSha is exactly what licenses the FALSE below -- a pinned literal
  # would stop being that the day fresh is upgraded.
  withr::local_envvar(FRESH_GIT_SHA = .lnk_pkg_remote_sha("fresh"),
                      FRESH_GIT_DIRTY = "")

  st <- .lnk_pkg_git_state("fresh")
  expect_identical(st$source, "env")
  expect_false(is.na(st$dirty))
  expect_false(st$dirty)
})

test_that("an env sha that is NOT the built commit does not read clean", {
  # Tier 2's FALSE is a statement about the commit RemoteSha names, so it may
  # only attach to a SHA that IS that commit. Applied unconditionally it would
  # certify a tree this host never built -- clean asserted about the wrong
  # commit, which is precisely what the dirty flag exists to prevent.
  #
  # `fresh` is installed with no .git, so the honest answer here is NA: we do
  # not know. On a real cypher FRESH_GIT_DIRTY answers instead, which is why
  # cypher_prep.sh writing it is still worth its two lines.
  skip_unless_fresh_is_git_installed()
  withr::local_envvar(FRESH_GIT_SHA = "0000000000000000000000000000000000000000",
                      FRESH_GIT_DIRTY = "")
  st <- .lnk_pkg_git_state("fresh")
  expect_identical(st$source, "env")
  expect_true(is.na(st$dirty))

  # And the env override still reaches it, so the state is recoverable.
  withr::local_envvar(FRESH_GIT_DIRTY = "1")
  expect_true(.lnk_pkg_git_state("fresh")$dirty)
})

# --- tier 3: the .git walk --------------------------------------------------

test_that("a source checkout still resolves through .git, not RemoteSha", {
  # The dispatcher's `link`: pkgload::load_all() from a checkout, whose
  # DESCRIPTION has no Remote* fields at all (they are written at install).
  # This tier must keep working exactly as before -- link_sha has never been
  # NULL and this change must not make it so.
  skip_if_no_git()
  withr::local_envvar(LINK_GIT_SHA = "", LINK_GIT_DIRTY = "")
  st <- .lnk_pkg_git_state("link")
  skip_if(is.na(st$sha) || !identical(st$source, "git"),
          "link is not loaded from a git checkout here")
  expect_match(st$sha, "^[0-9a-f]{40}$")
  expect_false(is.na(st$dirty))
})

test_that("nothing resolves to NA sha, NA dirty and NA source together", {
  # `stats` is installed, has no Remote* fields and no .git. Every tier must
  # decline, and decline honestly -- NA, never FALSE, since a failure read as
  # clean is a SHA silently certified against an unknown tree.
  withr::local_envvar(STATS_GIT_SHA = "", STATS_GIT_DIRTY = "")
  st <- .lnk_pkg_git_state("stats")
  expect_true(is.na(st$sha))
  expect_true(is.na(st$dirty))
  expect_true(is.na(st$source))
})

test_that("an uninstalled package yields NA on every field", {
  st <- .lnk_pkg_git_state("nosuchpkg")
  expect_true(is.na(st$sha))
  expect_true(is.na(st$dirty))
  expect_true(is.na(st$source))
})

# --- the wrappers cannot disagree with the resolver -------------------------

test_that("both wrappers report the same tier as the resolver", {
  # The reason this is one function with two wrappers rather than two parallel
  # three-tier resolvers: two functions inferring the same fact from the same
  # DESCRIPTION are free to drift, and the drift is silent.
  #
  # Checked in the state where the two fields come from DIFFERENT tiers -- sha
  # from the env, dirty from RemoteSha -- because that is the only arrangement
  # a naive re-implementation gets wrong.
  skip_unless_fresh_is_git_installed()
  remote <- .lnk_pkg_remote_sha("fresh")
  withr::local_envvar(FRESH_GIT_SHA = remote, FRESH_GIT_DIRTY = "")

  st <- .lnk_pkg_git_state("fresh")
  expect_identical(.lnk_pkg_git_sha("fresh"), st$sha)
  expect_identical(.lnk_pkg_git_dirty("fresh"), st$dirty)
  expect_identical(.lnk_pkg_git_sha("fresh"), remote)
  expect_identical(st$source, "env")      # sha from tier 1
  expect_false(.lnk_pkg_git_dirty("fresh"))  # dirty from tier 2
})
