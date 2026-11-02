Sys.unsetenv(c("GITHUB_PAT", "GITHUB_TOKEN"))
if (!requireNamespace("remotes", quietly = TRUE)) stop("no remotes")
remotes::install_github("NewGraphEnvironment/fresh@v0.52.0", auth_token = NULL, upgrade = "never", quiet = TRUE)
d <- packageDescription("fresh"); cat("INSTALLED", d$Version, d$RemoteSha, d$RemoteRef, "\n")
