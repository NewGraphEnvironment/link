# Scheduler templates for `data-raw/snapshot_bcfp.sh`

Per-host install for the weekly bcfp snapshot. Each host (M4, M1, cypher) runs the script Wed 5:00 AM PDT (Wed 12:00 UTC) so users wake Wednesday morning to a fully-fresh local fwapg.

## Cadence chain

```
Tue ~1:25 PM PDT (20:25 UTC)  → smnorris/bcfishpass:ng-prod fires
Tue ~9:15 PM – ~11:31 PM PDT  → ng-prod finishes (worst observed n=2)
Wed 3 AM PDT (10:00 UTC)      → db_newgraph: dump-bcfishpass-csvs (s3 bundle)
Wed 4 AM PDT (11:00 UTC)      → link: sync-bcfishpass-csvs (override CSV PRs)
Wed 5 AM PDT (12:00 UTC)      → THIS: snapshot_bcfp.sh on each host
```

## Per-host install

### macOS (M4, M1) — launchd

1. **Install link package + dependencies** (R + GDAL + bcdata, see `data-raw/snapshot_bcfp.sh` prereqs).

2. **Create the env file** at `~/.config/snapshot-bcfp.env`:

   ```bash
   mkdir -p ~/.config
   cat > ~/.config/snapshot-bcfp.env <<'EOF'
   # Choose one of:
   #   DATABASE_URL=postgresql://user:pass@localhost:5432/dbname
   # OR the PG* variables:
   PGUSER=postgres
   PGPASSWORD=...
   PGHOST=localhost
   PGPORT=5432
   PGDATABASE=fwapg
   EOF
   chmod 600 ~/.config/snapshot-bcfp.env
   ```

3. **Create the log directory:**

   ```bash
   mkdir -p ~/.local/state/snapshot-bcfp
   ```

4. **Customize and install the plist:**

   ```bash
   sed -e "s|{{REPO_PATH}}|$HOME/Projects/repo/link|g" \
       -e "s|{{HOME}}|$HOME|g" \
       data-raw/scheduler/com.newgraph.snapshot-bcfp.plist \
     > ~/Library/LaunchAgents/com.newgraph.snapshot-bcfp.plist
   launchctl load ~/Library/LaunchAgents/com.newgraph.snapshot-bcfp.plist
   ```

5. **Smoke-test** by triggering once manually:

   ```bash
   launchctl start com.newgraph.snapshot-bcfp
   tail -f ~/.local/state/snapshot-bcfp/launchd.log
   ```

   Verify `data-raw/logs/bcfp_baselines.csv` gained a row for this host.

### Linux (cypher) — cron

1. **Install link package + dependencies** (same as macOS).

2. **Create env file + log directory** (same commands as macOS).

3. **Add the cron line:**

   ```bash
   crontab -e
   # Paste the line from data-raw/scheduler/snapshot-bcfp.cron, with
   # {{REPO_PATH}} and {{HOME}} replaced with absolute paths.
   ```

4. **Smoke-test** by running the script directly:

   ```bash
   bash data-raw/snapshot_bcfp.sh
   tail -f ~/.local/state/snapshot-bcfp/cron.log
   ```

## Skip-if-already-stamped behaviour

The script calls `link::lnk_baseline_skip_p()` early. If this host's most-recent ledger row in `data-raw/logs/bcfp_baselines.csv` already stamps the upstream `bcfp_model_version` from `s3://fresh-bc/bcfishpass/log.json`, the script logs "skipping" and exits 0 without re-snapshotting. Avoids redundant data loads when launchd / cron fires twice per cycle (e.g. wake-from-sleep catch-up runs on macOS).

## Uninstall

### macOS

```bash
launchctl unload ~/Library/LaunchAgents/com.newgraph.snapshot-bcfp.plist
rm ~/Library/LaunchAgents/com.newgraph.snapshot-bcfp.plist
```

### Linux

```bash
crontab -e
# Delete the snapshot-bcfp line.
```

## Verification after a Wed cycle

```bash
# Each enrolled host should have a row stamped with this Tue's bcfp_model_version.
tail -5 data-raw/logs/bcfp_baselines.csv

# Per-host log content
ls -la ~/.local/state/snapshot-bcfp/
```

If a host missed a cycle (was asleep at fire time on macOS, or cron had a transient failure), running `bash data-raw/snapshot_bcfp.sh` manually picks up where the schedule would have. The skip guard means re-running after a successful cycle is harmless — second invocation exits 0 cleanly.
