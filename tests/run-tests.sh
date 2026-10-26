#!/bin/sh
# Pickup test suite.
#
# Feeds fake hook inputs into scripts/pickup.sh, the same way Claude Code
# does, and checks what comes out. Nothing here touches your real projects
# or your real Claude Code data: everything happens in a temporary folder.
#
# Usage:
#   sh tests/run-tests.sh              test with the awk on your PATH
#   sh tests/run-tests.sh /usr/bin/mawk   test with a specific awk
#
# The script under test runs with dash when it is installed, because dash
# is strict about POSIX sh. Otherwise it falls back to sh.

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/../scripts/pickup.sh
TEMPLATE_ROOT=$HERE/..

if command -v dash >/dev/null 2>&1; then RUNSH=dash; else RUNSH=sh; fi

T=${TMPDIR:-/tmp}/pickup-tests.$$
rm -rf "$T"
mkdir -p "$T/bin" || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

# Use a specific awk if one was given, by putting it first on the PATH.
if [ -n "${1:-}" ]; then
  [ -x "$1" ] || { echo "Not an awk program: $1"; exit 1; }
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$1" >"$T/bin/awk"
  chmod +x "$T/bin/awk"
  PATH=$T/bin:$PATH
  export PATH
fi
# </dev/null matters: an awk that doesn't know a flag may wait for input.
AWKNAME=$(awk -W version </dev/null 2>/dev/null | head -n 1)
[ -n "$AWKNAME" ] || AWKNAME=$(awk --version </dev/null 2>/dev/null | head -n 1)
[ -n "$AWKNAME" ] || AWKNAME=$(awk -version </dev/null 2>/dev/null | head -n 1)
[ -n "$AWKNAME" ] || AWKNAME="awk (version unknown)"
echo "Shell: $RUNSH"
echo "Awk:   $AWKNAME"
echo

unset CLAUDE_PROJECT_DIR
CLAUDE_PLUGIN_ROOT=$TEMPLATE_ROOT
CLAUDE_PLUGIN_DATA=$T/data
export CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA

PASS=0
FAIL=0
BS=$(printf '\134') # one backslash
TAB=$(printf '\t')

ok() {
  PASS=$((PASS + 1))
  echo "  ok    $1"
}
bad() {
  FAIL=$((FAIL + 1))
  echo "  FAIL  $1"
}
check() { # check "description" command...
  d=$1
  shift
  if "$@"; then ok "$d"; else bad "$d"; fi
}
has() { printf '%s' "$1" | grep -F -- "$2" >/dev/null; }
lacks() { ! has "$1" "$2"; }
file_has() { [ -f "$1" ] && grep -F -- "$2" "$1" >/dev/null; }
file_lacks() { ! file_has "$1" "$2"; }
is_empty() { [ -z "$1" ]; }

# Run one hook. Sets OUT (what it printed) and RC (its exit code).
hook() { # hook mode json
  OUT=$(printf '%s' "$2" | "$RUNSH" "$SCRIPT" "$1" 2>"$T/stderr")
  RC=$?
  [ "$RC" -eq 0 ] || bad "exit code 0 for $1 (got $RC)"
}

# The private log for a project, found by its folder name.
log_of() { ls "$CLAUDE_PLUGIN_DATA"/projects/"$1"-*/activity.log 2>/dev/null | head -n 1; }

# Is this valid UTF-8? Uses iconv when available.
HAVE_ICONV=0
if printf 'a' | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then HAVE_ICONV=1; fi
valid_utf8() { printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; }

new_project() { # new_project name -> sets P
  P=$T/projects/$1
  rm -rf "$P"
  mkdir -p "$P"
}
edit() { hook post-edit "{\"cwd\":\"$P\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/$1\"}}"; }
say() { hook prompt "{\"cwd\":\"$P\",\"prompt\":\"$1\"}"; }
stop() { hook stop "{\"cwd\":\"$P\",\"stop_hook_active\":${1:-false}}"; }

