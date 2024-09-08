#!/usr/bin/env bash

set -eux

# Search queries
SEARCH_QUERIES=('"last night I dreamed"' '"dream last night"' '"last night, I dreamed"' \
    '"last night I had a dream"' '"dream last night"' '"dreams last night"' '"dreamed last night"')

# SQLite path
DB_FILE="posts.db"

# Function to search Mastodon for non-sensitive posts that are under 600 characters long (480
# plus HTML) and are not replies.
search_mastodon() {

    local query=$1
    # URL-encode the search query
    local encoded_query
    encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
    
    # We're going to want to filter down results to the past 12 hours
    local timestamp
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        timestamp=$(date -v-12H -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        # Linux
        timestamp=$(date -u --iso-8601=seconds -d "12 hours ago")
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

# Main script
initialize_db

# Iterate through our search queries and execute each one
for query in "${SEARCH_QUERIES[@]}"; do
    search_mastodon "$query" | insert_into_db "$query"
done

echo "Search completed. Post IDs have been stored in $DB_FILE."
