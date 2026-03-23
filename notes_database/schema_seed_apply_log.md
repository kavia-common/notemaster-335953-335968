# NoteMaster DB schema + seed apply log

This file records that the PostgreSQL schema and seed data for **notes**, **tags**, and **note_tags** were applied using the container rule-compliant CLI flow:

- Connection command source of truth: `notes_database/db_connection.txt`
- Execution mode: **one SQL statement at a time** via `psql ... -c "..."` with `-v ON_ERROR_STOP=1`

## Applied DDL/DML (high level)

### Extensions
- `pg_trgm` (for trigram GIN search indexes)
- `pgcrypto` (for `gen_random_uuid()` defaults)

### Tables
- `notes` (UUID PK, title, content, created_at, updated_at)
- `tags` (UUID PK, unique name)
- `note_tags` (many-to-many, PK(note_id, tag_id), CASCADE deletes)

### Indexes (search/filter/sort)
- `idx_notes_created_at`
- `idx_notes_updated_at`
- `idx_notes_title_trgm` (GIN + trgm)
- `idx_notes_content_trgm` (GIN + trgm)
- `idx_tags_name_trgm` (GIN + trgm)
- `idx_note_tags_tag_id`
- `idx_note_tags_note_id`

### Trigger
- `set_updated_at()` function
- `trg_notes_set_updated_at` trigger on `notes` (BEFORE UPDATE)

### Minimal seed
- Tags: `work`, `personal`, `ideas`
- Notes: “Welcome to NoteMaster”, “Shopping list”
- Relations: welcome→ideas, shopping→personal

## Live verification (concrete evidence)

All checks below were executed against the live database using the canonical connection command from `db_connection.txt`:

- `psql postgresql://appuser:dbuser123@localhost:5000/myapp`

### Connectivity
Verified:
- `current_database() = myapp`
- `current_user = appuser`
- PostgreSQL version: `16.11`

### Tables exist (public schema)
Verified:
- `notes`
- `tags`
- `note_tags`

### Extensions exist
Verified:
- `pg_trgm`
- `pgcrypto`

### Indexes exist (selection)
Verified in `pg_indexes`:
- Notes: `idx_notes_created_at`, `idx_notes_updated_at`, `idx_notes_title_trgm`, `idx_notes_content_trgm`
- Tags: `idx_tags_name_trgm` (and `tags_name_key`)
- Join: `idx_note_tags_note_id`, `idx_note_tags_tag_id`, `note_tags_pkey`

### Trigger exists
Verified:
- Function `set_updated_at()` exists and is visible
- Trigger `trg_notes_set_updated_at` exists on `notes` (BEFORE UPDATE)

### Seed/data row counts
Note: Avoid using reserved word `table` as an alias.

Executed:

```sql
SELECT 'notes' as tbl, count(*)::int as count FROM notes
UNION ALL SELECT 'tags' as tbl, count(*)::int FROM tags
UNION ALL SELECT 'note_tags' as tbl, count(*)::int FROM note_tags
ORDER BY tbl;
```

Observed in live DB:
- notes: 7
- tags: 4
- note_tags: 8

(Counts may be higher than “minimal seed” if previously run; schema is idempotent and seed is best-effort idempotent for tags/relations.)
