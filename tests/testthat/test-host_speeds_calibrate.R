# data-raw/host_speeds_calibrate.R: a run's model legs into the learned-speed
# state and its history (link#259). Each test writes a small run directory
# (phases, run_wsgs, coverage) and a plan, and runs the script.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the script is absent and
# these skip; devtools::test() from the source tree runs them.

cal_script <- function() {
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "host_speeds_calibrate.R"),
                     mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), "data-raw/host_speeds_calibrate.R absent")
  p
}

cal_uid <- "20261101_000000-aaaaaaaa"

# A run of four groups: A, B on the dispatcher (m4), C, D on job1 (cloud).
# Each leg is projected at 100 min; the dispatcher took 100 and job1 125.
cal_world <- function(model_rows = NULL, account = c(dispatcher = "ok", job1 = "ok"),
                      coverage = c(A = "recompute", B = "recompute", C = "recompute", D = "recompute"),
                      skip = c(A = "no", B = "no", C = "no", D = "no"), unit = "min",
                      plan_host = c(A = "dispatcher", B = "dispatcher", C = "job1", D = "job1")) {
  d <- tempfile("calrun")
  dir.create(d)
  ts <- "20261101_000000"
  model_rows <- model_rows %||% c("model\tdispatcher\t2026-11-01T01:00:00Z\t2026-11-01T02:40:00Z",
                                  "model\tjob1\t2026-11-01T01:00:00Z\t2026-11-01T03:05:00Z")
  # phase, host, start, end; then minutes and groups blank and the status.
  acc <- sprintf("account\t%s\t2026-11-01T03:10:00Z\t2026-11-01T03:10:00Z\t\t\t%s",
                 names(account), account)
  mod <- if (length(model_rows)) sprintf("%s\t\t\tok", model_rows)
  writeLines(c("run_uid\tphase\thost\tstart_utc\tend_utc\tminutes\tgroups\tstatus",
               paste0(cal_uid, "\t", c(mod, acc))),
             file.path(d, paste0(ts, "_phases.tsv")))
  writeLines(c("wsg\thost\tskip\trun_uid\tbucket_mode",
               sprintf("%s\t%s\t%s\t%s\tclosure", names(skip),
                       c(A = "dispatcher", B = "dispatcher", C = "job1", D = "job1")[names(skip)],
                       skip, cal_uid)),
             file.path(d, paste0(ts, "_run_wsgs.tsv")))
  writeLines(c("wsg\tclass", sprintf("%s\t%s", names(coverage), coverage)),
             file.path(d, paste0(ts, "_coverage.tsv")))
  name <- ifelse(plan_host == "dispatcher", "m4", "cloud")
  writeLines(c("wsg\thost_key\tname\tspeed\tspeed_source\tweight_unit\tweight\tminutes\tmeasured_by",
               sprintf("%s\t%s\t%s\t1\tequal (no learned state)\t%s\t50\t50\t%s", names(plan_host),
                       plan_host, name, unit, name)),
             file.path(d, "plan.tsv"))
  list(dir = d, phases = file.path(d, paste0(ts, "_phases.tsv")), plan = file.path(d, "plan.tsv"),
       state = file.path(d, "host_speeds.tsv"), history = file.path(d, "host_speeds_history.tsv"))
}

cal_run <- function(w, ...) {
  argv <- c(paste0("--plan=", w$plan), paste0("--phases=", w$phases),
            paste0("--state=", w$state), paste0("--history=", w$history), ...)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c(shQuote(cal_script()), shQuote(argv)),
                                  stdout = TRUE, stderr = TRUE))
  list(out = out, status = attr(out, "status") %||% 0L)
}

test_that("a run's legs update the state and append the history", {
  w <- cal_world()
  r <- cal_run(w)
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  st <- utils::read.delim(w$state)
  expect_equal(st$name, c("cloud", "m4"))
  rr <- 225 / 200
  expect_equal(st$factor[st$name == "cloud"], round(0.7 + 0.3 / (1.25 / rr), 4))
  expect_equal(st$factor[st$name == "m4"], round(0.7 + 0.3 / (1 / rr), 4))
  h <- utils::read.delim(w$history)
  expect_equal(nrow(h), 2)
  expect_equal(unique(h$run_uid), cal_uid)
  expect_equal(unique(h$run_ratio), round(rr, 4))
  # A run is calibrated once.
  r2 <- cal_run(w)
  expect_false(r2$status == 0L)
  expect_match(paste(r2$out, collapse = "\n"), "already holds run")
})

test_that("--dry-run writes nothing", {
  w <- cal_world()
  r <- cal_run(w, "--dry-run")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  expect_false(file.exists(w$state))
  expect_false(file.exists(w$history))
  expect_match(paste(r$out, collapse = "\n"), "nothing written")
})

