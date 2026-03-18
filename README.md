# DuplicateFF v1.0.0

![License](https://img.shields.io/badge/license-MIT-blue)
![Language](https://img.shields.io/badge/language-PowerShell-5391FE)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)

Professional duplicate file finder with a progressive hashing pipeline for terabyte-scale scanning. PowerShell WPF with Catppuccin Mocha dark theme.

![DuplicateFF Screenshot](screenshot.png)

## Features

- **Progressive Hashing Pipeline** - 5-stage elimination (size grouping, prefix hash, suffix hash, full SHA256) minimizes disk I/O
- **Reference Folders** - Mark folders as protected; duplicates will never be selected from these locations
- **File Type Filters** - Images, Videos, Audio, Documents, or All Files
- **Image Preview** - Inline preview panel for visual verification before deletion
- **Auto-Select Rules** - Keep Newest, Oldest, From Reference Folders, Largest, or Shortest Path
- **Safe Deletion** - Move to Recycle Bin (default), Permanent Delete, or Replace with Hardlinks
- **CSV Export** - Full results export with hash values, groups, and file metadata
- **Async Scanning** - Non-blocking UI with real-time progress and cancellation support
- **Dark Theme** - Catppuccin Mocha with premium UI styling

## Usage

```powershell
.\DuplicateFF.ps1
```

1. Click **Add Folder** to add directories to scan
2. Optionally add **Reference Folders** (protected from deletion)
3. Set filters (min size, file type, subfolders)
4. Click **Scan for Duplicates**
5. Review results, use auto-select or manual checkbox selection
6. Choose delete mode and click **Delete Selected**

## How It Works

The progressive hashing pipeline avoids reading entire files whenever possible:

| Stage | Action | Typical Elimination |
|-------|--------|-------------------|
| 1 | Enumerate files with filters | N/A |
| 2 | Group by file size | ~70% of files |
| 3 | SHA256 of first 4KB | ~15% more |
| 4 | SHA256 of last 4KB | ~5% more |
| 5 | Full SHA256 hash | Final confirmation |

Only files surviving all stages get fully hashed, making scans fast even on large datasets.

## Research

See [Building a professional duplicate file finder: A technical guide](Building%20a%20professional%20duplicate%20file%20finder%20A%20technical%20guide.md) for the research behind this tool, covering algorithm selection, perceptual hashing for AI upscale detection, and performance architecture.

## License

MIT License
