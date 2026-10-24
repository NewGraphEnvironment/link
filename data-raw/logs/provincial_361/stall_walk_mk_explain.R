a <- commandArgs(TRUE)  # table on_path side outfile [ANALYZE]
on_path <- as.numeric(a[2]); side <- as.numeric(a[3])
sql <- fresh:::.frs_near_river_walk_sql(a[1], "pg_temp.frs_near_river_walk", 15, 1000,
                                        on_path + side, entry_max = side, col = "channel_width")
opt <- if (length(a) >= 5 && a[5] == "ANALYZE") "EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE OFF)" else "EXPLAIN (COSTS, VERBOSE OFF)"
sql <- sub("CREATE TEMP TABLE pg_temp.frs_near_river_walk AS", opt, sql, fixed = TRUE)
writeLines(sql, a[4])
