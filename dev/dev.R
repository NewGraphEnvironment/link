# dev/dev.R — reproducible setup script for link package
# Run interactively, not sourced. Documents every scaffold step.

# Package scaffold (already done)
# usethis::create_package(".")

# License
usethis::use_mit_license("New Graph Environment Ltd.")

# Testing
usethis::use_testthat(edition = 3)

# Documentation
usethis::use_pkgdown()
usethis::use_github_action("pkgdown")

# Directories
usethis::use_directory("dev")
usethis::use_directory("data-raw")

# Development workflow
devtools::document()
devtools::test()
lintr::lint_package()
devtools::check()
