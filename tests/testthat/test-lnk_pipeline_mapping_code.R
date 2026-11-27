# lnk_pipeline_mapping_code(): the pure token build (link#191).

# One row per case. Barrier flags are per species (bt resident, ch anadromous);
# the source flags drive token 2.
mc_access <- function() {
  data.frame(
    id_segment = 1:8,
    has_barriers_bt_dnstr = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, NA, FALSE),
    has_barriers_ch_dnstr = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE),
    has_barriers_anthropogenic_dnstr = c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
    has_barriers_pscis_dnstr        = c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE),
    has_barriers_dams_dnstr         = c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
    dam_dnstr_ind                   = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    remediated_dnstr_ind            = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))
}
mc_habitat <- function() {
  data.frame(id_segment = 1:8,
             spawning_bt = c(0, 1, 0, 0, 0, 0, 0, 0),
             rearing_bt  = c(0, 0, 1, 0, 0, 0, 0, 0),
             spawning_ch = c(0, 0, 0, 0, 0, 0, 0, 0),
             rearing_ch  = c(0, 0, 0, 0, 0, 0, 0, 0))
}
mc_fc <- function() {
  data.frame(id_segment = 1:8,
             feature_code = c(rep("GA24850000", 7), "GA24850150"))
}
mc_build <- function(...) {
  lnk_pipeline_mapping_code(mc_access(), mc_habitat(), mc_fc(),
                            species_resident = "bt",
                            species_anadromous = "ch",
                            species_spawn_only = character(0), ...)
}

test_that("token 1 is ACCESS, SPAWN or REAR, and a blocked segment reads empty", {
  out <- mc_build()
  expect_identical(
    out$mapping_code_bt,
    c("ACCESS;NONE", "SPAWN;MODELLED", "REAR;ASSESSED", "",
      "ACCESS;ASSESSED", "ACCESS;REMEDIATED", "", "ACCESS;NONE;INTERMITTENT"))
})

test_that("the resident and anadromous chains differ on a dam", {
  # Row 5 has a dam downstream (has_barriers_dams_dnstr) but dam_dnstr_ind is
  # FALSE: the next barrier down is not the dam. Resident reads the sequence
  # (ASSESSED); anadromous reads any dam (DAM).
  out <- mc_build()
  expect_identical(out$mapping_code_bt[5], "ACCESS;ASSESSED")
  expect_identical(out$mapping_code_ch[5], "ACCESS;DAM")
  # Anadromous: PSCIS wins over a modelled crossing.
  expect_identical(out$mapping_code_ch[3], "ACCESS;ASSESSED")
})

test_that("a spawn-only species never reads REAR", {
  h <- mc_habitat()
  h$rearing_ch <- c(0, 0, 1, 0, 0, 0, 0, 0)
  out <- lnk_pipeline_mapping_code(mc_access(), h, mc_fc(),
                                   species_resident = character(0),
                                   species_anadromous = "ch",
                                   species_spawn_only = "ch")
  expect_identical(out$mapping_code_ch[3], "ACCESS;ASSESSED")
  out2 <- lnk_pipeline_mapping_code(mc_access(), h, mc_fc(),
                                    species_resident = character(0),
                                    species_anadromous = "ch",
                                    species_spawn_only = character(0))
  expect_identical(out2$mapping_code_ch[3], "REAR;ASSESSED")
})

test_that("an absent species reads empty on every segment", {
  pres <- lnk_presence(
    data.frame(watershed_group_code = "AAAA", bt = "t", ch = ""), "AAAA",
    groups = list())
  out <- mc_build(presence = pres)
  expect_true(all(out$mapping_code_ch == ""))
  expect_identical(out$mapping_code_bt, mc_build()$mapping_code_bt)
})

test_that("a named logical presence works as an lnk_presence does (#351)", {
  pres <- lnk_presence(
    data.frame(watershed_group_code = "AAAA", bt = "t", ch = ""), "AAAA",
    groups = list())
  expect_identical(mc_build(presence = c(bt = TRUE, ch = FALSE)),
                   mc_build(presence = pres))
  # A species the vector does not name is absent.
  expect_true(all(mc_build(presence = c(bt = TRUE))$mapping_code_ch == ""))
  expect_error(mc_build(presence = "bt"), "named logical")
})

test_that("a missing habitat column reads 0, a missing habitat row stays NA (#153)", {
  h <- mc_habitat()[, c("id_segment", "spawning_bt", "rearing_bt")]
  out <- lnk_pipeline_mapping_code(mc_access(), h, mc_fc(),
                                   species_resident = "bt",
                                   species_anadromous = "ch",
                                   species_spawn_only = character(0))
  # ch has no columns: accessible segments read ACCESS, as bcfishpass does.
  expect_identical(out$mapping_code_ch[1], "ACCESS;NONE")
  h0 <- mc_habitat()
  h0$spawning_ch <- 0
  h0$rearing_ch <- 0
  expect_identical(out$mapping_code_ch,
                   lnk_pipeline_mapping_code(mc_access(), h0, mc_fc(),
                                             species_resident = "bt",
                                             species_anadromous = "ch",
                                             species_spawn_only = character(0)
                                             )$mapping_code_ch)
  # Segment 1 with no habitat row: token 1 is NA, so only token 2 is left.
  out_norow <- lnk_pipeline_mapping_code(mc_access(), h[-1, ], mc_fc(),
                                         species_resident = "bt",
                                         species_anadromous = "ch",
                                         species_spawn_only = character(0))
  expect_identical(out_norow$mapping_code_ch[1], "NONE")
})

test_that("the expired argument aliases are gone", {
  expect_error(mc_build(resident_species = "bt"), "unused argument")
})

test_that("`to` without a connection refuses", {
  expect_error(mc_build(to = "s.t"), "requires a DBI connection")
})
