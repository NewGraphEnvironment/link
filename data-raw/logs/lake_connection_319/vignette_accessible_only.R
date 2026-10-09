# Evaluate only the accessible-km block of data-raw/wsg_vignette_data.R (#319),
# leaving the gpkg and mapping-code parity artifacts untouched.
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
ex <- parse("data-raw/wsg_vignette_data.R", keep.source = TRUE)
txt <- vapply(ex, function(e) paste(deparse(e, width.cutoff = 500L), collapse = " "), "")
setup <- which(grepl("^(aoi|stub|out_dir|conn) <- ", txt))
i0 <- which(grepl("^metrics_km <- ", txt)); i1 <- which(grepl("accessible km \\(link", txt))
stopifnot(length(i0) == 1L, length(i1) == 1L, i1 > i0, length(setup) == 4L)
env <- globalenv()
for (k in c(setup, i0:i1)) eval(ex[[k]], env)
DBI::dbDisconnect(conn)
