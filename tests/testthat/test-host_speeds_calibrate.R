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
  writeLines(c("wsg\thost_key\tname\tspeed\tspeed_source\tweight_unit\tweight",
               sprintf("%s\t%s\t%s\t1\tequal (no learned state)\t%s\t50", names(plan_host), plan_host,
                       name, unit)),
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
  expect_match(paste(r$out, collapse = "\n"), "the plan gives it")
  r <- cal_run(cal_world(model_rows = character()))
  expect_false(r$status == 0L)
  expect_match(paste(r$out, collapse = "\n"), "no finished model rows")
})
