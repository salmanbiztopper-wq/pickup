# Changelog

## 1.0.0 (2026-10-26)

First release.

- The project notebook, `PICKUP.md`, appears on its own after the first real piece of work, and Claude keeps it up to date.
- The latest requests (word for word, with secrets hidden) and recently changed files are copied into the notebook automatically.
- The notebook is loaded back in at the start of every session and after every compaction.
- Three commands: `/pickup:save`, `/pickup:status` and `/pickup:handoff`.
- Claude can update `PICKUP.md` without a permission prompt. This applies to that one file only, and your own permission rules still come first.
- An off switch for single projects: an empty `.pickup-off` file.
