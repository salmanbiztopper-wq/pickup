#!/bin/sh
# Pickup: keeps a plain-English project notebook (PICKUP.md) so Claude never
# loses its place, even after compaction or in a brand-new session.
#
# Claude Code runs this one script for every hook, with the hook name as the
# first word:
#
#   sh pickup.sh session-start   a session opens, resumes, clears or compacts
#   sh pickup.sh prompt          the user sends a message
#   sh pickup.sh pre-edit        Claude is about to write or edit a file
#   sh pickup.sh post-edit       Claude has just written or edited a file
#   sh pickup.sh stop            Claude is about to finish its reply
#   sh pickup.sh pre-compact     the conversation is about to be compacted
#   sh pickup.sh session-end     the session is closing
#
# Claude Code sends details about the event as JSON on standard input.
#
# Ground rules this script follows:
# - Plain POSIX sh and awk only. No jq, Node or Python, because many users
#   don't have them. The awk code avoids features that only one awk has, so it
#   runs the same on Mac (BWK awk), Linux (mawk or gawk) and Git Bash (gawk).
# - It always exits 0. Any other exit code shows the user an error notice or
#   blocks Claude. To ask Claude for something, it prints JSON instead.
# - The raw activity log lives in the plugin's private data folder, never in
#   the project. The only thing it writes into the project is PICKUP.md.

# ---------------------------------------------------------------------------
# Settings. Each one can be changed with the environment variable named next
# to it. Nothing else in the script needs editing.
# ---------------------------------------------------------------------------
SAVE_AFTER_EDITS=${PICKUP_SAVE_AFTER_EDITS:-6} # edits before Claude is asked to update the notebook (0 turns reminders off)
FACT_REQUESTS=${PICKUP_FACT_REQUESTS:-5}       # how many recent requests the facts block shows
FACT_FILES=${PICKUP_FACT_FILES:-10}            # how many recently changed files the facts block shows
REQUEST_CHARS=${PICKUP_REQUEST_CHARS:-280}     # each request is cut to about this many bytes
CONTEXT_BYTES=${PICKUP_CONTEXT_BYTES:-9000}    # most text loaded into Claude at session start
NOTEBOOK=${PICKUP_NOTEBOOK:-PICKUP.md}         # notebook file name, inside the project folder
OFF_FILE=${PICKUP_OFF_FILE:-.pickup-off}       # if this file exists in a project, Pickup stays quiet there
LOG_KEEP=500                                   # lines kept when the private log is trimmed

# If a number setting isn't a whole number, fall back to its default.
case $SAVE_AFTER_EDITS in '' | *[!0-9]*) SAVE_AFTER_EDITS=6 ;; esac
case $FACT_REQUESTS in '' | *[!0-9]*) FACT_REQUESTS=5 ;; esac
case $FACT_FILES in '' | *[!0-9]*) FACT_FILES=10 ;; esac
case $REQUEST_CHARS in '' | *[!0-9]*) REQUEST_CHARS=280 ;; esac
case $CONTEXT_BYTES in '' | *[!0-9]*) CONTEXT_BYTES=9000 ;; esac

# The notebook is created a little earlier than the first reminder would come,
# so it appears after the first real piece of work: half the threshold.
CREATE_AFTER_EDITS=$(((SAVE_AFTER_EDITS + 1) / 2))

# Byte-by-byte text handling everywhere, the same on every system.
LC_ALL=C
export LC_ALL

MODE=${1:-}
case $MODE in
session-start | prompt | pre-edit | post-edit | stop | pre-compact | session-end) ;;
*) exit 0 ;;
esac