test_that("the later of two model rows is the leg's end", {
  rows <- c("model\tdispatcher\t2026-11-01T01:00:00Z\t2026-11-01T02:40:00Z",
            "model\tjob1\t2026-11-01T01:00:00Z\t2026-11-01T01:30:00Z",
            "model\tjob1\t2026-11-01T01:00:00Z\t2026-11-01T03:05:00Z")
  w <- cal_world(model_rows = rows)
  r <- cal_run(w, "--dry-run")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  expect_match(paste(r$out, collapse = "\n"), "\\| job1 \\| cloud \\| 1.000 \\| 2 \\| 100.0 \\| 125.0 \\|")
})

test_that("a host that did not finish its bucket, or that the operator names, is left out", {
  w <- cal_world(account = c(dispatcher = "ok", job1 = "failed"))
  r <- cal_run(w)
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  h <- utils::read.delim(w$history)
  expect_equal(h$action[h$name == "cloud"], "skipped: account failed")
  expect_false("cloud" %in% utils::read.delim(w$state)$name)
  w2 <- cal_world()
  r <- cal_run(w2, "--skip=m4:stall: KTSU 65 min")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  h <- utils::read.delim(w2$history)
  expect_equal(h$action[h$name == "m4"], "skipped: stall: KTSU 65 min")
  expect_false(cal_run(cal_world(), "--skip=m9:x")$status == 0L)
})

test_that("SKIPped groups and groups with no rows leave the projection", {
  # D was SKIPped on resume (built earlier under this run_uid), so it has rows
  # from this run but no time in this leg; B ran and left no rows.
  w <- cal_world(skip = c(A = "no", B = "no", C = "no", D = "yes"),
                 coverage = c(A = "recompute", B = "no_rows", C = "recompute", D = "recompute"))
  r <- cal_run(w, "--dry-run")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  out <- paste(r$out, collapse = "\n")
  expect_match(out, "\\| dispatcher \\| m4 \\| 1.000 \\| 1 \\| 50.0 \\|")
  expect_match(out, "\\| job1 \\| cloud \\| 1.000 \\| 1 \\| 50.0 \\|")
})

test_that("the calibrator refuses what it cannot compare", {
  r <- cal_run(cal_world(unit = "segments"))
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "weighted in segments")
  r <- cal_run(cal_world(plan_host = c(A = "dispatcher", B = "job1", C = "job1", D = "job1")))
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "no run host was given the same groups")
  r <- cal_run(cal_world(model_rows = character()))
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "no finished model rows")
})

test_that("an unnamed worker's leg is recorded but never learned", {
  w <- cal_world()
  p <- readLines(w$plan)
  writeLines(sub("\tcloud\t", "\tworker1\t", p), w$plan)
  r <- cal_run(w)
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  h <- utils::read.delim(w$history)
  expect_match(h$action[h$name == "worker1"], "^not learned")
  expect_equal(utils::read.delim(w$state)$name, "m4")
})

test_that("a history with other columns is refused, not appended to", {
  w <- cal_world()
  writeLines(c("run_uid\tdate_utc\tname\told", "seed\td\tm1\t1"), w$history)
  r <- cal_run(w)
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "appending would misalign")
})

test_that("--skip by host key leaves out one cloud host's leg", {
  w <- cal_world(plan_host = c(A = "dispatcher", B = "dispatcher", C = "job1", D = "job2"))
  # run_wsgs must agree with the plan: D on job2, and job2 needs a model row.
  rw <- readLines(file.path(w$dir, "20261101_000000_run_wsgs.tsv"))
  writeLines(sub("^D\tjob1\t", "D\tjob2\t", rw), file.path(w$dir, "20261101_000000_run_wsgs.tsv"))
  ph <- readLines(w$phases)
  writeLines(c(ph, sprintf("%s\tmodel\tjob2\t2026-11-01T01:00:00Z\t2026-11-01T09:00:00Z\t\t\tok", cal_uid),
               sprintf("%s\taccount\tjob2\t2026-11-01T09:00:00Z\t2026-11-01T09:00:00Z\t\t\tok", cal_uid)),
             w$phases)
  r <- cal_run(w, "--dry-run", "--skip=job2:stall")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  out <- paste(r$out, collapse = "\n")
  expect_match(out, "| job2 | cloud | 1.000 | 1 |  |  | stall |", fixed = TRUE)
  expect_match(out, "\\| job1 \\| cloud \\| 1\\.000 \\| 1 \\| 50\\.0 \\|")
})

test_that("a plan packed on another state is re-normalized at the calibrating one", {
  # Packed when the state said cloud 0.5, so the cloud groups' 50 measured
  # minutes went into the plan as 25. Calibrated with no state, they count 50
  # again, and job1's leg projects at 100 as if packed on this state.
  w <- cal_world()
  p <- readLines(w$plan)
  cloud <- grepl("\tcloud\t", p)
  p[cloud] <- sub("\t50\t50\tcloud$", "\t25\t50\tcloud", p[cloud])
  writeLines(p, w$plan)
  r <- cal_run(w, "--dry-run")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  expect_match(paste(r$out, collapse = "\n"), "\\| job1 \\| cloud \\| 1\\.000 \\| 2 \\| 100\\.0 \\| 125\\.0 \\|")
})

