#!/bin/sh

# portcheck Update Script
# Called by ms after installing the new version
# Args: cmd old_version new_version target_script wrapper_path registry_name

CMD="${1:-portcheck}"
OLD_VERSION="${2:-unknown}"
NEW_VERSION="${3:-unknown}"

echo "$CMD updated: $OLD_VERSION -> $NEW_VERSION"
