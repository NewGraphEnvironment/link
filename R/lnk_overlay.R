# Overlays: link's cell changes on a copied upstream table (#429).
#
# A file copied from bcfishpass stays byte for byte as published, so the
# weekly sync can check it. Where link departs from it, the departure is a
# row in a link-owned overlay file beside the copy, declared on the copy's
# `files:` entry as `overlay:`. Each row names one cell and says why:
#
#   <key column>,column,value,reason,issue
#   ADMS,ko,t,kokanee recorded in Adams Lake,#123
#
# The first column is named for the base table's key and holds its values;
# `column` may name a column the base lacks, which is then added (empty
# elsewhere, as a CSV gives an empty field) before the first non-key column
# that sorts after it. The loader applies the overlay
# before typing, so every reader sees one table.

# Apply an overlay file to a base table read with every column character.
# Returns the base with the overlay's cells set. Refuses an overlay that is
# not one change per cell, with a reason, on a key the base holds.
.lnk_overlay_apply <- function(base, overlay_path, key = "table") {
  ovl <- utils::read.csv(overlay_path, stringsAsFactors = FALSE,
                         colClasses = "character",
                         na.strings = character(0))
  cols <- names(ovl)
  want <- c("column", "value", "reason", "issue")
  if (length(cols) != 5L || !identical(cols[-1], want)) {
    stop("overlay for `", key, "` (", overlay_path, ") must have the ",
         "columns <key>, column, value, reason, issue; it has ",
         paste(cols, collapse = ", "), call. = FALSE)
  }
  key_col <- cols[[1]]
  if (!key_col %in% names(base)) {
    stop("overlay for `", key, "`: its key column '", key_col, "' is not ",
         "a column of the table it changes", call. = FALSE)
  }
  rep_base <- unique(base[[key_col]][duplicated(base[[key_col]])])
  if (length(rep_base) > 0L) {
    stop("overlay for `", key, "`: the table's key '", key_col,
         "' values repeat (", paste(rep_base, collapse = ", "),
         "), so a cell cannot be named", call. = FALSE)
  }
  if (nrow(ovl) == 0L) return(base)

  if (any(ovl$column == key_col)) {
    stop("overlay for `", key, "`: a row targets the key column '",
         key_col, "' itself", call. = FALSE)
  }
  blank <- !nzchar(trimws(ovl$reason))
  if (any(blank)) {
    stop("overlay for `", key, "`: every row needs a reason; none on ",
         paste(ovl[[key_col]][blank], ovl$column[blank], sep = "/",
               collapse = ", "), call. = FALSE)
  }
  cell <- paste(ovl[[key_col]], ovl$column, sep = "/")
  rep_cell <- unique(cell[duplicated(cell)])
  if (length(rep_cell) > 0L) {
    stop("overlay for `", key, "`: more than one row for ",
         paste(rep_cell, collapse = ", "), call. = FALSE)
  }
  unknown <- setdiff(ovl[[key_col]], base[[key_col]])
  if (length(unknown) > 0L) {
    stop("overlay for `", key, "`: ", key_col, " not in the table: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  # An added column goes before the first non-key column that sorts after
  # it, so a column the copy lacks lands where a sorted table would hold it
  # (the presence table's ko before pk): column order reaches readers.
  for (col in sort(setdiff(unique(ovl$column), names(base)), method = "radix")) {
    nm <- names(base)
    after <- which(nm != key_col &
                     vapply(nm, function(x) {
                       sort(c(x, col), method = "radix")[[1]] == col
                     }, logical(1)))
    base[[col]] <- rep("", nrow(base))
    if (length(after) > 0L) {
      at <- after[[1]]
      base <- base[, append(nm, col, after = at - 1L), drop = FALSE]
    }
  }
  rows <- match(ovl[[key_col]], base[[key_col]])
  for (i in seq_len(nrow(ovl))) {
    base[[ovl$column[[i]]]][[rows[[i]]]] <- ovl$value[[i]]
  }
  base
}
