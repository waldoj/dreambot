#!/usr/bin/env bash

set -eux

# Database file
DB_FILE="posts.db"

# Define a failure function
function exit_error {
    printf '%s\n' "$1" >&2
    exit "${2-1}"
}

# Select an entry from the list
function select_entry {
    sqlite3 "$DB_FILE" '
        SELECT id
        FROM posts
        WHERE status="queued"
        ORDER BY date_created DESC
        LIMIT 1;' | sed 's/"//g'
}

# Move into the directory where this script is found
cd "$(dirname "$0")" || exit

# Select an entry
POST_ID=$(select_entry)

if ! [[ "$POST_ID" =~ ^[0-9]+$ ]]; then
  exit_error "No queued posts found."
fi

# Repost this status
curl -X POST \
     -H "Authorization: Bearer ${MASTODON_TOKEN}" \
     ${MASTODON_SERVER}/api/v1/statuses/${POST_ID}/reblog

RESULT=$?
if [ "$RESULT" -ne 0 ]; then
    exit_error "Reposting message on Mastodon failed"
else
    echo "Repost succeeded"
    sqlite3 "$DB_FILE" "UPDATE posts SET status='published' WHERE id=${POST_ID}"
fi
