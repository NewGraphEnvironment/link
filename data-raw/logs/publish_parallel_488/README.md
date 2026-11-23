# PUBLISH on a pool of aws processes (link#488)

Measured on m1, 2026-11-23 UTC, aws-cli 2.34.34, the home connection m1 sits
on. One built root, published three times to scratch prefixes of fresh-bc
(private, versioned like `habitat/`), every version removed after (2,800
versions, `list-object-versions` empty).

**The root.** No built root was on m1, so the published tree was synced down
(`aws s3 sync s3://fresh-bc/habitat/fwa/v1/`, 2026-11-23T01:45Z): 108 parts
(724 MB), 482 per-group parts (212 MB), 753 provenance and bundle files (10 MB),
the dependency map and the manifest. Two copy-on-write copies of it were
published, so each run started from the same tree; a second publish to one
prefix would skip what the first put there.

## One call

| command | seconds, five runs |
|---|---|
| `aws --version` (start-up alone) | 0.32 to 0.34 |
| `aws s3api head-object` on the published manifest | 0.55 to 0.63 |

#488's 2.4 s per call was a cloud host; here a call is about 0.55 s, 60 % of it
start-up. So the ratio below is m1's, and this does not reproduce #488's 53.5
min.

## Three publishes

| run | code | target | wall time | log |
|---|---|---|---|---|
| serial | `main` at `be06e2b` | `scratch/link499/serial/` | 36.5 min | `serial.log` |
| parallel, 8 at once | this branch | `scratch/link499/parallel/` | 4.1 min | `parallel.log` |
| parallel, the same tree again | this branch | `scratch/link499/parallel/` | 1.9 min | `parallel_republish.log` |

Where the serial run's time went (from its stamps): a `head-object` and a put
per file, 16.0 min; 108 parts, 3.4 min; a `head-object` and a put per per-group
part, 11.2 min; a `head-object` per part for its version, 5.8 min; the manifest,
the stale listing and the read-back, 5 s. The parallel run: one listing, 3.4 s;
every put on the pool (753 files, 108 parts, 482 per-group parts, the dependency
map), 231.3 s; versions from the replies, 0.3 s; the rest, 8 s. On m1 the pool
makes a full publish **8.9 times faster**. The republish of an unchanged tree
skipped all 753 files and 482 per-group parts (one listing), re-put the 108 parts
and the dependency map, and named the per-group parts' versions from one
`list-object-versions` of `barriers/` and `barrier_overrides/`.

## The two prefixes hold the same thing

1,344 keys under each, with identical ETags and sizes (the manifest aside). The
manifests are equal once `version_id` is removed, every part and per-group part
carries one, and each of the parallel manifest's version ids is that key's
latest version in the bucket.

## Not measured

A publish from a cloud host, where a call costs 2.4 s and the pool should save
more; widths other than 8; a publish that deletes stale keys (none here).
