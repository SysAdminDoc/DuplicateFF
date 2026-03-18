# DuplicateFF - Working Notes

## Overview
Professional duplicate file finder. PowerShell WPF, Catppuccin Mocha dark theme.

## Version
v1.0.0

## Tech Stack
- PowerShell WPF (single-file)
- SHA256 hashing with progressive pipeline
- Microsoft.VisualBasic for Recycle Bin support

## Architecture
Single-file `DuplicateFF.ps1`. All XAML inline via XamlReader.

### Progressive Hashing Pipeline (from fclones research)
1. **Enumerate** - Collect all files with filter/size constraints
2. **Size Group** - Files with unique sizes eliminated (can't be duplicates)
3. **Prefix Hash** - SHA256 of first 4KB, eliminate non-matches
4. **Suffix Hash** - SHA256 of last 4KB, eliminate non-matches
5. **Full Hash** - SHA256 of entire file (only remaining candidates)

Each phase eliminates 50-90% of candidates, minimizing I/O.

### Async Pattern
`[PowerShell]::Create()` + `BeginInvoke()` with `DispatcherTimer` polling (150ms).
Synchronized hashtable for thread communication.
CancellationTokenSource for cancel support.

## Features
- Folder + Reference Folder support (REF folders protected from deletion)
- File type filters (Images/Videos/Audio/Documents/All)
- Min size filter (1KB to 100MB)
- Subfolder recursion toggle
- Skip zero-byte files
- Image preview panel
- Auto-select rules (Keep Newest/Oldest/Reference/Largest/Shortest Path)
- Delete modes: Recycle Bin, Permanent, Hardlink replacement
- CSV export
- Double-click to reveal file in Explorer

## Key Files
- `DuplicateFF.ps1` - Main application (~680 lines)
- `Building a professional duplicate file finder A technical guide.md` - Research notes

## Gotchas
- File open uses `FileShare.ReadWrite` to handle locked files gracefully
- Hardlink replacement via `cmd /c mklink /H` (requires same volume)
- SVG/HEIC/AVIF excluded from preview (no native WPF decoder)
- No emoji/unicode in PowerShell output
