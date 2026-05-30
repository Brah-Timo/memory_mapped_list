# Migration Guide

## Upgrading to 0.1.x

This is the initial public release.  No migration is needed.

---

## Future migration notes (reserved)

This document will track breaking changes between published versions.

### Version numbering

`memory_mapped_list` follows [Semantic Versioning](https://semver.org/):

- **Patch** (0.1.x): bug fixes, documentation, performance improvements.
  No API or file-format changes.
- **Minor** (0.x.0): new features added in a backwards-compatible manner.
  Existing `.mml` files remain readable.
- **Major** (x.0.0): breaking API or file-format changes.
  A migration guide section will be added here.

---

## Dart SDK requirement

Starting with version **0.1.0**, the minimum Dart SDK is **3.6.0**.

This is required because the codebase uses digit-separator literals
(`1_000_000`) introduced in Dart 3.6 as a stable language feature
(previously experimental behind `--enable-experiment=digit-separators`).

If you need Dart 3.0–3.5 compatibility, use the older 0.0.x releases.

---

## Checklist for upgrading

1. Ensure `dart --version` reports ≥ 3.6.0.
2. Run `dart pub upgrade memory_mapped_list`.
3. Run `dart pub get` to resolve updated dependencies.
4. Run `dart analyze` and `dart test` — no breaking API changes are
   expected for 0.1.x patch releases.

---

## File format compatibility

`.mml` files written by any 0.x.x release are fully forward-compatible
with all future 0.x.x releases.  Format version 1 will be supported
indefinitely.
