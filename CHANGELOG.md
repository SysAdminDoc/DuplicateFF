# Changelog

All notable changes to DuplicateFF will be documented in this file.

## [Unreleased]

- Added: Expandable duplicate-group browser with per-group file counts and reclaimable totals.
- Added: Shared ranked auto-selection rule chains and saved wildcard/regex path patterns in GUI and CLI.
- Added: Known-good SHA256 hash exclusions through GUI input and `-KnownHash`/`-KnownHashPath`.
- Added: `-PackagePath` portable ZIP creation containing the script, README, LICENSE, and screenshot.

## [v1.1.0] - 2026-06-20

- Added: Full CLI mode with -Scan, -Reference, -AutoSelect, -Delete, -Json, -DryRun, -Silent, -ReportPath
- Added: Byte-verify stage (stage 6) for hash collision protection
- Added: Drag-and-drop folder support
- Added: Rehearse Delete (dry run preview)
- Added: Cross-volume hardlink guard
- Added: Locked-file detection and skip
- Added: Reference-folder integrity guard (pre-scan and mid-scan)
- Added: Toast notification on scan complete
- Fixed: CLI Get-FileHashValue now uses chunked 256KB reads (prevents OOM on large files)
- Fixed: Hardlink replacement uses safe temp-link-then-swap (prevents data loss on link failure)
- Fixed: -Delete without -AutoSelect now emits an error instead of silently doing nothing
- Fixed: SHA256 instances properly disposed in all hash functions
- Fixed: Version string sync across README, script, and CHANGELOG

## [v1.0.0] - 2026-06-01

- Added: Professional duplicate file finder with 5-stage progressive hashing pipeline
- Added: PowerShell WPF GUI with Catppuccin Mocha dark theme
- Added: Reference folder support (protected from deletion)
- Added: File type filters (Images/Videos/Audio/Documents/All)
- Added: Auto-select rules (Keep Newest/Oldest/Reference/Largest/Shortest Path)
- Added: Delete modes (Recycle Bin, Permanent, Hardlink replacement)
- Added: CSV export with hash values and metadata
- Added: Image preview panel
- Added: Async scanning with cancel support

## Roadmap archive — 2026-08-10 — ROADMAP.md

<details>
<summary>Original roadmap snapshot</summary>

```markdown
# DuplicateFF Roadmap

PowerShell WPF duplicate file finder with a 6-stage progressive hashing pipeline and Catppuccin Mocha UI. Tracks work beyond v1.1.0.

## Planned Features

### UX / UI
- Tree-view of the duplicate groups with expand/collapse per group
- Per-group totals (N files, X GB reclaimable) in the results view
- Saved selection patterns (regex-based "auto-select anything under `C:\Downloads\*`")
- Ranked auto-selection with composable rules chain: "keep newest" + "prefer reference folders" + "prefer shortest path" tie-breakers
- Exclude-by-content list: paste a list of known-good hashes that should never be flagged

### Safety
- Undo stack for the last N delete operations (works because default is Recycle Bin)

### Performance
- `ForEach-Object -Parallel` (PS7 path) with PS5 Runspace fallback for size grouping and hashing stages
- MemoryMappedFile reads for large files so the full-hash stage avoids doubling memory
- Configurable worker count tied to CPU core count with a disk-bound throttle
- Early abort: if size-group stage eliminates 100% of files past a threshold, skip subsequent stages
- Progress + ETA from cumulative byte count (not file count) -- more accurate on uneven trees

### Packaging
- Portable ZIP release asset with screenshots, README, LICENSE

## Competitive Research

- **dupeGuru** -- Cross-platform Python tool with strong fuzzy match for music and pictures; validates perceptual-hash direction.
- **Czkawka** -- Rust tool, extremely fast, supports images/audio/video similarity out of the box.
- **AllDup** -- Closed-source Windows classic with dense UI; strong feature parity reference but poor theming.
- **fclones** -- Rust CLI tool with a clean progressive hashing pipeline and hardlink/symlink replacement.

## Nice-to-Haves

- Report export: HTML (self-contained) with thumbnails for images, markdown for docs
- Schedule scans as a Windows Task with a drop-your-result-here inbox for IT teams
- Deduplicate across a mapped network drive and a local copy with explicit "never delete network" guard
- Integration with MavenSort: after a dedupe pass, trigger an organize pass on the cleaned tree
```

</details>
