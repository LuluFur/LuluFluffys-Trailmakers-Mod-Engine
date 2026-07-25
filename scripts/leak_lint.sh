#!/bin/bash
################################################################################
# leak_lint.sh
#
# Scans engine.lua for per-player state tables and verifies they are either:
# 1. Registered for cleanup (appear in a known registry)
# 2. Explicitly marked WONTFIX with a comment
#
# This is a non-blocking lint pass. The full table registry (issue #23) does
# not exist yet, so this only detects obvious patterns and suggests follow-up.
#
# Output: leak-lint-report.txt (human-readable findings)
# Exit code: always 0 (non-blocking in CI)
################################################################################

set -e

REPORT="leak-lint-report.txt"
ENGINE_FILE="data_static/engine.lua"
ALLOWLIST="scripts/.leak_lint_allowlist"

# Initialize report
: > "$REPORT"

echo "Scanning $ENGINE_FILE for per-player state patterns..." >&2

# Look for patterns that suggest per-player tables:
# - Variables storing Player-indexed data
# - Tables keyed by player name or player object
# - _playerData, _playerTables, etc.
# - Any pattern like "[player]" or "[p.name]" or "[p.UserId]"

echo "=== Per-Player Table Scan ===" >> "$REPORT"
echo "Engine file: $ENGINE_FILE" >> "$REPORT"
echo "Scan date: $(date -u)" >> "$REPORT"
echo "" >> "$REPORT"

# Pattern 1: Variables that look like player registries
echo "Finding potential per-player state variables..." >> "$REPORT"
grep -n "local.*player" "$ENGINE_FILE" | grep -E "(table|map|registry|set)" >> "$REPORT" || echo "  (none found)" >> "$REPORT"

echo "" >> "$REPORT"

# Pattern 2: Comments that mention player-scoped or per-player storage
echo "Finding comments about per-player state..." >> "$REPORT"
grep -n "player.*table\|per-player\|per player" "$ENGINE_FILE" | head -20 >> "$REPORT" || echo "  (none found)" >> "$REPORT"

echo "" >> "$REPORT"

# Pattern 3: References to service-local storage that might hold player data
echo "Finding service-local storage patterns..." >> "$REPORT"
grep -n "self\._.*\[\|self\..*player" "$ENGINE_FILE" | head -20 >> "$REPORT" || echo "  (none found)" >> "$REPORT"

echo "" >> "$REPORT"

# Pattern 4: Check if there's an allowlist and compare
if [ -f "$ALLOWLIST" ]; then
    echo "Allowlist found at $ALLOWLIST" >> "$REPORT"
    echo "Allowed patterns:" >> "$REPORT"
    cat "$ALLOWLIST" >> "$REPORT"
else
    echo "No allowlist yet (create scripts/.leak_lint_allowlist to suppress patterns)" >> "$REPORT"
fi

echo "" >> "$REPORT"

# Summary
PATTERN_COUNT=$(grep -E "local.*player|per-player|per player" "$ENGINE_FILE" | wc -l)
echo "Summary:" >> "$REPORT"
echo "  Found $PATTERN_COUNT lines matching per-player patterns" >> "$REPORT"
echo "  NOTE: This is an early scan. Full registry tracking (issue #23) will refine this." >> "$REPORT"
echo "  Review findings and update scripts/.leak_lint_allowlist if patterns are safe." >> "$REPORT"

# Print report to stdout
echo ""
cat "$REPORT"

# Non-blocking exit
exit 0
