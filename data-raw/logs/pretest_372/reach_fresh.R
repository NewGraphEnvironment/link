sp <- commandArgs(TRUE)[1]
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
ln <- asNamespace("link")
lf <- Filter(function(n) is.function(get(n, ln)), ls(ln, all.names = TRUE))
lc <- lapply(lf, function(n) codetools::findGlobals(get(n, ln), merge = TRUE)); names(lc) <- lf
entries <- c("lnk_db_conn","lnk_config","lnk_load_overrides","lnk_pipeline_species","lnk_wsg_downstream_check","lnk_pipeline_run",".lnk_timeout_statement")
seen <- entries; q <- entries
while (length(q)) { x <- q[1]; q <- q[-1]; nw <- setdiff(intersect(lc[[x]], lf), seen); seen <- c(seen, nw); q <- c(q, nw) }
# fresh calls from on-path link functions: deparse bodies, find fresh::name
txt <- unlist(lapply(seen, function(n) deparse(get(n, ln))))
gfn <- unlist(regmatches(txt, gregexpr("getFromNamespace\\(\"[.A-Za-z0-9_]+\", *\"fresh\"", txt))); gfn <- sub("getFromNamespace\\(\"([^\"]+)\".*", "\\1", gfn)
fcalls <- unique(sub("fresh:::?", "", regmatches(txt, gregexpr("fresh:::?[A-Za-z_.][A-Za-z0-9_.]*", txt)) |> unlist()))
fcalls <- unique(c(fcalls, gfn)); cat("via getFromNamespace:", gfn, "\n")
pkgload::load_all(file.path(sp, "fresh044"), quiet = TRUE, export_all = TRUE)
fn <- asNamespace("fresh"); ff <- Filter(function(n) is.function(get(n, fn)), ls(fn, all.names = TRUE))
fof <- vapply(ff, function(n) { s <- attr(get(n, fn), "srcref"); if (is.null(s)) NA_character_ else basename(attr(s, "srcfile")$filename) }, "")
fc <- lapply(ff, function(n) intersect(codetools::findGlobals(get(n, fn), merge = TRUE), ff)); names(fc) <- ff
seen2 <- intersect(fcalls, ff); q <- seen2
while (length(q)) { x <- q[1]; q <- q[-1]; nw <- setdiff(fc[[x]], seen2); seen2 <- c(seen2, nw); q <- c(q, nw) }
on <- sort(unique(fof[seen2])); cat("FRESH ON:", on, "\nFRESH OFF:", setdiff(sort(list.files(file.path(sp,"fresh044","R"))), on), "\n")
