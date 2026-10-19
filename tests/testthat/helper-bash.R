# Shared by the tests that run data-raw/ bash libs (test-study_area_hosts.R,
# test-study_area_finish.R).

# The libs need bash >= 4 (assoc arrays); macOS /bin/bash is 3.2.
hosts_bash <- function() {
  cands <- unique(c(
    "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
    unname(Sys.which("bash"))
  ))
  for (b in cands[nzchar(cands) & file.exists(cands)]) {
    v <- suppressWarnings(system2(b, c("-c", shQuote("echo ${BASH_VERSINFO[0]}")),
      stdout = TRUE, stderr = FALSE
    ))
    n <- suppressWarnings(as.integer(v))
    if (length(n) == 1L && !is.na(n) && n >= 4L) {
      return(b)
    }
  }
  ""
}
