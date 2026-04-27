# Finalize an in-progress run stamp

Sets `end_time` to [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html)
and attaches an optional `result` object (typically the comparison
tibble or rollup). Returns the updated stamp.

## Usage

``` r
lnk_stamp_finish(stamp, result = NULL, end_time = Sys.time())
```

## Arguments

- stamp:

  An `lnk_stamp` object from
  [`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md).

- result:

  Optional. Any R object representing the run's output. Stored verbatim
  in `stamp$result`.

- end_time:

  Default [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html).

## Value

An `lnk_stamp` with `run$end_time` and `result` populated.

## See also

Other stamp:
[`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
