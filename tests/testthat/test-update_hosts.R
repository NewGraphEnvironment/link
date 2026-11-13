# scripts/update_hosts.sh (link#269): fresh is installed at the tag DESCRIPTION's
# Remotes: pins, never at fresh's main; the host the script runs on is installed
# locally. Stubs on PATH stand in for curl, ssh, Rscript and hostname, so nothing
# is installed and nothing leaves the machine. scripts/ is .Rbuildignore'd, so
# these skip under R CMD check.

uh_script <- function() {
  p <- normalizePath(testthat::test_path("..", "..", "scripts", "update_hosts.sh"),
                     mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), "scripts/update_hosts.sh absent")
  p
}

# A repo layout the script resolves REPO_ROOT against, with its own DESCRIPTION.
uh_world <- function(remotes, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(d, "scripts"))
  dir.create(file.path(d, "bin"))
  file.copy(uh_script(), file.path(d, "scripts", "update_hosts.sh"))
  writeLines(c("Package: link", "Version: 0.0.0", "Remotes:", remotes,
               "Encoding: UTF-8"), file.path(d, "DESCRIPTION"))
  stub <- function(name, body) {
    f <- file.path(d, "bin", name)
    writeLines(c("#!/bin/sh", body), f)
    Sys.chmod(f, "755")
  }
  log <- file.path(d, "calls")
  # The API answers a sha per ref, so the test can see which ref was asked for.
  stub("curl", c(sprintf('echo "curl $*" >> %s', shQuote(log)),
                 'case "$*" in',
                 '  *commits/v9.9.9*) printf %s 1111111111111111111111111111111111111111 ;;',
                 '  *commits/main*) printf %s 2222222222222222222222222222222222222222 ;;',
                 '  *) printf %s notasha ;;',
                 'esac'))
  # The remote prints the completion marker unless no_marker exists: Tailscale SSH
  # to a Mac exits 0 whatever ran, so the marker is what the script reads.
  stub("ssh", c(sprintf('echo "ssh $*" >> %s', shQuote(log)),
                sprintf('[ -f %s ] || echo __UH_OK__', shQuote(file.path(d, "no_marker")))))
  stub("Rscript", sprintf('echo "Rscript $*" >> %s', shQuote(log)))
  stub("hostname", 'echo stubhost')
  list(dir = d, log = log)
}

uh_run <- function(w, args = character(), alias = "m1", bash = "bash") {
  out <- withr::with_envvar(
    c(PATH = paste(file.path(w$dir, "bin"), Sys.getenv("PATH"), sep = ":"),
      LNK_HOST_ALIAS = alias),
    suppressWarnings(system2(bash, c(file.path(w$dir, "scripts", "update_hosts.sh"), args),
                             stdout = TRUE, stderr = TRUE)))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L,
       calls = if (file.exists(w$log)) readLines(w$log) else character())
}

test_that("fresh is resolved at its Remotes: tag, link at main", {
  w <- uh_world(c("    NewGraphEnvironment/crate,", "    NewGraphEnvironment/fresh@v9.9.9,",
                  "    NewGraphEnvironment/wet@v0.4.7"))
  r <- uh_run(w, "--dry-run")
  expect_equal(r$status, 0L)
  expect_match(r$out, "resolved fresh@v9.9.9 -> 111111111111", fixed = TRUE)
  expect_match(r$out, "resolved link@main -> 222222222222", fixed = TRUE)
  expect_match(r$out, "pins wet@v0.4.7", fixed = TRUE)
  # Asked for the tag, never fresh's main.
  expect_true(any(grepl("fresh/commits/v9.9.9", r$calls, fixed = TRUE)))
  expect_false(any(grepl("fresh/commits/main", r$calls, fixed = TRUE)))
  # A dry run installs nothing anywhere.
  expect_false(any(grepl("^(ssh|Rscript) ", r$calls)))
})

test_that("with no fresh pin it refuses rather than fall back to main", {
  w <- uh_world(c("    NewGraphEnvironment/crate,", "    NewGraphEnvironment/fresh"))
  r <- uh_run(w, "--dry-run")
  expect_false(r$status == 0L)
  expect_match(r$out, "does not pin NewGraphEnvironment/fresh@<tag>", fixed = TRUE)
})

test_that("the host it runs on is installed locally, others over ssh, cypher by tarball", {
  w <- uh_world("    NewGraphEnvironment/fresh@v9.9.9")
  r <- uh_run(w, "--dry-run", alias = "m4")
  expect_match(r$out, "local host: m4", fixed = TRUE)
  expect_match(r$out, "=== m4 ===\n  would install fresh@v9.9.9 (111111111111) by pak, local", fixed = TRUE)
  expect_match(r$out, "=== m1 ===\n  would install fresh@v9.9.9 (111111111111) by pak, ssh", fixed = TRUE)
  expect_match(r$out, "=== cypher ===\n  would install fresh@v9.9.9 (111111111111) by tarball, ssh",
               fixed = TRUE)
})

test_that("a pak install names the tag and checks RemoteSha before unpinning", {
  w <- uh_world("    NewGraphEnvironment/fresh@v9.9.9")
  r <- uh_run(w, c("fresh", "m4"), alias = "m1")
  # The remote command spans lines; read the log whole from the one ssh call.
  # Two ssh calls: the install, then fresh's re-check after every install on the host.
  starts <- which(startsWith(r$calls, "ssh "))
  expect_identical(length(starts), 2L)
  ssh <- paste(r$calls[seq(starts[1], starts[2] - 1L)], collapse = "\n")
  expect_match(ssh, "pak::pkg_install(\"NewGraphEnvironment/fresh@v9.9.9\"", fixed = TRUE)
  expect_match(ssh, "1111111111111111111111111111111111111111", fixed = TRUE)
  expect_match(ssh, "FRESH_GIT_SHA|FRESH_GIT_DIRTY", fixed = TRUE)
})

test_that("update_hosts.sh parses under macOS /bin/bash 3.2", {
  skip_if_not(file.exists("/bin/bash"))
  out <- suppressWarnings(system2("/bin/bash", c("-n", uh_script()), stdout = TRUE, stderr = TRUE))
  expect_null(attr(out, "status"))
})

test_that("link installs without its dependencies, and fresh is re-checked after it", {
  # pak resolves link@main's own Remotes: and would put fresh back at main's pin.
  w <- uh_world("    NewGraphEnvironment/fresh@v9.9.9")
  r <- uh_run(w, "m4", alias = "m1")
  log <- paste(r$calls, collapse = "\n")
  expect_match(log, 'NewGraphEnvironment/link@main", upgrade = FALSE, ask = FALSE, dependencies = FALSE',
               fixed = TRUE)
  # fresh at pak's default (hard dependencies only), not TRUE, which adds Suggests.
  expect_match(log, 'NewGraphEnvironment/fresh@v9.9.9", upgrade = FALSE, ask = FALSE, dependencies = NA',
               fixed = TRUE)
  expect_match(log, "after the installs, not 1111111111111111111111111111111111111111", fixed = TRUE)
})

test_that("an ssh that exits 0 without the completion marker fails the run", {
  # Over Tailscale SSH to a Mac a failed remote command still exits 0.
  w <- uh_world("    NewGraphEnvironment/fresh@v9.9.9")
  file.create(file.path(w$dir, "no_marker"))
  r <- uh_run(w, c("fresh", "m4"), alias = "m1")
  expect_false(r$status == 0L)
  expect_match(r$out, "FATAL: install of fresh on m4 failed (no completion marker", fixed = TRUE)
})
