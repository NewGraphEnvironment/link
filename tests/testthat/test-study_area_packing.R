# data-raw/study_area_packing.R: packing groups onto hosts and learning host
# speeds from a run's legs (link#259, folding in #163).
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the helper is absent and
# these skip; devtools::test() from the source tree runs them.
#
# LNK_TEST_PACKING_LIB points the tests at a mutant copy of the helper
# (proving they fail).

pk_env <- function() {
  p <- Sys.getenv("LNK_TEST_PACKING_LIB")
  if (!nzchar(p)) {
    p <- normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_packing.R"),
                       mustWork = FALSE)
  }
  testthat::skip_if_not(file.exists(p), "data-raw/study_area_packing.R absent")
  e <- new.env()
  sys.source(p, envir = e)
  e
}

pk_fixture <- function(...) {
  testthat::test_path("..", "..", "data-raw", "logs", "packing_259", ...)
}

test_that("pack() reproduces the 2026-10-23 group-atom loads on that run's weights", {
  e <- pk_env()
  f <- pk_fixture("log_rows.tsv")
  skip_if_not(file.exists(f), "packing_259 evidence absent")
  r <- utils::read.delim(f, na.strings = "", colClasses = c(run_uid = "character"))
  w <- r$minutes[which(r$run_uid == "20261023_074321-24d85e8c")]
  expect_length(w, 241)
  p <- e$pack(w, rep(1, 4))
  # Golden: the greedy's loads on these 241 weights at equal speeds. A change to
  # the order of placement, the tie rule or the finish test moves them.
  expect_equal(round(sort(p$load), 1), c(269.1, 269.1, 269.6, 269.7))
  expect_equal(sum(p$seg), sum(w))
  expect_equal(p$load, p$seg)
})

test_that("pack() sends work to the host that finishes it earliest", {
  e <- pk_env()
  p <- e$pack(c(10, 10, 10), c(2, 1))
  expect_equal(p$assign, c(1L, 1L, 2L))
  expect_equal(p$load, c(10, 10))
})

test_that("host_class() pools every cloud host and keeps other names", {
  e <- pk_env()
  expect_equal(e$host_class(c("cypher-job1", "cypher-job3", "job2", "m1", "m4")),
               c("cloud", "cloud", "cloud", "m1", "m4"))
})

test_that("host names refuse an ssh target, an address or a domain", {
  e <- pk_env()
  expect_silent(e$host_names_check(c("m4", "cloud", "worker1")))
  for (bad in c("cypher@10.0.0.1", "10.0.0.1", "box.local", "", "a b", "host:22")) {
    expect_error(e$host_names_check(c("m4", bad)), "aliases", info = bad)
  }
})

test_that("speeds: --host-speeds, then the learned state, then equal", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud", "m4"), factor = c(1, 0.8, 1.3),
                   last_updated = "d", n_runs = 1L, source_run_uid = "u")
  s <- e$speeds_resolve(c("m4", "cloud", "cloud"), cli = c(1, 0.5, 0.5), state = st)
  expect_equal(s$speed, c(1, 0.5, 0.5))
  expect_equal(unique(s$source), "--host-speeds")
  s <- e$speeds_resolve(c("m4", "cloud"), state = st)
  expect_equal(s$speed, c(1.3, 0.8))
  expect_equal(s$source, c("learned", "learned"))
  s <- e$speeds_resolve(c("m4", "cloud"))
  expect_equal(s$speed, c(1, 1))
  expect_match(s$source, "^equal")
  expect_error(e$speeds_resolve(c("m4", "cloud"), cli = c(1, 0)), "positive")
  expect_error(e$speeds_resolve(c("m4", "cloud"), cli = 1), "2 positive")
})

test_that("a host the state does not hold takes the median and says so", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud", "m4"), factor = c(0.9, 0.8, 1.3),
                   last_updated = "d", n_runs = 1L, source_run_uid = "u")
  s <- e$speeds_resolve(c("worker1", "cloud"), state = st)
  expect_equal(s$speed, c(0.9, 0.8))
  expect_equal(s$source, c("median (no learned speed)", "learned"))
})