# Where the plugin's own files are (for the notebook template).
case $0 in
*/*) HERE=${0%/*} ;;
*) HERE=. ;;
esac
PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-$HERE/..}
TEMPLATE=$PLUGIN_ROOT/templates/PICKUP.md

# ---------------------------------------------------------------------------
# Shared awk helpers. Every awk program below starts with these.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
AWKLIB='
function init_lib(   i) {
  # Does this awk count bytes (gawk, mawk, older BWK awk with LC_ALL=C) or
  # whole characters (newer BWK awk)? The UTF-8 cutting below needs to know.
  BYTEMODE = (length("\303\251") == 2)
  # Printable ASCII, for decoding \u escapes without relying on %c quirks.
  ASCII = ""
  for (i = 32; i < 127; i++) ASCII = ASCII sprintf("%c", i)
  # A token-like string: 32 or more letters, digits or _+/=- in a row.
  # Built by repetition because some awks do not support {32,}.
  TOKRE = ""
  for (i = 0; i < 32; i++) TOKRE = TOKRE "[A-Za-z0-9_+/=-]"
  TOKRE = TOKRE "[A-Za-z0-9_+/=-]*"
  MSTART = "<!-- pickup:facts:start -->"
  MEND = "<!-- pickup:facts:end -->"
}

# Find "key": in a JSON text and return its value. Strings are decoded,
# true/false/null/numbers are returned as written. Returns "" if missing.
# cap limits how much of a long string is decoded.
function json_get(s, key, cap,    pat, p, r) {
  pat = "\"" key "\""
  while ((p = index(s, pat)) > 0) {
    s = substr(s, p + length(pat))
    if (!match(substr(s, 1, 200), /^[ \t\r\n]*:[ \t\r\n]*/)) continue
    r = substr(s, RLENGTH + 1, cap * 6 + 16)
    if (substr(r, 1, 1) == "\"") return json_str(substr(r, 2), cap)
    if (match(r, /^[A-Za-z0-9.+-]+/)) return substr(r, 1, RLENGTH)
    return ""
  }
  return ""
}

