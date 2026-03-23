#!/bin/bash
set -euo pipefail

# Applies NoteMaster schema + minimal seed data to the local PostgreSQL instance.
# This script intentionally uses db_connection.txt as the single source of truth
# for the psql connection command, per container rules.
#
# Usage:
#   ./startup.sh              # ensure postgres is running (if needed)
#   bash apply_schema_and_seed.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "db_connection.txt" ]; then
  echo "ERROR: db_connection.txt not found in ${SCRIPT_DIR}"
  exit 1
fi

PSQL_CMD="$(cat db_connection.txt)"
echo "Using: ${PSQL_CMD}"

run_sql () {
  local sql="$1"
  # -v ON_ERROR_STOP=1 ensures the script stops on any SQL error.
  ${PSQL_CMD} -v ON_ERROR_STOP=1 -c "${sql}"
}

echo "== Enabling extensions =="
run_sql "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

echo "== Creating tables =="
run_sql "CREATE TABLE IF NOT EXISTS notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

run_sql "CREATE TABLE IF NOT EXISTS tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

run_sql "CREATE TABLE IF NOT EXISTS note_tags (
  note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (note_id, tag_id)
);"

echo "== Indexes for search/filter/sort =="
run_sql "CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);"
run_sql "CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);"
run_sql "CREATE INDEX IF NOT EXISTS idx_notes_title_trgm ON notes USING gin (title gin_trgm_ops);"
run_sql "CREATE INDEX IF NOT EXISTS idx_notes_content_trgm ON notes USING gin (content gin_trgm_ops);"
run_sql "CREATE INDEX IF NOT EXISTS idx_tags_name_trgm ON tags USING gin (name gin_trgm_ops);"
run_sql "CREATE INDEX IF NOT EXISTS idx_note_tags_tag_id ON note_tags(tag_id);"
run_sql "CREATE INDEX IF NOT EXISTS idx_note_tags_note_id ON note_tags(note_id);"

echo "== updated_at maintenance trigger =="
# Use single quotes around the function body $$ ... $$ when calling this script from bash would be best,
# but here we are already passing as a single argument to psql -c. To keep it robust and simple,
# we create the function via psql directly, then drop/create the trigger idempotently.
run_sql "CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS \$\$ BEGIN NEW.updated_at = now(); RETURN NEW; END; \$\$ LANGUAGE plpgsql;"
run_sql "DROP TRIGGER IF EXISTS trg_notes_set_updated_at ON notes;"
run_sql "CREATE TRIGGER trg_notes_set_updated_at BEFORE UPDATE ON notes FOR EACH ROW EXECUTE FUNCTION set_updated_at();"

echo "== Minimal seed data (idempotent) =="
run_sql "INSERT INTO tags (name) VALUES ('work') ON CONFLICT (name) DO NOTHING;"
run_sql "INSERT INTO tags (name) VALUES ('personal') ON CONFLICT (name) DO NOTHING;"
run_sql "INSERT INTO tags (name) VALUES ('ideas') ON CONFLICT (name) DO NOTHING;"

run_sql "INSERT INTO notes (title, content)
VALUES ('Welcome to NoteMaster', 'This is your first note. Try editing, searching, and tagging!');"

run_sql "INSERT INTO notes (title, content)
VALUES ('Shopping list', E'- Milk\n- Eggs\n- Coffee');"

run_sql "WITH n AS (
  SELECT id FROM notes WHERE title='Welcome to NoteMaster' ORDER BY created_at DESC LIMIT 1
), t AS (
  SELECT id FROM tags WHERE name='ideas'
)
INSERT INTO note_tags (note_id, tag_id)
SELECT n.id, t.id FROM n, t
ON CONFLICT DO NOTHING;"

run_sql "WITH n AS (
  SELECT id FROM notes WHERE title='Shopping list' ORDER BY created_at DESC LIMIT 1
), t AS (
  SELECT id FROM tags WHERE name='personal'
)
INSERT INTO note_tags (note_id, tag_id)
SELECT n.id, t.id FROM n, t
ON CONFLICT DO NOTHING;"

echo "== Done. Current row counts =="
run_sql "SELECT 'notes' as table, count(*) as count FROM notes
UNION ALL SELECT 'tags', count(*) FROM tags
UNION ALL SELECT 'note_tags', count(*) FROM note_tags;"

echo "Schema + seed applied successfully."
