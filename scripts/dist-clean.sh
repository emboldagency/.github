#!/bin/bash
# WPhaven Recipe: Distribution Cleaner
# Iterates over a target directory (or all plugins in a directory)
# and removes any files/folders listed in their local .distignore files.

TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory $TARGET_DIR does not exist."
  exit 1
fi

clean_plugin() {
  local plugin_dir="$1"
  local plugin_slug=$(basename "$plugin_dir")
  local distignore="$plugin_dir/.distignore"

  # If it's one of our own plugins and .distignore is missing locally, fetch it from GitHub!
  if [ ! -f "$distignore" ]; then
    if [[ "$plugin_slug" == embold-* ]] || [[ "$plugin_slug" == wphaven-* ]]; then
      echo "⬇️  Fetching .distignore from GitHub for $plugin_slug..."
      curl -sL -f "https://raw.githubusercontent.com/emboldagency/${plugin_slug}/master/.distignore" > "/tmp/.distignore_${plugin_slug}"
      if [ $? -eq 0 ]; then
        distignore="/tmp/.distignore_${plugin_slug}"
      else
        return 0
      fi
    else
      return 0
    fi
  fi

  echo "🧹 Cleaning $plugin_slug against .distignore..."

  while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    if [[ -z "$pattern" ]] || [[ "$pattern" == \#* ]]; then
      continue
    fi
    
    pattern=$(echo "$pattern" | tr -d '\r' | xargs)
    
    shopt -s nullglob
    for match in "$plugin_dir"/$pattern; do
      if [ -e "$match" ]; then
        rm -rf "$match" 2>/dev/null
      fi
    done
    shopt -u nullglob

  done < "$distignore"
  
  # Clean up temp file if we downloaded it
  if [[ "$distignore" == /tmp/* ]]; then
    rm -f "$distignore"
  fi
}

if [ -f "$TARGET_DIR/.distignore" ] || [[ $(basename "$TARGET_DIR") == embold-* ]] || [[ $(basename "$TARGET_DIR") == wphaven-* ]]; then
  clean_plugin "$TARGET_DIR"
else
  for d in "$TARGET_DIR"/*/; do
    if [ -d "$d" ]; then
      clean_plugin "${d%/}"
    fi
  done
fi

echo "✅ Dist-clean complete!"
