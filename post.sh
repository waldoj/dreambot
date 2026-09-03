#!/usr/bin/env bash

set -eux

# Shared library: credentials, logging, the failure path, and Mastodon
# transport. See lib/botlib/ and the bot-harness docs.
. "$(dirname "$0")/lib/botlib/core.sh"
. "$(dirname "$0")/lib/botlib/secrets.sh"
. "$(dirname "$0")/lib/botlib/mastodon.sh"

# Database file
DB_FILE="posts.db"

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

load_secrets dreambot
require_secrets MASTODON_SERVER MASTODON_TOKEN

# Select an entry
POST_ID=$(select_entry)

if ! [[ "$POST_ID" =~ ^[0-9]+$ ]]; then
  exit_error "No queued posts found."
fi

# Repost this status.
#
# The old curl had no -f, so a 500 exited 0: the failure branch never ran, and
# the row was marked published even though the boost had not happened. That
# post could then never be retried. masto_reblog uses -f, so a failure now
# stops the script with the row left queued.
masto_reblog "$POST_ID" > /dev/null \
    || exit_error "Reposting message on Mastodon failed"

echo "Repost succeeded"
sqlite3 "$DB_FILE" "UPDATE posts SET status='published' WHERE id=${POST_ID}"

log_info "boosted status=${POST_ID}"
