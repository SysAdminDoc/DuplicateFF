# DuplicateFF

![License](https://img.shields.io/badge/license-MIT-blue)
![Type](https://img.shields.io/badge/type-Technical%20Guide-purple)
![Language](https://img.shields.io/badge/language-PowerShell-5391FE)

A research and architecture repository for building a professional duplicate file finder — covering hashing strategies, UI design, performance optimization, and WPF implementation patterns.

## Contents

| File | Description |
|------|-------------|
| [Building a professional duplicate file finder A technical guide.md](Building%20a%20professional%20duplicate%20file%20finder%20A%20technical%20guide.md) | Full technical guide covering architecture decisions, hashing algorithms, GUI design, and implementation approach |

## About the Guide

The guide covers:

- **Hashing Strategy** — When to use MD5, SHA-256, or xxHash; two-pass scanning (size pre-filter then hash comparison)
- **Performance** — Parallel I/O, memory-mapped files, progress reporting without blocking the UI
- **UI/UX Design** — WPF data grid layouts, grouping duplicates visually, user-friendly delete/keep workflows
- **Edge Cases** — Handling locked files, symlinks, zero-byte files, and very large file sets
- **Architecture** — Class design, separation of concerns, cancellation token patterns

## Related Project

The implementation based on this guide is **[EXTRACTORX](https://github.com/SysAdminDoc/EXTRACTORX)** — a full-featured PowerShell WPF archive extraction tool built using the same design principles.

## License

MIT License
