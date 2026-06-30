# archive/

Historical / superseded files moved here to de-clutter the project root.

**Nothing in this folder is used by the app, the build, the CI, or the
schema-drift tool.** It is safe to keep, ignore, or delete. The app bundles only
`assets/` (see `pubspec.yaml`); the live database is driven by
`silence_app/migrations/*.sql` + `silence_app/supabase_schema.sql` (both still in
their original location and untouched).

## Contents

- **`old-analysis/`** — stale `flutter analyze` dumps, a one-off screen-inventory
  generator script + its CSV output, and a raw text extraction. All regenerable.
- **`old-sql/`** — loose scratch SQL that once sat at the repo root
  (`draft_members.sql`, `expenditures.sql`, `indices.sql`). These tables/indexes
  already live in the canonical `silence_app/supabase_schema.sql`; these copies
  were redundant.
- **`audit-reports/`** — completed audit reports (external + internal) that have
  already been verified and actioned. The current/active planning docs remain in
  `docs_fix/`.
- **`docs_audit/`** — the older phased audit set (AUDIT_PHASE_0..16, early PRD /
  state / matrices). Superseded by `docs_fix/` and the live codebase, which
  `AGENTS.md` defines as the source of truth.

## Still-active docs (NOT here)

- `AGENTS.md`, `CLAUDE.md`, `README.md` — project root.
- `docs_fix/` — current working docs (AGENTS.md §0 reads several of these).
- `silence_app/` — DB migrations + canonical schema + original spec.