test_that("the state file is read whole or refused", {
  e <- pk_env()
  expect_null(e$speeds_state_read(""))
  expect_null(e$speeds_state_read(tempfile()))
  f <- tempfile(fileext = ".tsv")
  writeLines(c(paste(e$PACK_STATE_COLS, collapse = "\t"), "m1\t1\td\t1\tu", "cloud\t0.9\td\t1\tu"), f)
  s <- e$speeds_state_read(f)
  expect_equal(s$factor, c(1, 0.9))
  writeLines(c(paste(e$PACK_STATE_COLS, collapse = "\t"), "m1\t0\td\t1\tu"), f)
  expect_error(e$speeds_state_read(f), "positive")
  writeLines(c(paste(e$PACK_STATE_COLS, collapse = "\t"), "m1\t1\td\t1\tu", "m1\t2\td\t1\tu"), f)
  expect_error(e$speeds_state_read(f), "one row per name")
  writeLines(c("name\tfactor", "m1\t1"), f)
  expect_error(e$speeds_state_read(f), "expected columns")
})

test_that("measured minutes are normalized by the class that measured them", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud"), factor = c(1, 0.5),
                   last_updated = "d", n_runs = 1L, source_run_uid = "u")
  expect_equal(e$weights_normalize(c(10, 10), c("m1", "cypher-job2"), st), c(10, 5))
  expect_equal(e$weights_normalize(c(10, 10), c("m1", "cypher-job2")), c(10, 10))
  # With the state right, a group that moves class is predicted exactly: work 5
  # took 10 min on a cloud host at 0.5, so 5 min on m1.
  w <- e$weights_normalize(10, "cypher-job1", st)
  expect_equal(w / 1, 5)
})

legs_of <- function(name, speed, projected, actual, skip = NA) {
  data.frame(name = name, speed = speed, projected = projected, actual = actual, skip = skip)
}

test_that("calibration damps the observation, 0.7 old + 0.3 observed", {
  e <- pk_env()
  # cloud took 25 % longer than projected and m1 exactly the run's pooled rate.
  l <- legs_of(c("m1", "cloud"), 1, c(100, 100), c(100, 125))
  out <- e$speeds_calibrate(l, run_uid = "u1", date_utc = "d")
  rr <- 225 / 200
  h <- out$history
  expect_equal(out$run_ratio, rr)
  expect_equal(h$correction[h$name == "cloud"], 1.25 / rr)
  expect_equal(h$new[h$name == "cloud"], 0.7 + 0.3 * (1 / (1.25 / rr)))
  expect_equal(h$new[h$name == "m1"], 0.7 + 0.3 * (1 / (1 / rr)))
  expect_false(any(h$clamped))
})

test_that("a drift common to every leg moves no factor", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud"), factor = c(1, 0.8), last_updated = "d",
                   n_runs = 1L, source_run_uid = "u")
  l <- legs_of(c("m1", "cloud", "cloud"), c(1, 0.8, 0.8), c(100, 90, 110), c(115, 103.5, 126.5))
  out <- e$speeds_calibrate(l, st, run_uid = "u1", date_utc = "d")
  expect_equal(out$run_ratio, 1.15)
  expect_equal(out$history$new, out$history$old)
})

test_that("a pooled class reads its legs summed, not averaged", {
  e <- pk_env()
  l <- legs_of(c("m1", "cloud", "cloud"), 1, c(100, 10, 190), c(100, 30, 190))
  h <- e$speeds_calibrate(l, run_uid = "u1", date_utc = "d")$history
  rr <- 320 / 300
  expect_equal(h$correction[h$name == "cloud"], (220 / 200) / rr)
})

test_that("calibration clamps a run's move to at most 2 x old", {
  e <- pk_env()
  l <- legs_of(c("m1", "cloud"), 1, c(100, 100), c(10, 1000))
  h <- e$speeds_calibrate(l, run_uid = "u1", date_utc = "d")$history
  expect_true(h$clamped[h$name == "m1"])
  expect_equal(h$new[h$name == "m1"], 2)
  # The lower bound, 0.5 x old, cannot bind at 0.3 damping: 0.7 x old + 0.3 x a
  # positive observation is above 0.7 x old. The slowdown is damped instead.
  expect_false(h$clamped[h$name == "cloud"])
  expect_gt(h$new[h$name == "cloud"], 0.7)
})

