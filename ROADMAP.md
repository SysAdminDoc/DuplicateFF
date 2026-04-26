# DuplicateFF Roadmap

PowerShell WPF duplicate file finder with a 5-stage progressive hashing pipeline and Catppuccin Mocha UI. Tracks work beyond v1.0.0.

## Planned Features

### Core Engine
- Pluggable hash backend: SHA256 (default), xxHash64 (3-5x faster, already in CRC32 territory), BLAKE3 for the full-hash stage
- Perceptual hash (pHash / dHash) mode for images so AI-upscaled and re-encoded duplicates are still grouped
- Audio fingerprinting (Chromaprint) mode for MP3/FLAC dupes that differ only by bitrate/tags
- Video fingerprinting via scene-hash + ffprobe metadata
- Byte-compare fallback (last-resort) that streams both files and exits on first mismatch — handles hash collision paranoia
- Incremental scan: cache size+mtime+hash in SQLite so rescanning a 10M-file tree only processes changed files

### UX / UI
- Tree-view of the duplicate groups with expand/collapse per group
- Per-group totals (N files, X GB reclaimable)
- Thumbnail panel for images AND videos (ffmpeg thumb at 10% duration)
- Media metadata panel: EXIF, audio tags, video codec+resolution
- Side-by-side pixel diff for images (XOR overlay)
- Saved selection patterns (regex-based "auto-select anything under `C:\Downloads\*`")
- Drag-and-drop folders onto the window to add them to the scan queue
- Toast notification on scan complete with X dupes found, Y GB reclaimable

### Safety
- "Rehearse delete" mode: apply selection rules and preview exactly what will be deleted without actually moving anything
- Undo stack for the last N delete operations (works because default is Recycle Bin)
- Locked-file detection before delete; skip and log instead of fail
- Cross-volume hardlink guard: refuse to `mklink /H` across volumes (impossible) — offer junction / symlink fallback
- Reference-folder integrity guard: abort if any reference folder became inaccessible mid-scan

### Performance
- `ForEach-Object -Parallel` (PS7 path) with PS5 Runspace fallback for size grouping and hashing stages
- MemoryMappedFile reads for large files so the full-hash stage avoids doubling memory
- Configurable worker count tied to CPU core count with a disk-bound throttle
- Early abort: if size-group stage eliminates 100% of files past a threshold, skip subsequent stages

### CLI
- Full parity: `.\DuplicateFF.ps1 -Scan "D:\" -Reference "D:\Archive" -Filter Images -AutoSelect KeepOldest -Delete RecycleBin -Json`
- `-DryRun`, `-Silent`, `-ReportPath`, `-CachePath`
- Exit codes: 0 success, 1 partial, 2 user-cancelled, 3 reference folder unreadable

### Packaging
- Authenticode-signed `.ps1` + SHA256SUMS per release
- Portable ZIP release asset with screenshots, README, LICENSE
- Winget manifest (`SysAdminDoc.DuplicateFF`)
- PSGallery module path

## Competitive Research

- **dupeGuru** — Cross-platform Python tool with strong fuzzy match for music and pictures; validates perceptual-hash direction. DuplicateFF's WPF + progressive pipeline wins on Windows UX and scaling.
- **Czkawka** — Rust tool, extremely fast, supports images/audio/video similarity out of the box. Benchmark to beat on speed; borrow their UI taxonomy (Similar Images, Music Duplicates, Big Files).
- **AllDup** — Closed-source Windows classic with dense UI; strong feature parity reference but poor theming. DuplicateFF already ships Catppuccin Mocha — hold that line.
- **fclones** — Rust CLI tool with a clean progressive hashing pipeline and hardlink/symlink replacement; worth mirroring its algorithmic choices and CLI flags.

## Nice-to-Haves

- Report export: HTML (self-contained) with thumbnails for images, markdown for docs
- Schedule scans as a Windows Task with a drop-your-result-here inbox for IT teams
- Deduplicate across a mapped network drive and a local copy with explicit "never delete network" guard
- ZFS / Storage Spaces-aware mode that creates CoW reflinks instead of hardlinks where supported
- "Find nearly-duplicate" mode using fuzzy pHash thresholding — drag a slider from strict to loose
- Integration with MavenSort: after a dedupe pass, trigger an organize pass on the cleaned tree

## Open-Source Research (Round 2)

### Related OSS Projects
- **dupeguru** — https://github.com/arsenetar/dupeguru — Python/Qt duplicate finder with Standard/Music/Picture modes; fuzzy-name and perceptual-image match; mature UX reference
- **Czkawka** — https://github.com/qarmin/czkawka — Rust multi-tool: dup files, empty folders, big files, bad extensions, broken files, similar images/videos, same-music; fast and lean
- **Krokiet** — https://github.com/qarmin/krokiet — newer Slint-GUI front for Czkawka; cleaner modern look
- **fdupes** — https://github.com/adrianlopezroche/fdupes — classic C duplicate finder on Unix; reference for CLI ergonomics
- **jdupes** — https://github.com/jbruchon/jdupes — fdupes fork with dedupe by hardlink/clonefile/dedup ioctl; production speed
- **rdfind** — https://github.com/pauldreik/rdfind — ranks matches and can auto-hardlink; used by sysadmins at scale
- **fclones** — https://github.com/pkolaczk/fclones — Rust, multi-threaded, JSON output, reflink support on APFS/Btrfs/XFS/ZFS
- **SearchMyFiles (NirSoft)** — not OSS but notable Windows sibling
- **AllDup** — freeware Windows reference; closest UI competitor

### Features to Borrow
- Reflink/copy-on-write replacement on supported filesystems (APFS/Btrfs/XFS/ReFS) — zero-cost dedupe without touching data (fclones, jdupes)
- Perceptual-hash match for images (pHash/dHash) and videos (frame-hash sampling) with adjustable similarity threshold (Czkawka, dupeguru Picture mode)
- Audio-fingerprint matching for music dupes across different formats (Czkawka same-music, dupeguru Music)
- JSON/CSV/YAML export of duplicate groups for scripting downstream actions (fclones has this)
- "Exclude-by-content" list: paste a list of known-good hashes that should never be flagged (jdupes --nohidden equivalent extension)
- Ranked auto-selection with composable rules chain: "keep newest" + "prefer reference folders" + "prefer shortest path" tie-breakers (rdfind ranking)
- Dry-run mode that writes the proposed action plan to a file for review before execution (rdfind -dryrun, fclones)
- Symlink detection and loop protection during recursive scan (all serious tools handle this; DuplicateFF should confirm)
- Progress + ETA from cumulative byte count (not file count) — more accurate on uneven trees (fclones pattern)
- Resume from checkpoint: persist mid-scan state so a terabyte scan can survive a reboot (production feature; fclones has seen this asked)

### Patterns & Architectures Worth Studying
- Progressive elimination pipeline: size-group → partial hash (first 4KB) → full hash → byte compare only on collision (fclones, Czkawka — same 5-stage model as DuplicateFF)
- Reflink-first dedupe: on supported FS, replace duplicate bytes with a CoW clone — saves space, preserves separate inodes/metadata (jdupes, fclones)
- Parallelism strategy: one thread per physical disk (NOT per core), since bottleneck is I/O — fclones explicitly measures and schedules this way
- Reference-folder concept as an input to the scoring function, not a filter: prefer-keep from refs, still-consider-for-linking (rdfind ranking system)
- Plugin/mode architecture where file-type adds a new similarity engine (dupeguru Standard/Music/Picture modes are separate algorithms behind one UI)