# ---------------------------------------------------------------------------
echo "1. Fresh project: prompts and edits until the notebook appears"
new_project fresh
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\",\"transcript_path\":\"$T/sessions/one.jsonl\"}"
check "session start explains the notebook does not exist yet" has "$OUT" "does not exist yet"
say "add a menu section with photos"
check "a request prints nothing (costs no context)" is_empty "$OUT"
say "make the order button green and bigger"
say "/pickup:status"
edit index.html
edit styles.css
stop
check "no notebook after 2 edits" test ! -f "$P/PICKUP.md"
check "no reminder after 2 edits" is_empty "$OUT"
edit menu.html
stop
check "notebook created after 3 edits" test -f "$P/PICKUP.md"
check "Claude is asked to fill it in" has "$OUT" '{"decision":"block","reason":"Pickup created PICKUP.md'
Q=$(printf '%s' "$OUT" | tr -cd '"' | wc -c)
check "reminder JSON has exactly 8 quote marks (valid, no stray quotes)" [ "$Q" -eq 8 ]
check "notebook comes from the template" file_has "$P/PICKUP.md" "## Next step"

echo "2. The facts block fills in"
NB=$P/PICKUP.md
check "facts start marker" file_has "$NB" "<!-- pickup:facts:start -->"
check "facts end marker" file_has "$NB" "<!-- pickup:facts:end -->"
check "newest request is first" file_has "$NB" '1. "make the order button green and bigger"'
check "older request is second" file_has "$NB" '2. "add a menu section with photos"'
check "bare slash commands are not listed as requests" file_lacks "$NB" "/pickup:status"
check "newest changed file is first" grep -n -- "- menu.html" "$NB" >/dev/null
L1=$(grep -n -- "^- menu.html" "$NB" | cut -d: -f1)
L2=$(grep -n -- "^- index.html" "$NB" | cut -d: -f1)
R=1
[ "${L1:-0}" -gt 0 ] && [ "${L1:-0}" -lt "${L2:-0}" ] && R=0
check "files are newest first" [ "$R" -eq 0 ]
check "the private log is not in the project" test ! -f "$P/activity.log"
LOG=$(log_of fresh)
check "the private log is in the plugin data folder" test -f "$LOG"
check "session record path logged as TRANSCRIPT" file_has "$LOG" "TRANSCRIPT${TAB}$T/sessions/one.jsonl"

echo "3. Saving the notebook resets the counter"
hook post-edit "{\"cwd\":\"$P\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$NB\"}}"
check "notebook edit logged as SAVE" file_has "$LOG" "SAVE${TAB}PICKUP.md"
for f in a b c d e; do edit "$f.txt"; done
stop
check "no reminder after 5 edits since the save" is_empty "$OUT"
edit f.txt
stop
check "reminder after 6 edits since the save" has "$OUT" "6 edits have been made since PICKUP.md was last updated"
stop
check "no second reminder for the same edits" is_empty "$OUT"

echo "4. Loop guard"
for f in g h i j k l; do edit "$f.txt"; done
stop true
check "stop_hook_active true: nothing printed" is_empty "$OUT"
stop
check "the same edits still get a reminder at the next normal stop" has "$OUT" "6 edits"