test_that("a skipped leg keeps its factor and records why", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud"), factor = c(1, 0.9), last_updated = "d0",
                   n_runs = c(2L, 2L), source_run_uid = "u0")
  l <- legs_of(c("m1", "cloud", "cloud"), c(1, 0.9, 0.9), c(100, 100, 100), c(300, 100, 110),
               skip = c("stall: KTSU", NA, NA))
  out <- e$speeds_calibrate(l, st, run_uid = "u1", date_utc = "d1")
  expect_equal(out$state$factor[out$state$name == "m1"], 1)
  expect_equal(out$state$n_runs[out$state$name == "m1"], 2L)
  expect_equal(out$history$action[out$history$name == "m1"], "skipped: stall: KTSU")
  expect_equal(out$run_ratio, 210 / 200)
  expect_equal(out$state$n_runs[out$state$name == "cloud"], 3L)
})

test_that("calibration refuses what it cannot read", {
  e <- pk_env()
  expect_error(e$speeds_calibrate(legs_of("m1", 1, 100, 100)[0, ], run_uid = "u", date_utc = "d"),
               "no legs")
  expect_error(e$speeds_calibrate(legs_of(c("cloud", "cloud"), c(1, 0.9), 100, 100),
                                  run_uid = "u", date_utc = "d"), "two speeds")
  expect_error(e$speeds_calibrate(legs_of("m1", 1, 0, 100), run_uid = "u", date_utc = "d"),
               "positive")
  expect_error(e$speeds_calibrate(legs_of("m1", 1, 100, 100, skip = "x"),
                                  run_uid = "u", date_utc = "d"), "every leg is skipped")
})

# Pack, run, calibrate, repeat, against a known truth: the cloud class at 0.7
# of m1, a drift that changes every run, and a first build measured on m1.
pk_simulate <- function(e, runs, calibrate) {
  set.seed(1)
  w <- stats::rlnorm(240, 0, 1.2)
  hosts <- c("m1", "cloud", "cloud", "cloud")
  truth <- c(m1 = 1, cloud = 0.7)
  state <- NULL
  meas <- w
  meas_host <- rep("m1", 240)
  for (r in seq_len(runs)) {
    sp <- e$speeds_resolve(hosts, state = state)
    p <- e$pack(e$weights_normalize(meas, meas_host, state), sp$speed)
    act <- w / truth[hosts[p$assign]] * c(1.15, 0.9, 1.05)[(r %% 3) + 1]
    state <- calibrate(e, hosts, sp, p, act, state, r)
    meas <- act
    meas_host <- hosts[p$assign]
  }
  f <- stats::setNames(state$factor, state$name)
  f[["cloud"]] / f[["m1"]]
}

pk_by_legs <- function(e, hosts, sp, p, act, state, r) {
  legs <- legs_of(hosts, sp$speed, p$load, as.vector(tapply(act, factor(p$assign, 1:4), sum)))
  e$speeds_calibrate(legs, state, paste0("r", r), "d")$state
}

test_that("whole-leg calibration converges on the true speed ratio", {
  e <- pk_env()
  expect_equal(pk_simulate(e, 20, pk_by_legs), 0.7, tolerance = 0.02)
})

test_that("per-group means do not converge (#163's feedback loop)", {
  e <- pk_env()
  # The mutant #163 warns against: a class's speed from its groups' mean
  # minutes against the run's. Its bucket mix is the packing's choice, so the
  # estimate chases its own packing and runs away from 0.7.
  by_means <- function(e, hosts, sp, p, act, state, r) {
    mg <- tapply(act, hosts[p$assign], mean)
    legs <- legs_of(names(mg), sp$speed[match(names(mg), hosts)], mean(act), as.vector(mg))
    e$speeds_calibrate(legs, state, paste0("r", r), "d")$state
  }
  expect_gt(abs(pk_simulate(e, 20, by_means) - 0.7), 0.3)
})