test_that("a plan without raw minutes is refused", {
  w <- cal_world()
  p <- readLines(w$plan)
  writeLines(sub("\t[^\t]*\t[^\t]*$", "", p), w$plan)
  r <- cal_run(w)
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "lacks columns: minutes, measured_by")
})

test_that("a plan host is matched to the run host given the same groups, whatever its key", {
  # The packer keys cloud hosts job1..N by position; this run used workspace
  # job3 for them (--cy-workspaces=job3, a kept job1 leaving a gap).
  w <- cal_world()
  for (f in c(file.path(w$dir, "20261101_000000_run_wsgs.tsv"), w$phases)) {
    writeLines(gsub("\tjob1\t", "\tjob3\t", readLines(f)), f)
  }
  r <- cal_run(w, "--dry-run", "--skip=job3:stall on job3")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  expect_match(paste(r$out, collapse = "\n"), "| job3 | cloud | 1.000 | 2 |  |  | stall on job3 |",
               fixed = TRUE)
})

test_that("a leg holding a group measured by a class the state lacks is left out", {
  w <- cal_world()
  writeLines(c(paste(c("name", "factor", "last_updated", "n_runs", "source_run_uid"), collapse = "\t"),
               "m4\t1\td\t1\tu", "cloud\t1\td\t1\tu"), w$state)
  # D, on job1 (cloud), was measured last run by a worker the state never
  # learned (m2); C was measured by cloud itself.
  p <- readLines(w$plan)
  writeLines(sub("^(D\t.*)\tcloud$", "\\1\tm2", p), w$plan)
  r <- cal_run(w, "--dry-run")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  out <- paste(r$out, collapse = "\n")
  expect_match(out, "groups measured by m2, which the state does not hold", fixed = TRUE)
  # m4's own groups were measured by m4, which the state holds: it is learned.
  expect_match(out, "\\| m4 \\| 1\\.000 \\| 1\\.000 \\|")
})

test_that("a run that swapped the dispatcher's and a cloud host's lists is refused", {
  w <- cal_world()
  rwf <- file.path(w$dir, "20261101_000000_run_wsgs.tsv")
  rw <- readLines(rwf)
  rw <- sub("\tdispatcher\t", "\tTMP\t", rw)
  rw <- sub("\tjob1\t", "\tdispatcher\t", rw)
  writeLines(sub("\tTMP\t", "\tjob1\t", rw), rwf)
  r <- cal_run(w, "--dry-run")
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "ran in another role")
})

test_that("--skip names the run's host key, not the plan's", {
  # Plan: job1 {C}, job2 {D}. Run: job3 {C}, job1 {D}. --skip=job1 means the
  # run's job1, the host that ran D, and nothing else.
  w <- cal_world(plan_host = c(A = "dispatcher", B = "dispatcher", C = "job1", D = "job2"))
  rwf <- file.path(w$dir, "20261101_000000_run_wsgs.tsv")
  rw <- readLines(rwf)
  rw <- sub("^C\tjob1\t", "C\tjob3\t", rw)
  writeLines(rw, rwf)
  ph <- readLines(w$phases)
  ph <- sub("\tjob1\t", "\tjob3\t", ph)
  writeLines(c(ph, sprintf("%s\tmodel\tjob1\t2026-11-01T01:00:00Z\t2026-11-01T02:00:00Z\t\t\tok", cal_uid),
               sprintf("%s\taccount\tjob1\t2026-11-01T02:00:00Z\t2026-11-01T02:00:00Z\t\t\tok", cal_uid)),
             w$phases)
  r <- cal_run(w, "--dry-run", "--skip=job1:stall")
  expect_equal(r$status, 0L, info = paste(r$out, collapse = "\n"))
  out <- paste(r$out, collapse = "\n")
  expect_match(out, "| job1 | cloud | 1.000 | 1 |  |  | stall |", fixed = TRUE)
  expect_match(out, "\\| job3 \\| cloud \\| 1\\.000 \\| 1 \\| 50\\.0 \\|")
})

test_that("a run in which every leg is left out still prints why", {
  w <- cal_world()
  writeLines(c(paste(c("name", "factor", "last_updated", "n_runs", "source_run_uid"), collapse = "\t"),
               "m4\t1\td\t1\tu", "cloud\t1\td\t1\tu"), w$state)
  p <- readLines(w$plan)
  writeLines(sub("\t(m4|cloud)$", "\tm2", p), w$plan)
  r <- cal_run(w, "--dry-run")
  expect_false(r$status == 0L)
  out <- paste(r$out, collapse = "\n")
  expect_match(out, "groups measured by m2, which the state does not hold", fixed = TRUE)
  expect_match(out, "every leg is left out (reasons above)", fixed = TRUE)
})
