Batch-add a prefix/suffix to files right inside Finder — select files, press **⌥F2**, type, done.

### Install

**One line (Terminal)** — no Gatekeeper prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/surrealier/Mac_Renamer/main/install.sh | bash
```

**Or download** `Mac_Renamer.zip` below → unzip → drag **Mac_Renamer.app** to **Applications** → open it.
The app is ad-hoc signed (not notarized), so the first launch shows a warning: open
**System Settings › Privacy & Security** and click **Open Anyway** (or run
`xattr -dr com.apple.quarantine /Applications/Mac_Renamer.app`).

Requires macOS 13 Ventura or later · Universal (Apple Silicon + Intel) · `Mac_Renamer.zip.sha256` has the checksum.

### Use

1. Select files or folders in Finder (or on the Desktop)
2. Press **⌥F2** (Fn+⌥+F2 on a MacBook keyboard) — or right-click › **Services › Rename with Mac_Renamer**
3. Type a prefix / suffix, check the preview, click **Rename**

Uninstall any time: `curl -fsSL https://raw.githubusercontent.com/surrealier/Mac_Renamer/main/uninstall.sh | bash`

Full details in the [README](https://github.com/surrealier/Mac_Renamer/blob/__TAG__/README.md).