test_that("an update is damped toward the stored factor, not the speed the run was packed at", {
  e <- pk_env()
  # The state says 1 for both; the run was packed with --host-speeds at 0.45 for
  # cloud. Both truly run at the same speed, so each leg took 100 min.
  st <- data.frame(name = c("m1", "cloud"), factor = 1, last_updated = "d", n_runs = 1L,
                   source_run_uid = "u")
  l <- legs_of(c("m1", "cloud", "cloud"), c(1, 0.45, 0.45), c(100, 100 / 0.45, 100 / 0.45), 100)
  out <- e$speeds_calibrate(l, st, run_uid = "u1", date_utc = "d")
  h <- out$history
  expect_equal(h$packed[h$name == "cloud"], 0.45)
  expect_equal(h$old, c(1, 1))
  # The observation is the packed speed over the correction, the same truth for
  # both, so the two learned factors stay equal.
  expect_equal(h$observed[h$name == "cloud"], h$observed[h$name == "m1"])
  expect_equal(out$state$factor[1], out$state$factor[2])
  expect_equal(h$new[h$name == "cloud"], 0.7 * 1 + 0.3 * h$observed[h$name == "cloud"])
  # The clamp is against the stored factor too: twice 1, not twice 0.45.
  l2 <- legs_of(c("m1", "cloud"), c(1, 0.45), c(100, 100), c(1000, 1))
  h2 <- e$speeds_calibrate(l2, st, run_uid = "u2", date_utc = "d")$history
  expect_equal(h2$new[h2$name == "cloud"], 2)
})

test_that("a driver role key is never learned, and still counts toward the run's ratio", {
  e <- pk_env()
  l <- legs_of(c("m4", "worker1", "cloud", "dispatcher"), 1, 100, c(100, 150, 100, 100))
  out <- e$speeds_calibrate(l, run_uid = "u1", date_utc = "d")
  expect_equal(sort(out$state$name), c("cloud", "m4"))
  expect_equal(out$run_ratio, 450 / 400)
  h <- out$history
  expect_match(h$action[h$name == "worker1"], "^not learned: worker1 is a driver role key")
  expect_match(h$action[h$name == "dispatcher"], "^not learned")
  expect_true(is.na(h$new[h$name == "worker1"]))
})

test_that("host_class() drops a domain, so a logged node name meets its alias", {
  e <- pk_env()
  expect_equal(e$host_class(c("m4.local", "cypher-job1.example")), c("m4", "cloud"))
})

test_that("the speed a run was packed at decides routing, never what is learned", {
  e <- pk_env()
  # Truth all equal and the state says so. A run packed cloud at 0.45 by hand,
  # with m1 not in it: nothing may move, or the ratios against m1 break.
  st <- data.frame(name = c("m1", "m4", "cloud"), factor = 1, last_updated = "d", n_runs = 1L,
                   source_run_uid = "u")
  l <- legs_of(c("m4", "cloud", "cloud", "cloud"), c(1, 0.45, 0.45, 0.45),
               c(100, rep(100 / 0.45, 3)), 100)
  out <- e$speeds_calibrate(l, st, run_uid = "u1", date_utc = "d")
  expect_equal(out$state$factor, c(1, 1, 1))
  # One usable name, packed at 1.5: the correction is 1 by construction, and
  # the hand-typed speed must not leak into the state.
  l2 <- legs_of(c("m4", "cloud"), c(1.5, 1), c(100 / 1.5, 100), 100, skip = c(NA, "stall"))
  out2 <- e$speeds_calibrate(l2, st, run_uid = "u2", date_utc = "d")
  expect_equal(out2$state$factor[out2$state$name == "m4"], 1)
})

test_that("plan weights are re-normalized at a given state; unmeasured groups keep theirs", {
  e <- pk_env()
  st <- data.frame(name = c("m1", "cloud"), factor = c(1, 0.5), last_updated = "d", n_runs = 1L,
                   source_run_uid = "u")
  expect_equal(e$plan_weights_at(c(25, 10, 7), c(50, 10, NA), c("cloud", "m1", NA), st),
               c(25, 10, 7))
  expect_equal(e$plan_weights_at(c(25, 10, 7), c(50, 10, NA), c("cloud", "m1", NA)),
               c(50, 10, 7))
})