echo "5. Compaction"
say "now the order form"
hook pre-compact "{\"cwd\":\"$P\",\"trigger\":\"auto\",\"custom_instructions\":null}"
check "COMPACT logged" file_has "$LOG" "COMPACT${TAB}auto"
check "facts refreshed before compaction" file_has "$NB" '1. "now the order form"'
hook session-start "{\"cwd\":\"$P\",\"source\":\"compact\",\"transcript_path\":\"$T/sessions/one.jsonl\"}"
check "after compaction: re-check Next step" has "$OUT" "checks the Next step section"
check "after compaction: mentions the new-chat restart" has "$OUT" "/pickup:handoff, then open a new chat in this same folder"
check "after compaction: mentions /clear as the other option" has "$OUT" "or type /clear to start fresh here"
check "after compaction: plain phrases work without the command list" has "$OUT" "If the user asks to save progress"
check "after compaction: the notebook itself is loaded" has "$OUT" "## What we're building"
check "after compaction: facts are loaded too" has "$OUT" "now the order form"
N=$(grep -c "TRANSCRIPT" "$LOG")
check "same session record not logged twice" [ "$N" -eq 1 ]
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\"}"
check "fresh session: one-line status expected" has "$OUT" "begin its first reply with one plain sentence"
hook session-start "{\"cwd\":\"$P\",\"source\":\"resume\"}"
check "resumed session: no opening line" has "$OUT" "no opening status line is needed"
hook session-start "{\"cwd\":\"$P\",\"source\":\"clear\",\"transcript_path\":\"$T/sessions/two.jsonl\"}"
check "after /clear: one-line status expected" has "$OUT" "begin its first reply with one plain sentence"
check "a new session record is logged" file_has "$LOG" "TRANSCRIPT${TAB}$T/sessions/two.jsonl"
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\",\"transcript_path\":\"$T/sessions/three.jsonl\"}"
check "new chat in the same folder: one-line status expected" has "$OUT" "begin its first reply with one plain sentence"
check "new chat in the same folder: notebook loaded" has "$OUT" "## Next step"
check "new chat's session record is logged" file_has "$LOG" "TRANSCRIPT${TAB}$T/sessions/three.jsonl"

echo "6. A long notebook is cut safely"
new_project long
awk 'BEGIN { print "# Where this project stands"; for (i = 1; i <= 400; i++) print "- decision " i ": a reason that is long enough to take up room" }' >"$P/PICKUP.md"
OUT=$(printf '{"cwd":"%s","source":"startup"}' "$P" | PICKUP_CONTEXT_BYTES=3000 "$RUNSH" "$SCRIPT" session-start)
SIZE=$(printf '%s' "$OUT" | wc -c)
check "output stays under the limit (3000 bytes, got $((SIZE + 0)))" [ "$SIZE" -le 3000 ]
check "says it was cut" has "$OUT" "was cut here"
LAST=$(printf '%s\n' "$OUT" | grep -- "^- decision" | tail -n 1)
check "cut at the end of a whole line" has "$LAST" "take up room"
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\"}"
SIZE=$(printf '%s' "$OUT" | wc -c)
check "default limit keeps output under 10,000 characters (got $((SIZE + 0)))" [ "$SIZE" -lt 9500 ]

echo "7. Windows-style paths"
WROOT="C:${BS}${BS}Users${BS}${BS}Test${BS}${BS}proj"
hook prompt "{\"cwd\":\"$WROOT\",\"prompt\":\"fix the header\"}"
hook post-edit "{\"cwd\":\"C:/Users/Test/proj\",\"tool_input\":{\"file_path\":\"C:${BS}${BS}Users${BS}${BS}Test${BS}${BS}proj${BS}${BS}src${BS}${BS}app.js\"}}"
hook post-edit "{\"cwd\":\"/c/Users/Test/proj\",\"tool_input\":{\"file_path\":\"$WROOT${BS}${BS}PICKUP.md\"}}"
WLOG=$(log_of proj)
N=$(ls -d "$CLAUDE_PLUGIN_DATA"/projects/proj-* 2>/dev/null | wc -l)
check "C:\\, C:/ and /c/ forms share one log" [ "$N" -eq 1 ]
check "edit logged relative to the project" file_has "$WLOG" "EDIT${TAB}src/app.js"
check "notebook save through a Windows path counts as a save" file_has "$WLOG" "SAVE${TAB}PICKUP.md"
hook pre-edit "{\"cwd\":\"/c/Users/Test/proj\",\"permission_mode\":\"default\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WROOT${BS}${BS}PICKUP.md\"}}"
check "notebook edit through a Windows path is let through" has "$OUT" '"permissionDecision":"allow"'
OUT=$(printf '{"tool_input":{"file_path":"C:%sUsers%sTest%sproj%sb.txt"}}' "$BS$BS" "$BS$BS" "$BS$BS" "$BS$BS" | CLAUDE_PROJECT_DIR="C:${BS}Users${BS}Test${BS}proj" "$RUNSH" "$SCRIPT" post-edit)
check "project folder given with backslashes in CLAUDE_PROJECT_DIR" file_has "$WLOG" "EDIT${TAB}b.txt"

