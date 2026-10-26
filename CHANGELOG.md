# Changelog

## 1.0.1

A small fix, plus wording and a website.

- "Your latest requests" now shows only the words you typed or pasted. Text the app adds around a message (the wrapper around pasted text, and hidden system notes) is left out, and a message with nothing left is skipped. Notebooks made by 1.0.0 are cleaned up the next time Pickup refreshes them.

- The README now says what a new chat does keep (`CLAUDE.md`, auto memory, `/resume`) and what Pickup adds: where the project stands.
- The README's privacy section now says that Pickup itself sends nothing, and that the notebook is read into your Claude chat like any other file.
- New website, linked at the top of the README.
- The repo ignores a `PICKUP.md` at its top level, so Pickup can run in its own folder.

## 1.0.0 (2026-10-26)

First release.

- The project notebook, `PICKUP.md`, appears on its own after the first real piece of work, and Claude keeps it up to date.
- The latest requests (word for word, with secrets hidden) and recently changed files are copied into the notebook automatically.
- The notebook is loaded back in at the start of every session and after every compaction.
- Three commands: `/pickup:save`, `/pickup:status` and `/pickup:handoff`.
- Claude can update `PICKUP.md` without a permission prompt. This applies to that one file only, and your own permission rules still come first.
- An off switch for single projects: an empty `.pickup-off` file.
