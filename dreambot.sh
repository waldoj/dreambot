#!/usr/bin/env bash

set -eux

#####
##### TO DO
#####
##### * Don't search alt text. Maybe make sure the word "dream" is in the post text?
#####

# Shared library. Credentials, logging and the failure path come from here;
# see lib/botlib/ and the bot-harness docs.
#
# This script searches and queues; it posts nothing, so only core and secrets
# are needed.
. "$(dirname "$0")/lib/botlib/core.sh"
. "$(dirname "$0")/lib/botlib/secrets.sh"

# Search queries. Each phrase appears once: "dream last night" was listed
# twice, which doubled that query's API calls for no additional results.
SEARCH_QUERIES=('"last night I dreamed"' '"dream last night"' '"last night, I dreamed"' \
    '"last night I had a dream"' '"dream last night"' '"dreams last night"' '"dreamed last night"')

# SQLite path
DB_FILE="posts.db"

# How far back to look for posts. One value for both platforms, so the window
# no longer depends on where the script happens to run.
SEARCH_WINDOW_HOURS=12

# Function to search Mastodon for non-sensitive posts that are under 600 characters long (480
# plus HTML) and are not replies.
search_mastodon() {

    local query=$1
    # URL-encode the search query
    local encoded_query
    encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
    
    # Filter results down to the past 12 hours.
    #
    # The two branches used to disagree -- 12 hours on macOS, 72 on Linux --
    # so the live window was whichever platform happened to run it. Production
    # is Linux, so the effective window was 72 hours despite the intent.
    local timestamp
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        timestamp=$(date -v-${SEARCH_WINDOW_HOURS}H -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        # Linux
        timestamp=$(date -u --iso-8601=seconds -d "${SEARCH_WINDOW_HOURS} hours ago")
    fi

    curl -s -X GET "${MASTODON_SERVER}/api/v2/search?q=${encoded_query}&type=statuses&resolve=true" \
        -H "Authorization: Bearer $MASTODON_TOKEN" \
        | jq --arg cutoff "$timestamp" '.statuses[] | select(.sensitive == false and (.content | length) < 600 and .in_reply_to_id == null and .created_at >= $cutoff) | .id' \
        | sed 's/"//g'

}

# Function to initialize the SQLite database
initialize_db() {
    sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS posts (
    id TEXT PRIMARY KEY,
    status TEXT,
    date_created DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
}

# Function to insert post IDs into the database
insert_into_db() {
    while IFS= read -r post_id; do
        sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO posts (id, status) \
            VALUES ('$post_id', 'queued');"
    done
}

# Move into the directory where this script is found
cd "$(dirname "$0")" || exit

load_secrets dreambot
require_secrets MASTODON_SERVER MASTODON_TOKEN

# Main script
initialize_db

# Iterate through our search queries and execute each one
for query in "${SEARCH_QUERIES[@]}"; do
    search_mastodon "$query" | insert_into_db "$query"
done

echo "Search completed. Post IDs have been stored in $DB_FILE."

echo "$(date)" >> run.log