echo "8. Bangla text is cut cleanly"
new_project bangla
BN="মেনু অংশে ছবি যোগ করো এবং অর্ডার বোতামটি সবুজ ও বড় করো"
say "$BN $BN $BN $BN $BN $BN"
edit a.txt
edit b.txt
edit c.txt
stop
LINE=$(grep '^1\. "' "$P/PICKUP.md")
check "long request is cut and marked with ..." has "$LINE" '..."'
LEN=$(printf '%s' "$LINE" | wc -c)
check "cut to about 280 bytes (line is $((LEN + 0)) bytes)" [ "$LEN" -le 300 ]
if [ "$HAVE_ICONV" = 1 ]; then
  check "cut line is valid UTF-8" valid_utf8 "$LINE"
  BADCUT=""
  n=1
  while [ "$n" -le 40 ]; do
    PICKUP_REQUEST_CHARS=$n
    export PICKUP_REQUEST_CHARS
    hook session-end "{\"cwd\":\"$P\",\"reason\":\"other\"}"
    LINE=$(grep '^1\. "' "$P/PICKUP.md")
    valid_utf8 "$LINE" || BADCUT="$BADCUT $n"
    n=$((n + 1))
  done
  unset PICKUP_REQUEST_CHARS
  check "valid UTF-8 at every cut length from 1 to 40 bytes${BADCUT:+ (broken at:$BADCUT)}" [ -z "$BADCUT" ]
else
  echo "  skip  UTF-8 validity checks (iconv not available)"
fi
hook prompt "{\"cwd\":\"$P\",\"prompt\":\"escaped ${BS}u09ae${BS}u09c7 and ${BS}u0041\"}"
check "\\u escapes are decoded to real characters" file_has "$(log_of bangla)" "escaped মে and A"

echo "9. Token-like strings are hidden"
new_project secrets
# A made-up token. Deliberately not shaped like any real provider's key, so
# secret scanners (such as GitHub's push protection) don't flag it.
TOKEN=pickupFakeTestToken0123456789abcdefghijklmnop
say "use this key $TOKEN for payments"
say "short words stay: abc123"
edit a.txt
edit b.txt
edit c.txt
stop
check "token replaced with [hidden] in the notebook" file_has "$P/PICKUP.md" "use this key [hidden] for payments"
check "token not in the notebook" file_lacks "$P/PICKUP.md" "$TOKEN"
check "token not in the private log either" file_lacks "$(log_of secrets)" "$TOKEN"
check "normal text is kept" file_has "$P/PICKUP.md" "short words stay: abc123"

echo "10. The off switch"
new_project quiet
: >"$P/.pickup-off"
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\"}"
check "session start prints nothing" is_empty "$OUT"
say "this should not be logged"
for f in a b c d e g h; do edit "$f.txt"; done
stop
check "no reminder" is_empty "$OUT"
check "no notebook created" test ! -f "$P/PICKUP.md"
check "nothing logged" test -z "$(log_of quiet)"
hook pre-edit "{\"cwd\":\"$P\",\"tool_input\":{\"file_path\":\"$P/PICKUP.md\"}}"
check "no automatic approval while off" is_empty "$OUT"

