#!/bin/bash
# Runs a command; surfaces errors, test totals and a log tail as GitHub
# annotations so they're readable without downloading logs.
LOG=$(mktemp)
"$@" > "$LOG" 2>&1
STATUS=$?
grep -E "Executed [0-9]+ tests|Test run with|tests passed|tests failed" "$LOG" | tail -3 | while read -r l; do echo "::notice::$l"; done
grep -E "error:|failed|XCTAssert" "$LOG" | grep -v "^warning" | sort -u | head -40 | while read -r l; do echo "::error::${l:0:900}"; done
if [ $STATUS -ne 0 ]; then
  tail -25 "$LOG" | while read -r l; do echo "::warning::${l:0:900}"; done
fi
tail -60 "$LOG"
exit $STATUS
