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

## Verification query
Executed:

```sql
SELECT 'notes' as table, count(*) as count FROM notes
UNION ALL SELECT 'tags', count(*) FROM tags
UNION ALL SELECT 'note_tags', count(*) FROM note_tags;
```

Observed result at time of apply:

- notes: 7
- tags: 4
- note_tags: 8

(Counts may be higher than “minimal seed” if previously run; schema is idempotent and seed is best-effort idempotent for tags/relations.)
