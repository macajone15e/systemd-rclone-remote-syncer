# Cloud Remote Synchronizer for Linux (rclone + systemd)

This project provides an automatic, two-way synchronization solution between multiple local folders on Linux and Microsoft Cloud Remote. It relies on `rclone bisync`, Bash scripts with exclusive file locking (`flock`), and a user-level `systemd` timer.

---

## 1. How It Works

The system allows you to synchronize multiple folders independently without modifying the synchronization scripts.

Synchronization relies on `rclone bisync` with the `--conflict-resolve newer` option. Conflicts are resolved automatically by keeping the newest file. An automatic lock prevents multiple instances of the script from running at the same time.

The script also includes the following built-in features:

* **Offline check**: skips the sync silently if no network connectivity is detected (ping to `1.1.1.1`).
* **Log rotation**: automatically truncates the log file to the last 1000 lines when it exceeds 5 MB.
* **Desktop notifications**: sends a `notify-send` alert on sync failure.
* **Uninstaller**: run `uninstall.sh` to cleanly remove all installed files, systemd units, and shell aliases.

---

## 2. Installed File Structure

The installation creates the following files in your home directory:

* **Configuration file**
  * `~/.config/rclone-remote-syncer/config.env`: Defines the rclone remote name, the list of folders to synchronize (`SYNC_N`), the sync mode, and the log file location.

* **Execution script**
  * `~/.local/bin/rclone-remote-syncer.sh`: Unified script executed periodically by the timer. Accepts `--resync` as an optional argument to establish the initial baseline.

* **systemd units (user level)**
  * `~/.config/systemd/user/rclone-remote-syncer.service`: A `oneshot` service unit that launches `rclone-remote-syncer.sh`.
  * `~/.config/systemd/user/rclone-remote-syncer.timer`: Timer that schedules the service execution 1 minute after boot, then every 5 minutes.

---

## 3. Multi-folder Configuration (`config.env`)

All folder pairs are configured in `~/.config/rclone-remote-syncer/config.env`.

Each pair uses the following syntax:

```bash
SYNC_N="absolute_local_path:remote_name:relative_remote_path"
```

### Example Configuration

```bash
# Configured rclone remote
RCLONE_REMOTE="myremote"

# List of folders to sync (SYNC_1, SYNC_2, SYNC_3, etc.)
SYNC_1="/home/mac/Documents:myremote:Documents"
SYNC_2="/home/mac/Pictures:myremote:Pictures"

# Sync mode (bisync for bidirectional)
SYNC_MODE="bisync"

# Logging and exclusion options
RCLONE_LOG_LEVEL="INFO"
RCLONE_LOG_FILE="/home/mac/.config/rclone-remote-syncer/sync.log"
RCLONE_EXTRA_FLAGS="--exclude='.git/**' --exclude='node_modules/**'"
```

The `rclone-remote-syncer.sh` script automatically detects variables starting with `SYNC_` followed by a number and processes each folder sequentially.

---

## 4. Why and When to Use `--resync`

`rclone bisync` keeps a baseline history of the state of local and remote files in `~/.config/rclone/bisync/`.

The first time you synchronize a folder, or when you add a new `SYNC_N` pair to the configuration, `rclone` does not have this history yet. You must run `rclone-remote-syncer.sh --resync` once in this situation.

### What `--resync` does

* Passes the `--resync` option to `rclone bisync`.
* Compares all local and remote files to establish the initial baseline.
* Creates the state files required for future incremental synchronizations to work.

**Important:** Use `--resync` only once during initial setup or after adding a new folder. Regular automated synchronizations run without it.

---

## 5. Step-by-Step Setup and Installation Guide

Follow these steps to complete the installation and enable automatic synchronization.

### Step 1: Configure the Rclone Remote

If your Cloud Remote access is not configured in rclone yet, run the interactive setup command:

```bash
rclone config
```

1. Press `n` to create a new remote.
2. Name the remote (for example, `remote`).
3. Choose `Microsoft Cloud Remote` as the storage type.
4. Leave the default client credentials (press Enter).
5. Complete authentication in your web browser.
6. Test the connection with the following command:

```bash
rclone lsd remote:
```

### Step 2: Edit the Configuration

Open and modify the configuration file:

```bash
nano ~/.config/rclone-remote-syncer/config.env
```

Make sure the variables (`SYNC_1`, `SYNC_2`, etc.) match your actual local and remote folders, and that the remote name matches the one configured in Step 1.

### Step 3: Run the Initial Synchronization (Resync)

Run the resynchronization manually to create the initial baseline:

```bash
sync-remote --resync
```

Or, if the alias is not yet active in your current shell:

```bash
~/.local/bin/rclone-remote-syncer.sh --resync
```

Check the terminal to confirm the execution finishes with the status `Result: ALL PAIRS SUCCEEDED`.

### Step 4: Enable the Systemd Timer

Reload the user systemd configuration and enable the timer:

```bash
systemctl --user daemon-reload
systemctl --user enable --now rclone-remote-syncer.timer
```

### Step 5: Check Status and View Logs

To verify that the timer is active and see the next scheduled execution time:

```bash
systemctl --user status rclone-remote-syncer.timer
```

To view the systemd service execution history:

```bash
journalctl --user -u rclone-remote-syncer.service -f
```

To view the detailed log file generated by the scripts:

```bash
tail -f ~/.config/rclone-remote-syncer/sync.log
```

---

## 6. Uninstalling

To remove all installed files, systemd units, and shell aliases, run:

```bash
bash uninstall.sh
```

---

## 7. Troubleshooting

### Synchronization stuck at 0 B/s (Throttling)

If your synchronization seems completely frozen (e.g., `0 B/s` for several minutes) despite having a working connection, it is likely due to **API throttling** from Cloud Remote. This usually happens when attempting to sync folders containing thousands of tiny files, such as Python virtual environments or large cache directories.

To fix this:
1. Cancel the current sync with `Ctrl+C`.
2. Clear the residual lock file if it exists: `rm -f ~/.cache/rclone/bisync/*.lck`
3. Edit your configuration file (`~/.config/rclone-remote-syncer/config.env`) and add exclusions for those directories in `RCLONE_EXTRA_FLAGS`. For example, to exclude Python virtual environments:

```bash
RCLONE_EXTRA_FLAGS="--exclude='.git/**' --exclude='node_modules/**' --exclude='.venv/**' --exclude='venv/**' --exclude='__pycache__/**'"
```

4. Restart the initial sync with the `--resync` flag: `sync-remote --resync`

### "prior lock file found" Error

If rclone crashes or is interrupted, a lock file might be left behind. You will see an error like:
`Failed to bisync: prior lock file found: /home/mac/.cache/rclone/bisync/...lck`

Simply delete the `.lck` file mentioned in the error message and run the sync again.
