#!/bin/bash
#
# lib/cache.sh — Research caching functions
#

CACHE_DIR="${CACHE_DIR:-$HOME/.openclaw/workspace-dev/.research-cache}"
CACHE_TTL_DAYS=7

# Initialize cache directory
init_cache() {
  mkdir -p "$CACHE_DIR"
}

# Check if valid cache exists
check_cache() {
  local topic="$1"
  local depth="$2"
  local focus="$3"
  
  init_cache
  
  local cache_hash=$(generate_cache_hash "$topic" "$depth" "$focus")
  local cache_file="$CACHE_DIR/${cache_hash}.json"
  
  if [[ ! -f "$cache_file" ]]; then
    return 1
  fi
  
  # Check age
  local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")) / 86400 ))
  
  if [[ $file_age_days -gt $CACHE_TTL_DAYS ]]; then
    verbose "Cache expired ($file_age_days days old)"
    return 1
  fi
  
  # Cache valid
  CURRENT_CACHE_FILE="$cache_file"
  return 0
}

# Display cached results
display_cached_results() {
  if [[ -n "$CURRENT_CACHE_FILE" && -f "$CURRENT_CACHE_FILE" ]]; then
    cat "$CURRENT_CACHE_FILE"
  fi
}

# Cache results
cache_results() {
  local topic="$1"
  local depth="$2"
  local focus="$3"
  local results="$4"
  
  init_cache
  
  local cache_hash=$(generate_cache_hash "$topic" "$depth" "$focus")
  local cache_file="$CACHE_DIR/${cache_hash}.json"
  
  # Add metadata to cache
  local results_escaped=$(json_escape "$results")
  local cached_data=$(cat << EOF
{
  "cached_at": "$(timestamp)",
  "topic": $(json_escape "$topic"),
  "depth": "$depth",
  "focus": "$focus",
  "results": $results_escaped
}
EOF
)
  
  echo "$cached_data" > "$cache_file"
  verbose "Cached to: $cache_file"
  return 0
}

# List cached research
list_cache() {
  init_cache
  
  info "Cached research (last $CACHE_TTL_DAYS days):"
  for f in "$CACHE_DIR"/*.json; do
    if [[ -f "$f" ]]; then
      local topic=$(jq -r '.topic' "$f" 2>/dev/null)
      local date=$(jq -r '.cached_at' "$f" 2>/dev/null)
      echo "  • $topic ($date)"
    fi
  done
}

# Clear cache
clear_cache() {
  init_cache
  rm -f "$CACHE_DIR"/*.json
  info "Cache cleared"
}
