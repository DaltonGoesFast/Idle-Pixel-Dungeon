# APK size (informational)

Phase 1 does **not** target APK under 50 MB (Discord). Official Godot Android templates keep the engine binary large (DECISIONS #2, #246).

## Snapshot (v0.50.4 APK ~90 MB)

| Bucket | Approx | Notes |
|--------|--------|--------|
| `lib/arm64-v8a/libgodot_android.so` | ~74 MB | Engine floor under official templates |
| Pack content (`assets/.godot/imported`) | ~13–14 MB | Game data after import |
| Music (`.ogg` / `.oggvorbisstr`) | ~10 MB | Dominant content driver (`assets/music/` ~42 files) |
| Sprites / UI / fonts / JSON | ~3–4 MB | Pixel sheets stay small |
| `reference/`, `android/build/` | — | Not exported (`.gdignore` / gitignore) |

## Safe hygiene

- Every export preset excludes `tests/*`, `docs/*`, `tools/*`, `*.md`, and `builds/*` (so screenshot trees / prior APKs do not re-pack).
- Also excluded: branding guides / mockups (`*guide*`, `mockup*`) and `.pdn` sources (not used at runtime; see `assets/branding/README.md`).
- Prefer filter hygiene over cutting music or stripping engine modules.

## How to re-measure (PC, no phone)

1. Export Android (or use an existing `builds/*.apk`).
2. Copy to `.zip` and sum compressed sizes by top-level folder (`lib`, `assets`, …), or inspect `lib/arm64-v8a/libgodot_android.so` vs `assets/.godot/imported/*.oggvorbisstr`.