# Decode a JSON string body (the part after the opening quote) up to the
# first unescaped quote. Line breaks and tabs become spaces.
function json_str(r, cap,    out, c, e) {
  out = ""
  while (length(out) < cap) {
    if (!match(r, /[\\"]/)) return out r
    out = out substr(r, 1, RSTART - 1)
    c = substr(r, RSTART, 1)
    r = substr(r, RSTART + 1)
    if (c == "\"") return out
    e = substr(r, 1, 1)
    r = substr(r, 2)
    if (e == "u") { out = out json_u(substr(r, 1, 4)); r = substr(r, 5) }
    else if (e == "n" || e == "r" || e == "t" || e == "b" || e == "f") out = out " "
    else out = out e
  }
  return out
}

# Turn a \uXXXX escape into the character it stands for (UTF-8).
function json_u(h,    i, d, n) {
  n = 0
  for (i = 1; i <= 4; i++) {
    d = index("0123456789abcdef", tolower(substr(h, i, 1)))
    if (!d) return "?"
    n = n * 16 + d - 1
  }
  if (n < 32 || n == 127) return " "
  if (n < 127) return substr(ASCII, n - 31, 1)
  if (n >= 55296 && n < 57344) return "?"
  if (!BYTEMODE) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
  return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
}

# Squeeze all runs of spaces, tabs and line breaks into single spaces.
function squash(s) {
  gsub(/[ \t\r\n]+/, " ", s)
  sub(/^ /, "", s)
  sub(/ $/, "", s)
  return s
}

# Replace anything that looks like a password, key or token with [hidden].
function hide_tokens(s) {
  gsub(TOKRE, "[hidden]", s)
  return s
}

# Cut text to about n bytes without breaking a character in half. This
# matters for Bangla and other non-Latin scripts, where one character is
# several bytes: step back over UTF-8 continuation bytes, then drop a lead
# byte whose sequence would be incomplete.
function cut_utf8(s, n,    t, i, k, c, need) {
  if (length(s) <= n) return s
  t = substr(s, 1, n)
  if (BYTEMODE) {
    i = n
    k = 0
    while (i > 0) {
      c = substr(t, i, 1)
      if (c >= "\200" && c < "\300") { i--; k++ } else break
    }
    if (i == 0) t = ""
    else {
      c = substr(t, i, 1)
      if (c >= "\300") {
        need = 1
        if (c >= "\340") need = 2
        if (c >= "\360") need = 3
        if (k < need) t = substr(t, 1, i - 1)
      } else if (k > 0) t = substr(t, 1, i)
    }
  }
  sub(/ +$/, "", t)
  return t "..."
}

# Put a path in one standard form so the same file always compares equal:
# backslashes become slashes, and C:/x, /c/x and /cygdrive/c/x all become /c/x.
function norm_path(p) {
  gsub(/\\/, "/", p)
  if (p ~ /^[A-Za-z]:/) p = "/" substr(p, 1, 1) substr(p, 3)
  sub(/^\/cygdrive\//, "/", p)
  if (p ~ /^\/[A-Za-z]\// || p ~ /^\/[A-Za-z]$/) p = "/" tolower(substr(p, 2, 1)) substr(p, 3)
  gsub(/\/+/, "/", p)
  while (p ~ /\/\.\//) sub(/\/\.\//, "/", p)
  if (length(p) > 1) sub(/\/$/, "", p)
  return p
}
'

# ---------------------------------------------------------------------------
# Step 1: read the hook's JSON and work out the project and its log.
# One awk run prints these lines, in this order:
#   project folder, standard form of it, cleaned folder name, data folder,
#   source, stop_hook_active, trigger, edited-file kind, edited-file path
#   relative to the project, whether the edited file is exactly the
#   notebook (same spelling), the permission mode, the session record path,
#   and the cleaned-up request (last, because it is the only long line).
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
PARSE='
BEGIN { init_lib() }
{ doc = doc $0 "\n" }
END {
  root = ENVIRON["CLAUDE_PROJECT_DIR"]
  if (root == "") root = json_get(doc, "cwd", 4096)
  if (root == "") root = ENVIRON["PWD"]
  gsub(/\\/, "/", root)
  if (length(root) > 1) sub(/\/$/, "", root)
  nroot = norm_path(root)

  # Folder name for the private log folder: letters, digits, . _ - only.
  name = nroot
  sub(/.*\//, "", name)
  gsub(/[^A-Za-z0-9._-]/, "-", name)
  name = substr(name, 1, 40)
  if (name == "") name = "project"

  data = ENVIRON["CLAUDE_PLUGIN_DATA"]
  if (data == "") data = ENVIRON["HOME"] "/.claude/plugins/data/pickup-pickup"
  gsub(/\\/, "/", data)

  # Which file was edited? NotebookEdit may use notebook_path.
  kind = ""
  rel = ""
  exact = 0
  f = json_get(doc, "notebook_path", 4096)
  if (f == "") f = json_get(doc, "file_path", 4096)
  if (f != "") {
    nf = norm_path(f)
    nbname = ENVIRON["PICKUP_NB"]
    gsub(/\\/, "/", nbname)
    sub(/^\.\//, "", nbname)
    nb = norm_path(nroot "/" nbname)
    # Same spelling, letter for letter (only the drive letter may differ in
    # case). Used before letting a notebook edit through without a prompt.
    exact = (nf == nb && index(nbname, "..") == 0)
    if (tolower(nf) == tolower(nb)) kind = "notebook"
    else if (index(tolower(nf), tolower(nroot) "/") == 1) {
      kind = "edit"
      rel = substr(nf, length(nroot) + 2)
    } else kind = "outside"
  }

  # The request: one line, secrets hidden, cut to 1000 bytes. It is cut
  # again, shorter, when it goes into the notebook.
  pr = cut_utf8(hide_tokens(squash(json_get(doc, "prompt", 4000))), 1000)

  print root
  print nroot
  print name
  print data
  print json_get(doc, "source", 64)
  print json_get(doc, "stop_hook_active", 16)
  print json_get(doc, "trigger", 64)
  print kind
  print rel
  print exact
  print json_get(doc, "permission_mode", 64)
  # Where Claude Code keeps this session full record (a .jsonl file).
  tp = json_get(doc, "transcript_path", 4096)
  gsub(/\\/, "/", tp)
  print tp
  print pr
}
'

PICKUP_NB=$NOTEBOOK
export PICKUP_NB
PARSED=$(awk "$AWKLIB$PARSE" 2>/dev/null)
{
  IFS= read -r ROOT
  IFS= read -r CANON
  IFS= read -r NAME
  IFS= read -r DATA
  IFS= read -r SOURCE
  IFS= read -r ACTIVE
  IFS= read -r TRIGGER
  IFS= read -r KIND
  IFS= read -r REL
  IFS= read -r EXACT
  IFS= read -r PERM_MODE
  IFS= read -r TRANSCRIPT
  IFS= read -r PROMPT
} <<EOF
$PARSED
EOF

[ -n "$ROOT" ] || exit 0

# Off switch: an empty .pickup-off file in the project silences Pickup there.
[ -e "$ROOT/$OFF_FILE" ] && exit 0

NB=$ROOT/$NOTEBOOK

# The private log folder: cleaned folder name plus a checksum of the path,
# so two projects with the same folder name never share a log.
# shellcheck disable=SC2046
set -- $(printf '%s' "$CANON" | cksum)
PDIR=$DATA/projects/$NAME-${1:-0}
LOG=$PDIR/activity.log

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Add one line to the private log: time, event type, details.
log_event() {
  [ -d "$PDIR" ] || mkdir -p "$PDIR" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >>"$LOG" 2>/dev/null
}

# Count edits logged since the notebook was last saved or Claude was last
# reminded, whichever came later.
edits_since_save() {
  if [ -f "$LOG" ]; then
    awk '{ split($0, f, "\t") }
      f[2] == "SAVE" || f[2] == "NUDGE" { n = 0 }
      f[2] == "EDIT" { n++ }
      END { print n + 0 }' "$LOG" 2>/dev/null
  else
    echo 0
  fi
}

# Rebuild the facts block at the bottom of the notebook from the private log.
# Only the part between the pickup:facts markers is replaced. If the markers
# are missing or broken, stray marker lines are removed and a fresh block is
# added at the end; nothing else in the notebook is ever deleted. The file is
# only rewritten when something actually changed, and it is written in place
# so its permissions stay the same.
# shellcheck disable=SC2016
FACTS='
BEGIN {
  init_lib()
  nr = 0
  while ((getline line < logf) > 0) L[++nr] = line
  close(logf)
}
{ NB[++nl] = $0 }
END {
  # Collect the newest requests and changed files, newest first.
  np = 0
  nfi = 0
  updated = ""
  for (i = nr; i >= 1; i--) {
    n = split(L[i], f, "\t")
    if (n < 3) continue
    if (f[2] == "PROMPT" && np < maxreq) {
      t = f[3]
      for (j = 4; j <= n; j++) t = t " " f[j]
      t = cut_utf8(hide_tokens(t), reqchars)
      gsub(/pickup:facts:/, "pickup-facts-", t)
      if (t == "" || (t in seenp)) continue
      seenp[t] = 1
      P[++np] = t
      if (updated == "") updated = substr(f[1], 1, 16)
    } else if (f[2] == "EDIT" && nfi < maxfiles) {
      t = f[3]
      gsub(/pickup:facts:/, "pickup-facts-", t)
      if (t == "" || (t in seenf)) continue
      seenf[t] = 1
      F[++nfi] = t
      if (updated == "") updated = substr(f[1], 1, 16)
    }
  }
  if (updated == "") updated = "nothing recorded yet"

  nb = 0
  B[++nb] = MSTART
  B[++nb] = "## Last session facts"
  B[++nb] = "_Copied automatically by Pickup from the session record. Claude does not write this part._"
  B[++nb] = ""
  B[++nb] = "Updated: " updated
  B[++nb] = ""
  B[++nb] = "**Your latest requests (newest first)**"
  if (np == 0) B[++nb] = "_None recorded yet._"
  for (i = 1; i <= np; i++) B[++nb] = i ". \"" P[i] "\""
  B[++nb] = ""
  B[++nb] = "**Files changed recently (newest first)**"
  if (nfi == 0) B[++nb] = "_None recorded yet._"
  for (i = 1; i <= nfi; i++) B[++nb] = "- " F[i]
  B[++nb] = MEND

  # Keep Windows line endings if the notebook uses them.
  eol = ""
  if (nl > 0 && NB[1] ~ /\r$/) eol = "\r"

  # Find the markers.
  ns = 0
  ne = 0
  for (i = 1; i <= nl; i++) {
    t = NB[i]
    sub(/\r$/, "", t)
    sub(/^[ \t]+/, "", t)
    sub(/[ \t]+$/, "", t)
    mark[i] = (t == MSTART || t == MEND)
    if (t == MSTART) { ns++; sp = i }
    if (t == MEND) { ne++; ep = i }
  }

  if (ns == 1 && ne == 1 && sp < ep) {
    for (i = 1; i < sp; i++) print NB[i]
    for (i = 1; i <= nb; i++) print B[i] eol
    for (i = ep + 1; i <= nl; i++) print NB[i]
  } else {
    last = nl
    while (last > 0) {
      t = NB[last]
      sub(/\r$/, "", t)
      if (mark[last] || t ~ /^[ \t]*$/) last--
      else break
    }
    for (i = 1; i <= last; i++) if (!mark[i]) print NB[i]
    if (last > 0) print eol
    for (i = 1; i <= nb; i++) print B[i] eol
  }
}
'

refresh_facts() {
  [ -f "$NB" ] || return 0
  [ -d "$PDIR" ] || mkdir -p "$PDIR" 2>/dev/null || return 0
  tmp=$PDIR/notebook.$$.tmp
  # BINMODE=3 stops Windows gawk from silently dropping the carriage returns
  # of a notebook saved with Windows line endings. Other awks ignore it.
  if awk -v BINMODE=3 -v logf="$LOG" -v maxreq="$FACT_REQUESTS" -v maxfiles="$FACT_FILES" \
    -v reqchars="$REQUEST_CHARS" "$AWKLIB$FACTS" "$NB" >"$tmp" 2>/dev/null &&
    [ -s "$tmp" ] && ! cmp -s "$tmp" "$NB"; then
    cat "$tmp" >"$NB" 2>/dev/null
  fi
  rm -f "$tmp" 2>/dev/null
}

# Text Claude reads at session start. Written as plain facts about the
# project and what the user expects, not as system-style commands.
intro_with_notebook() {
  printf '%s\n' "Pickup is installed for this project. $NOTEBOOK in the project folder is the project notebook: a plain-English page with what is being built, the plan, decisions and their reasons, the next step, things to watch out for, and questions waiting on the user. It lets work continue across sessions and after compaction without losing details."
  printf '\n'
  printf '%s\n' "- The user can read and edit $NOTEBOOK. If they have edited it by hand, their version is the one to follow."
  printf '%s\n' "- The block between the pickup:facts markers is copied automatically by Pickup from the session record: the user's latest requests word for word, and the files changed recently. Claude leaves that block as it is."
  printf '%s\n' "- After real progress (a finished step, a decision, a change of plan, something that broke), the user expects Claude to update $NOTEBOOK: tick finished plan steps, add decisions with their reasons, rewrite Next step, add traps to Watch out, and set Last updated. Short, plain sentences."
  printf '%s\n' "- Pickup commands: /pickup:save updates the notebook now, /pickup:status reports where things stand, /pickup:handoff prepares a clean restart."
}

intro_without_notebook() {
  printf '%s\n' "Pickup is installed for this project. Pickup keeps a plain-English project notebook called $NOTEBOOK in the project folder, so work can continue across sessions and after compaction without losing details. The notebook does not exist yet. Pickup creates it after the first real piece of work, or when the user asks to save progress. Pickup commands: /pickup:save updates the notebook, /pickup:status reports where things stand, /pickup:handoff prepares a clean restart."
}

# After compaction the list of available commands is not loaded again, so
# plain phrases are spelled out here.
plain_phrases() {
  printf '%s\n' "If the user asks to save progress, Claude updates $NOTEBOOK directly. If the user asks where things stand, Claude reads $NOTEBOOK and answers from it. This works even if the Pickup commands are not in Claude's command list."
}

situation() {
  case $SOURCE in
  compact)
    printf '%s\n' "The conversation was just compacted into a summary, so some details may be missing from it. The notebook below holds the saved state. Before continuing, Claude checks the Next step section against what it was doing. In its next reply, Claude tells the user in one line that if anything feels off, a clean restart is available: type /pickup:handoff, then open a new chat in this same folder (this chat stays as it is), or type /clear to start fresh here."
    printf '\n'
    plain_phrases
    ;;
  resume | fork)
    printf '%s\n' "This session was resumed, so the earlier conversation is still available and no opening status line is needed. The notebook below is the latest saved state."
    ;;
  *)
    printf '%s\n' "This is a fresh session. The user expects Claude to begin its first reply with one plain sentence on where the project stands, based on the notebook below (for example: Last time we finished the menu. Next is the order form.), and then handle their request."
    ;;
  esac
}

# ---------------------------------------------------------------------------
# The six modes
# ---------------------------------------------------------------------------
case $MODE in

session-start)
  # Remember where this session's full record is kept, once per record.
  # Version 2 (Recall) will search these records for exact words from
  # older chats, so it never has to guess where they are.
  if [ -n "$TRANSCRIPT" ] &&
    ! awk -v tp="$TRANSCRIPT" '{ split($0, f, "\t") } f[2] == "TRANSCRIPT" && f[3] == tp { found = 1 } END { exit !found }' "$LOG" 2>/dev/null; then
    log_event TRANSCRIPT "$TRANSCRIPT"
  fi

  # Refresh the facts, then load how Pickup works plus the notebook itself
  # into Claude's context. Plain output from this hook becomes context.
  if [ ! -f "$NB" ]; then
    intro_without_notebook
    if [ "$SOURCE" = compact ]; then
      printf '\n'
      plain_phrases
    fi
    exit 0
  fi
  refresh_facts
  HEAD=$(
    intro_with_notebook
    printf '\n'
    situation
  )
  CUT_NOTE="----- $NOTEBOOK was cut here because it is longer than Pickup loads at session start. The full notebook is in $NOTEBOOK. Claude reads the whole file before relying on it, and the next time it saves, folds finished items into a one-line summary so the notebook stays short. -----"
  # Hook output over 10,000 characters is replaced by a short preview, so
  # keep everything under CONTEXT_BYTES.
  BUDGET=$((CONTEXT_BYTES - ${#HEAD} - ${#CUT_NOTE} - 200))
  SIZE=$(wc -c <"$NB" 2>/dev/null)
  SIZE=$((${SIZE:-0} + 0))
  printf '%s\n\n' "$HEAD"
  printf '%s\n' "----- Start of $NOTEBOOK -----"
  if [ "$SIZE" -le "$BUDGET" ]; then
    cat "$NB"
    printf '\n%s\n' "----- End of $NOTEBOOK -----"
  else
    # Load the start of the notebook, cut at the end of a whole line.
    [ "$BUDGET" -gt 0 ] || BUDGET=0
    head -c "$BUDGET" "$NB" | awk 'NR > 1 { print prev } { prev = $0 }'
    printf '%s\n' "$CUT_NOTE"
  fi
  ;;

prompt)
  # Note the request in the private log. Print nothing, so it costs no
  # context. Bare slash commands like /pickup:save are not requests.
  case $PROMPT in
  '' | /*' '*) ;;
  /*) exit 0 ;;
  esac
  [ -n "$PROMPT" ] && log_event PROMPT "$PROMPT"
  ;;

pre-edit)
  # Let Claude update the notebook without a permission prompt. Only for
  # PICKUP.md in this project folder, spelled exactly, and never for any
  # other file. The user's own deny and ask rules are still checked by
  # Claude Code after this, so they always win. Not in plan mode, where
  # nothing should be edited, and not when PICKUP.md is a link that could
  # point to some other file.
  [ "$KIND" = notebook ] && [ "$EXACT" = 1 ] || exit 0
  [ "$PERM_MODE" = plan ] && exit 0
  [ -L "$NB" ] && exit 0
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Pickup lets Claude update the project notebook without asking."}}'
  ;;

post-edit)
  # A save of the notebook resets the edit count and refreshes the facts.
  # Any other file inside the project is logged as an edit.
  case $KIND in
  notebook)
    log_event SAVE "$NOTEBOOK"
    refresh_facts
    ;;
  edit)
    log_event EDIT "$REL"
    ;;
  esac
  ;;

stop)
  # Loop guard: if Claude is already continuing because of a stop hook,
  # let it finish.
  [ "$ACTIVE" = true ] && exit 0
  [ "$SAVE_AFTER_EDITS" -gt 0 ] || exit 0
  COUNT=$(edits_since_save)
  COUNT=$((${COUNT:-0} + 0))
  if [ ! -f "$NB" ]; then
    # First real piece of work: create the notebook from the template and
    # ask Claude to fill it in.
    [ "$COUNT" -ge "$CREATE_AFTER_EDITS" ] || exit 0
    [ -f "$TEMPLATE" ] || exit 0
    cat "$TEMPLATE" >"$NB" 2>/dev/null || exit 0
    refresh_facts
    log_event NUDGE created
    printf '{"decision":"block","reason":"%s"}\n' "Pickup created $NOTEBOOK in the project folder from its template, because real work has started. Please fill in each section from what you know about this project so far, in short plain English, and set Last updated. Leave the block between the pickup:facts markers as it is, since Pickup fills that part. Then end your reply with one line telling the user that the project notebook now exists."
  else
    [ "$COUNT" -ge "$SAVE_AFTER_EDITS" ] || exit 0
    log_event NUDGE "$COUNT"
    printf '{"decision":"block","reason":"%s"}\n' "$COUNT edits have been made since $NOTEBOOK was last updated. Please bring $NOTEBOOK up to date now: tick finished plan steps, add new decisions with their reasons, rewrite Next step, add anything to Watch out, and set Last updated. Leave the block between the pickup:facts markers as it is. Then finish your reply as normal."
  fi
  ;;

pre-compact)
  # Too late to ask Claude for anything here, so just make sure the facts
  # are current before the summary is written.
  log_event COMPACT "${TRIGGER:-unknown}"
  refresh_facts
  ;;

session-end)
  # Keep this quick: Claude Code gives closing hooks about 1.5 seconds.
  refresh_facts
  # Trim the private log when it gets long: keep the newest LOG_KEEP
  # lines, plus every TRANSCRIPT line (the list of this project's records).
  if [ -f "$LOG" ]; then
    LINES=$(wc -l <"$LOG" 2>/dev/null)
    if [ $((${LINES:-0} + 0)) -gt $((LOG_KEEP * 2)) ]; then
      awk -v keep="$LOG_KEEP" '
        { split($0, f, "\t") }
        NR == FNR { if (f[2] != "TRANSCRIPT") total++; next }
        f[2] == "TRANSCRIPT" { print; next }
        { seen++; if (seen > total - keep) print }
      ' "$LOG" "$LOG" >"$LOG.tmp" 2>/dev/null && cat "$LOG.tmp" >"$LOG"
      rm -f "$LOG.tmp" 2>/dev/null
    fi
  fi
  ;;

esac

exit 0
