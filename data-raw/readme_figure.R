# README figure: Arctic grayling habitat and access in the Parsnip River
# watershed group, from link's `default` config.
#
# Reads only the cached vignette artifact (inst/vignette-data/pars.gpkg, made
# by data-raw/wsg_vignette_data.R), so it needs no database. Colours come from
# the gq style registry, the same symbology the vignette uses.
#
#   Rscript data-raw/readme_figure.R
#
# Writes man/figures/readme-pars.png.

sf::sf_use_s2(FALSE)

gpkg <- "inst/vignette-data/pars.gpkg"
out  <- "man/figures/readme-pars.png"

aoi         <- sf::st_read(gpkg, layer = "aoi", quiet = TRUE)
streams     <- sf::st_read(gpkg, layer = "streams", quiet = TRUE)
waterbodies <- sf::st_read(gpkg, layer = "waterbodies", quiet = TRUE)

reg <- gq::gq_reg_main()
cls <- gq::gq_tmap_classes(reg$layers$streams_salmon)

# The intermittent flag is not distinguished here: one colour per habitat and
# downstream-barrier pair keeps the legend to what the caption explains.
tok <- sub(";INTERMITTENT", "", streams$mapping_code_gr, fixed = TRUE)
classified <- !is.na(tok) & nzchar(tok)
gr <- streams[classified, ]
gr$tok <- tok[classified]
gr$col <- unname(cls$values[gr$tok])
gr$col[is.na(gr$col)] <- "#999999"
gr$w <- unname(cls$widths[gr$tok])
gr$w[is.na(gr$w)] <- min(cls$widths, na.rm = TRUE)

# Draw order: access first, rearing over it, spawning on top.
gr <- gr[order(match(sub(";.*", "", gr$tok), c("ACCESS", "REAR", "SPAWN"))), ]

.tok1 <- c(SPAWN = "Spawning", REAR = "Rearing", ACCESS = "Accessible")
.tok2 <- c(NONE = "no known barrier below", MODELLED = "potential barrier below",
           ASSESSED = "known barrier below", DAM = "dam below",
           REMEDIATED = "remediated barrier below")
label_for <- function(tokens) {
  vapply(strsplit(tokens, ";", fixed = TRUE), function(p) {
    parts <- c(.tok1[p[1]], if (length(p) >= 2) .tok2[p[2]])
    paste(parts[!is.na(parts)], collapse = ", ")
  }, character(1))
}

# Legend in registry order, present tokens only, intermittent duplicates dropped.
keys <- unique(sub(";INTERMITTENT", "", names(cls$values), fixed = TRUE))
keys <- keys[keys %in% gr$tok]

bb <- sf::st_bbox(aoi)
# Widen the plot window to the right so the legend sits beside the basin, and
# size the canvas to that window's aspect so there are no blank bands.
xlim <- c(bb[["xmin"]], bb[["xmax"]] + (bb[["xmax"]] - bb[["xmin"]]) * 0.62)
asp  <- (bb[["ymax"]] - bb[["ymin"]]) / diff(xlim)
png(out, width = 8, height = 8 * asp + 0.1, units = "in", res = 120)
op <- par(mar = c(0.05, 0.05, 0.05, 0.05))
plot(sf::st_geometry(aoi), col = "#f4f1ea", border = NA, xlim = xlim,
     ylim = c(bb[["ymin"]], bb[["ymax"]]))
plot(sf::st_geometry(streams[!classified, ]), col = "#cfcfcf", lwd = 0.3,
     add = TRUE)
plot(sf::st_geometry(waterbodies), col = "#a3cdb9", border = "#2171B5",
     lwd = 0.3, add = TRUE)
plot(sf::st_geometry(gr), col = gr$col, lwd = gr$w * 0.7, add = TRUE)
plot(sf::st_geometry(aoi), col = NA, border = "black", lwd = 1.2, add = TRUE)

legend("topright", inset = c(0.01, 0.02), title = "Arctic grayling",
       title.adj = 0,
       legend = c(label_for(keys), "Above a natural barrier to grayling",
                  "Waterbodies"),
       col = c(unname(cls$values[keys]), "#cfcfcf", "#2171B5"),
       lwd = c(pmax(unname(cls$widths[keys]) * 1.6, 1), 1, NA),
       pch = c(rep(NA, length(keys) + 1), 22), pt.bg = "#a3cdb9", pt.cex = 1.6,
       seg.len = 2.5, cex = 0.82, bty = "n")

# 20 km scale bar, bottom right of the basin.
x0 <- bb[["xmax"]] + 4000
y0 <- bb[["ymin"]] + 4000
segments(x0, y0, x0 + 20000, y0, lwd = 3, lend = 1)
text(x0 + 10000, y0, "20 km", pos = 3, cex = 0.82)
par(op)
dev.off()

message("wrote ", out)
