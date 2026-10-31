screen_params <- function() {
  data.frame(
    species_code = c("CH", "KO", "BT"),
    anadromous = c(TRUE, FALSE, FALSE),
    elevation_max_m = c(1500, 2000, 2500),
    gradient_max = c(0.25, 0.25, 0.30),
    distance_max_m = c(500, 500, 500),
    isolation_km = c(50, 50, 50),
    lone_max = c(1L, 1L, 1L),
    lake_ha_min = c(NA, 100, NA)
  )
}

# One record that passes every screen; tests change one field at a time.
screen_rec <- function(...) {
  x <- data.frame(
    observation_key = "k1", species_code = "CH", match_letter = "A",
    distance_to_stream = 10, code50_record = "1001", code50_stream = "1001",
    utm_zone = 10L, longitude = -122, elevation_m = 500, gradient = 0.02,
    barrier_below = NA_character_, n_above_barrier = NA_integer_,
    rearing_lake_ha = NA_real_, in_hist_zone = NA, nearest_same_km = 2,
    stringsAsFactors = FALSE
  )
  mod <- list(...)
  for (n in names(mod)) x[[n]] <- mod[[n]]
  x
}

verdict <- function(...) {
  .lnk_obs_screen(screen_rec(...), screen_params())[, c("screen", "screen_reasons")]
}

test_that("a clean record passes with no reasons", {
  v <- verdict()
  expect_equal(v$screen, "pass")
  expect_equal(v$screen_reasons, "")
})

test_that("a UTM zone that disagrees with the longitude fails", {
  expect_equal(verdict(utm_zone = 11L)$screen, "fail")
  expect_equal(verdict(utm_zone = 11L)$screen_reasons, "utm_zone")
  # -117 is zone 11
  expect_equal(verdict(utm_zone = 11L, longitude = -117)$screen, "pass")
  expect_equal(verdict(utm_zone = NA_integer_)$screen, "pass")
})

test_that("elevation and gradient ceilings fail at and above them", {
  expect_equal(verdict(elevation_m = 1500)$screen, "pass")
  expect_equal(verdict(elevation_m = 1501)$screen_reasons, "elevation")
  expect_equal(verdict(gradient = 0.249)$screen, "pass")
  expect_equal(verdict(gradient = 0.25)$screen_reasons, "gradient")
  expect_equal(verdict(elevation_m = NA_real_, gradient = NA_real_)$screen, "pass")
})

test_that("a lone anadromous record above an unlifted barrier fails", {
  expect_equal(verdict(barrier_below = "FALLS", n_above_barrier = 1L)$screen_reasons,
               "above_barrier_lone")
  expect_equal(verdict(barrier_below = "FALLS", n_above_barrier = 1L)$screen, "fail")
})

test_that("a historical distribution zone keeps a lone record above a barrier", {
  v <- verdict(barrier_below = "FALLS", n_above_barrier = 1L, in_hist_zone = TRUE)
  expect_equal(v$screen, "pass")
})

test_that("many records above a barrier are doubt, not fail", {
  v <- verdict(barrier_below = "GRADIENT", n_above_barrier = 12L)
  expect_equal(v$screen, "doubt")
  expect_equal(v$screen_reasons, "above_barrier")
})

test_that("residents above a barrier are not screened for it", {
  v <- verdict(species_code = "BT", barrier_below = "FALLS", n_above_barrier = 1L)
  expect_equal(v$screen, "pass")
})

test_that("kokanee above a barrier need a rearing lake", {
  expect_equal(verdict(species_code = "KO", barrier_below = "FALLS",
                       n_above_barrier = 20L, rearing_lake_ha = 50)$screen_reasons,
               "above_barrier_no_lake")
  expect_equal(verdict(species_code = "KO", barrier_below = "FALLS",
                       n_above_barrier = 20L, rearing_lake_ha = NA_real_)$screen,
               "fail")
  expect_equal(verdict(species_code = "KO", barrier_below = "FALLS",
                       n_above_barrier = 20L, rearing_lake_ha = 100)$screen,
               "pass")
  expect_equal(verdict(species_code = "KO", rearing_lake_ha = NA_real_)$screen,
               "pass")
})

test_that("a weak location is doubt: closest-stream match off its code, or far", {
  expect_equal(verdict(match_letter = "B", code50_stream = "1002")$screen_reasons,
               "location")
  expect_equal(verdict(match_letter = "B")$screen, "pass")
  expect_equal(verdict(match_letter = "A", code50_stream = "1002")$screen, "pass")
  expect_equal(verdict(match_letter = "E", code50_stream = NA_character_)$screen,
               "pass")
  expect_equal(verdict(distance_to_stream = 501)$screen_reasons, "location")
})

test_that("an isolated record is doubt", {
  expect_equal(verdict(nearest_same_km = 51)$screen_reasons, "isolated")
  expect_equal(verdict(nearest_same_km = NA_real_)$screen, "pass")
})

test_that("a fail outranks a doubt, and both reasons are listed", {
  v <- verdict(nearest_same_km = 51, elevation_m = 2000)
  expect_equal(v$screen, "fail")
  expect_equal(v$screen_reasons, "elevation;isolated")
})

test_that("a species with no params row is screened on location and zone only", {
  v <- verdict(species_code = "ST", elevation_m = 9000, barrier_below = "FALLS",
               n_above_barrier = 1L)
  expect_equal(v$screen, "pass")
  expect_equal(verdict(species_code = "ST", utm_zone = 9L)$screen, "fail")
})

test_that("bad inputs stop", {
  expect_error(.lnk_obs_screen(screen_rec()[, -1], screen_params()), "lacks columns")
  expect_error(.lnk_obs_screen(screen_rec(), screen_params()[, -2]), "lacks columns")
  expect_error(.lnk_obs_screen(screen_rec(), rbind(screen_params(), screen_params())),
               "more than one row")
})

test_that("zero records return zero rows", {
  out <- .lnk_obs_screen(screen_rec()[0, ], screen_params())
  expect_equal(nrow(out), 0L)
  expect_true(all(c("screen", "screen_reasons") %in% names(out)))
})
