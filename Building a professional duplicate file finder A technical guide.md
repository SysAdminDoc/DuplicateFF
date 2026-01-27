# Building a professional duplicate file finder: A technical guide

**For building a terabyte-scale GUI application focused on images and videos, fork Czkawka (Rust/MIT) for its exceptional architecture and performance, or Video Duplicate Finder (C#/Avalonia) for superior video fingerprinting.** Czkawka's modular `czkawka_core` library offers the best foundation—it's the most actively maintained project with **27,400+ GitHub stars**, handles millions of files efficiently, and already implements both exact hashing (Blake3, XXH3) and perceptual image/video similarity. For detecting AI-upscaled duplicates, combine **pHash and wHash** algorithms at 16×16 resolution, which preserve low-frequency structural information that survives upscaling transformations.

---

## The landscape of open-source duplicate finders

Three mature projects emerge as serious candidates for forking. **Czkawka** (Polish for "hiccup") dominates with 27,400+ stars, 75 contributors, and active development through August 2025. Written entirely in Rust, it achieves approximately 10x faster scanning than Python alternatives while consuming far less memory. Its architecture separates the core library (`czkawka_core` crate) from GUI frontends, enabling clean forking of just the engine. The MIT license permits commercial use without copyleft obligations.

**Video Duplicate Finder** (2,800 stars) specializes in the harder problem of matching videos across different resolutions, frame rates, and encodings. Built in C# on .NET 9 with Avalonia for cross-platform GUI, it extracts 32×32 grayscale fingerprints from video frames and uses pHash for comparison. The AGPL-3.0 license requires source disclosure if deployed as a network service—a significant consideration for commercial applications.

**dupeGuru** (7,100 stars), once the gold standard, shows concerning maintenance stagnation with no release since July 2022. Its Python/Qt architecture introduces performance limitations at terabyte scale, though its picture mode with adjustable "filter hardness" demonstrates mature UX patterns worth studying.

| Project | Stars | Language | GUI | License | Last Release | Maintenance |
|---------|-------|----------|-----|---------|--------------|-------------|
| Czkawka | 27.4k | Rust | GTK4/Slint | MIT | Aug 2025 | Very High |
| Video Duplicate Finder | 2.8k | C# | Avalonia | AGPL-3.0 | Active daily | High |
| dupeGuru | 7.1k | Python | Qt5 | GPL-3.0 | Jul 2022 | Low |

Notably, **AllDup is proprietary freeware**—its source code is unavailable despite sometimes being listed alongside open-source alternatives.

---

## Perceptual hashing algorithms for AI-upscale detection

Detecting AI-upscaled versions of images requires understanding how Real-ESRGAN, Topaz Gigapixel, and similar tools modify content. These upscalers **add high-frequency detail** (texture hallucination, edge enhancement, noise removal) while **preserving low-frequency structure**. This characteristic makes certain perceptual hashes particularly effective.

**wHash (Wavelet Hash) achieves the lowest average Hamming distance** (0.61 bits) across comprehensive testing of 9,143 images. It applies discrete wavelet transforms that capture multi-resolution features, showing only 6.7% deviation for scaling operations and superior robustness to watermarks (31.7% deviation vs 46.4% for pHash). For AI upscaling detection specifically, however, **pHash remains the industry standard** because its DCT-based approach explicitly extracts low-frequency components—exactly what survives upscaling.

Practical threshold recommendations for a 64-bit hash:
- **0-2 bits difference**: Identical or trivially modified
- **3-8 bits**: Likely same image with processing (AI upscaling, compression, minor edits)
- **>8 bits**: Different images

For higher precision with AI-upscaled content, use **16×16 hash size (256 bits)** and raise the threshold to 10-15 bits. The multi-hash strategy—requiring both pHash AND wHash to indicate similarity—dramatically reduces false positives.

**dHash offers sub-millisecond speed** (0.33ms vs 60ms for pHash) by comparing adjacent pixel brightness gradients, making it ideal for initial screening. However, AI upscalers specifically enhance edges, causing dHash to see more modification than structure-focused algorithms.

---

## Video fingerprinting requires a hybrid approach

Video deduplication across different encodings, resolutions, and edits demands multiple fingerprinting techniques working in concert. The **videohash library** extracts one frame per second, creates a 144×144 collage, then applies wavelet hashing—robust to transcoding, watermarks, cropping, and frame rate changes. For comprehensive matching, combine this with **Chromaprint audio fingerprinting**, which analyzes chroma features (pitch class distributions) from the first two minutes of audio, producing a compact ~2.5KB fingerprint in under 100ms.

Video Duplicate Finder implements an effective two-method approach: grayscale frame difference analysis and pHash comparison of extracted thumbnails. Its hierarchical tree view of duplicate groups demonstrates good UX for presenting video matches with varying similarity scores.

For detecting the same video at different resolutions (original vs. AI-upscaled 4K), frame sampling combined with perceptual hashing of downscaled frames provides the most reliable results. The key insight: **normalize to a common resolution before comparison** rather than comparing frames at native resolution.

---

## The performance architecture that enables terabyte scale

The fastest open-source duplicate finder, **fclones** (Rust), demonstrates the critical architectural patterns. On a 316GB dataset with 1.46 million files, fclones completes in **34 seconds** versus 5:46 for fdupes—a 10x improvement. Its approach:

**Progressive hashing eliminates 95%+ of files before full-file reads.** The algorithm groups files by size (unique sizes can't be duplicates), hashes only the first 4KB, splits groups by prefix hash, hashes the last 4KB, then finally computes full hashes only for files matching both prefix and suffix. This reduces I/O by orders of magnitude.

**Device-aware thread pools** optimize for storage characteristics. HDDs benefit from 1-2 threads performing sequential reads ordered by physical disk location (queried via `FIEMAP` on Linux). SSDs handle 4-8 parallel random reads efficiently. Network drives need increased timeouts and reduced parallelism.

**SQLite caching with inode-based identification** enables incremental scanning. The schema stores file identifier (inode + device), modification time (nanosecond precision), file size, and computed hashes. On subsequent scans, files with unchanged metadata skip rehashing entirely. WAL mode with `PRAGMA synchronous = NORMAL` balances durability and speed.

```
Scanning Pipeline:
Directory Traversal → Size Grouping → Prefix Hash (4KB) → 
Suffix Hash (4KB) → Full Hash (candidates only) → Comparison
```

---

## Choosing your technology stack

**For the scanning/hashing engine, Rust provides the best combination** of performance and safety. Benchmarks show Rust and C++ within 5-10% of each other, but Rust's ownership system enables "fearless parallelism"—concurrent code that cannot have data races by construction. The ecosystem includes excellent libraries: `rayon` for parallel iterators, `walkdir` for directory traversal, `blake3` for cryptographic hashing, and `xxhash` for maximum speed.

The hashing algorithm choice matters significantly. **xxHash3 achieves 31 GB/s** versus 0.33 GB/s for MD5 and 0.2 GB/s for SHA-256—a 100x difference. For duplicate detection where collision resistance matters less than speed, xxHash3 or Blake3 (4+ GB/s, cryptographic) are optimal.

**For cross-platform GUI, Tauri or Avalonia lead their categories.** Tauri (Rust + web frontend) produces 2.5-10MB applications using 30-50MB RAM versus Electron's 85-150MB bundles consuming 200-300MB RAM. It integrates naturally with a Rust backend. Avalonia provides true cross-platform .NET UI with Skia rendering, ideal for teams with WPF experience—Video Duplicate Finder demonstrates its capabilities.

| Component | Recommended | Alternative |
|-----------|------------|-------------|
| Core Engine | Rust | C# (.NET 8) |
| Fast Hashing | xxHash3 / Blake3 | - |
| Image Similarity | image-hasher (Rust) | ImageHash (Python) |
| GUI Cross-platform | Tauri | Avalonia |
| Database | SQLite (WAL mode) | - |

---

## Feature requirements for professional workflows

Studying existing tools reveals essential UX patterns. **Reference folders** (implemented in both Czkawka and dupeGuru) let users mark directories as untouchable—the tool will never suggest deleting files from these locations, only duplicates elsewhere. **Selection rules** provide batch operations: keep newest, keep oldest, keep files from specific paths, keep highest resolution.

**Preview capabilities differ significantly by project.** Czkawka shows image thumbnails inline with metadata. Video Duplicate Finder provides video playback from context menus. dupeGuru offers side-by-side comparison panels. For a professional tool, **preview-before-delete is non-negotiable**, especially for near-duplicates where users must verify the AI-upscaled version is truly higher quality.

Deletion safety features include: move to system trash (not permanent delete), confirmation dialogs, export of planned actions before execution, and **hardlink/symlink creation** as a space-saving alternative to deletion. Czkawka's approach of offering move/copy operations alongside delete provides maximum flexibility.

For the exact→similar→visual workflow:
1. **Exact duplicates**: Full cryptographic hash match (fastest, certain)
2. **Similar images**: Perceptual hash within threshold (fast, configurable sensitivity)
3. **Visually identical**: Human review of similar groups, potentially with SSIM pixel comparison

---

## Recommended path forward

**Primary recommendation: Fork Czkawka.** Its Rust architecture, MIT licensing, active maintenance, and modular design make it the strongest foundation. The `czkawka_core` crate can be extracted and wrapped with a new frontend while preserving battle-tested scanning and similarity logic. Krokiet (the newer Slint-based frontend) demonstrates modern UI patterns worth adapting.

**For video-heavy use cases: Fork Video Duplicate Finder.** Its specialized video fingerprinting and Avalonia GUI provide a complete starting point. The C#/.NET 9 codebase offers faster development iteration than Rust for teams without Rust experience, with competitive performance for I/O-bound workloads.

**Key enhancements to implement:**
- Progressive hashing pipeline (adopt fclones' algorithm)
- Multi-algorithm perceptual hashing (pHash + wHash combined)
- Normalized comparison for AI upscales (downscale to common resolution)
- SQLite caching with inode-based invalidation
- Device-aware thread pool configuration
- Export before delete workflow

The critical insight: **scanning speed comes from avoiding I/O**, not faster hashing. A well-architected progressive pipeline with caching will outperform any single-threaded approach regardless of language choice. Focus architectural effort on the elimination stages—size grouping, prefix hashing, suffix hashing—before optimizing the final full-file hash computation.

## Conclusion

Building a professional duplicate file management tool in 2025 benefits from a mature ecosystem of open-source foundations. Czkawka demonstrates that Rust can deliver both performance and maintainability at scale, while its modular architecture explicitly supports forking and extension. For AI-upscale detection, the combination of pHash and wHash provides the technical foundation, while progressive hashing and intelligent caching enable terabyte-scale operation on consumer hardware. The recommended approach: fork Czkawka's core, implement fclones' scanning pipeline optimizations, and build a new frontend using Tauri or Avalonia with the UX patterns established by dupeGuru's mature interface.