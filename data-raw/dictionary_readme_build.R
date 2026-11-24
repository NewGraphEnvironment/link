# data-raw/dictionary_readme_build.R
#
# Render inst/extdata/configs/README.md from the dictionary_*.csv files beside
# it (link#75). Run after editing any dictionary; test-dictionaries.R fails
# while the README is stale.
#
# Usage:
#   Rscript data-raw/dictionary_readme_build.R

pkgload::load_all(quiet = TRUE)
dir <- file.path("inst", "extdata", "configs")
# UTF-8 bytes whatever the locale: writeLines() would otherwise convert to
# the native encoding and write <U+2014> for an em dash under LANG=C.
writeLines(enc2utf8(.lnk_dictionary_readme(dir)), file.path(dir, "README.md"),
           sep = "", useBytes = TRUE)
message("wrote ", file.path(dir, "README.md"))
