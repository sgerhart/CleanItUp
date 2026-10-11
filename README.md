# CleanItUp

A native macOS app (Swift and SwiftUI) that shows what's using your storage, how your disks are doing, and helps you clean up safely.

## What it does

| Section | What you get |
| --- | --- |
| **Storage** | Free and used space on every disk, then a breakdown of any folder: biggest subfolders as a chart, the 50 largest files, drill-down, and Move to Trash. |
| **Disk Health** | SMART status for each physical disk, plus NVMe wear (life used, spare blocks, temperature, lifetime writes, media errors) when macOS or `smartctl` reports it. Live read/write throughput and a table of which apps and agents are reading and writing the most. |
| **Cleanup** | Finds app caches, logs, Xcode leftovers, package manager caches (npm, pip, Hugging Face, Cargo, Go and more), `node_modules`, Python virtual environments, Rust and Swift build folders, and Downloads you haven't touched in 90 days. You pick; it moves them to the Trash. |
| **iCloud Drive** | How much is in iCloud Drive versus actually on this Mac, what's stored only in the cloud, and per-folder "Free Up Space" (keep in iCloud, drop the local copy) or "Download Now". |

### Safety rules

- Nothing is ever deleted permanently. Everything goes to the Trash, where you can put it back. Emptying the Trash is up to you.
- Every removal goes through `TrashSafety`, which refuses anything outside your home folder, top-level folders like `~/Documents` or `~/Library`, settings files in your home folder, and anything in `~/.ssh`, your keychains or iCloud Drive.
- Project dependency folders are only offered when the matching project file sits next to them (`package.json` for `node_modules`, `pyvenv.cfg` for virtual environments, `Cargo.toml` for `target`), and they start unchecked.
- "Old downloads" start unchecked and are marked "Review first".

## Install a build

1. Open the latest successful run under the repo's **Actions** tab, and download the **CleanItUp** artifact.
2. Your browser may unzip it for you; otherwise double-click the download. Open `CleanItUp.dmg` and drag CleanItUp to Applications.
3. The app isn't notarized yet, so macOS blocks the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. (Or run `xattr -dr com.apple.quarantine /Applications/CleanItUp.app`.)
4. For a complete picture, add CleanItUp under **System Settings → Privacy & Security → Full Disk Access**. Without it, some folders under `~/Library` are skipped and the app tells you how many.

Optional: `brew install smartmontools` adds detailed health data for drives macOS doesn't report on, like many external SSDs.

## Develop

Requires macOS 14+ and Xcode 15+ (Swift 5.9).

```sh
swift build          # debug build
swift test           # core logic tests
swift run CleanItUp  # launch without bundling
./scripts/bundle.sh  # universal CleanItUp.app + .dmg in build/
```

Or open `Package.swift` in Xcode.

### Layout

- `Sources/CleanItUpCore`: scanning, disk health, I/O monitoring, cleanup rules and trash safety. No UI, fully testable.
- `Sources/CleanItUp`: the SwiftUI app.
- `Tests/CleanItUpCoreTests`: unit tests for the core.
- `.github/workflows/build.yml`: builds, tests and bundles on a macOS runner for every push to main and every pull request.

## Roadmap

1. **Organize across local and iCloud**: rules like "move files in Downloads older than 30 days to iCloud Drive/Archive", previewed before running, and moving folders between local disk, iCloud Drive and external drives.
2. **Duplicates**: find identical files by size then hash, and keep one.
3. **Treemap view** of a folder, alongside the bar chart.
4. **Background monitoring**: a menu bar item that warns when free space or drive health drops, or when a process writes unusually much.
5. **Signing and notarization** so the app opens without the Gatekeeper step.