echo "11. Notebook edits without a permission prompt (PICKUP.md only)"
new_project perms
pre() { hook pre-edit "{\"cwd\":\"$P\",\"permission_mode\":\"${2:-default}\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$1\"}}"; }
pre "$P/PICKUP.md"
check "PICKUP.md in the project folder is let through" has "$OUT" '"permissionDecision":"allow"'
pre "$P/index.html"
check "any other file: no decision (normal prompt)" is_empty "$OUT"
pre "$P/sub/PICKUP.md"
check "PICKUP.md in a subfolder: no decision" is_empty "$OUT"
pre "$P/pickup.md"
check "different spelling (pickup.md): no decision" is_empty "$OUT"
pre "$P/../perms/PICKUP.md"
check "path with .. : no decision" is_empty "$OUT"
pre "$T/projects/other/PICKUP.md"
check "another project's PICKUP.md: no decision" is_empty "$OUT"
pre "$P/PICKUP.md" plan
check "plan mode: no decision" is_empty "$OUT"
echo "x" >"$T/elsewhere.txt"
if ln -s "$T/elsewhere.txt" "$P/PICKUP.md" 2>/dev/null && [ -L "$P/PICKUP.md" ]; then
  pre "$P/PICKUP.md"
  check "PICKUP.md that is a link to another file: no decision" is_empty "$OUT"
  rm -f "$P/PICKUP.md"
else
  echo "  skip  link test (this system cannot make symbolic links here)"
fi

echo "12. Broken markers, no needless rewrites, log trimming"
new_project markers
NB=$P/PICKUP.md
printf '# My notes\n\nkeep this line\n<!-- pickup:facts:start -->\nold facts\n' >"$NB"
say "hello"
hook session-end "{\"cwd\":\"$P\",\"reason\":\"other\"}"
check "text outside the markers is kept" file_has "$NB" "keep this line"
check "text after a broken marker is kept" file_has "$NB" "old facts"
N=$(grep -c "pickup:facts:start" "$NB")
M=$(grep -c "pickup:facts:end" "$NB")
check "exactly one fresh facts block" [ "$N$M" = 11 ]
check "fresh block has the request" file_has "$NB" '1. "hello"'
: >"$T/stamp"
sleep 1
hook session-end "{\"cwd\":\"$P\",\"reason\":\"other\"}"
check "nothing changed, so the notebook is not rewritten" test -z "$(find "$NB" -newer "$T/stamp")"
printf 'line one\r\nline two\r\n<!-- pickup:facts:start -->\r\n<!-- pickup:facts:end -->\r\n' >"$NB"
hook session-end "{\"cwd\":\"$P\",\"reason\":\"other\"}"
CR=$(tr -cd '\r' <"$NB" | wc -c)
TOTAL=$(wc -l <"$NB")
check "Windows line endings are kept" [ "$CR" -eq "$TOTAL" ]
LOG=$(log_of markers)
hook session-start "{\"cwd\":\"$P\",\"source\":\"startup\",\"transcript_path\":\"$T/sessions/keep.jsonl\"}"
awk 'BEGIN { for (i = 1; i <= 1200; i++) printf "2026-01-01 10:00:00\tEDIT\tfile%d.txt\n", i }' >>"$LOG"
hook session-end "{\"cwd\":\"$P\",\"reason\":\"other\"}"
N=$(wc -l <"$LOG")
check "long log is trimmed (now $((N + 0)) lines)" [ "$N" -le 520 ]
check "trimming keeps the session record list" file_has "$LOG" "TRANSCRIPT${TAB}$T/sessions/keep.jsonl"
check "trimming keeps the newest lines" file_has "$LOG" "file1200.txt"

echo "13. Always exit 0, even with bad input"
printf 'this is not json' | "$RUNSH" "$SCRIPT" stop >/dev/null 2>&1
check "garbage input" [ $? -eq 0 ]
printf '' | "$RUNSH" "$SCRIPT" session-start >/dev/null 2>&1
check "empty input" [ $? -eq 0 ]
printf '{}' | "$RUNSH" "$SCRIPT" no-such-mode >/dev/null 2>&1
check "unknown mode" [ $? -eq 0 ]

echo
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
