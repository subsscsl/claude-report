#!/usr/bin/env bash
# push-retry-queue.sh — durable push-retry queue for headless / scheduled runs.
#
# When a scheduled pipeline commits but can't push (VPN down, network blip,
# enterprise host unreachable), record the pending push to a JSONL queue and
# deliver it at the start of the next successful run.
#
# Sourceable library + CLI. Source it and call the functions, or run directly:
#   push-retry-queue.sh drain
#   push-retry-queue.sh list
#   push-retry-queue.sh enqueue --repo DIR [--branch main] [--remote origin] \
#                               [--source name] [--auth gh:subsscsl]
#
# Queue file: ~/.copilot/state/push-retry.jsonl (one JSON object per line).
# Record shape:
#   {"ts","source","repo_dir","branch","remote","commit","subject","auth"}
#
# AUTH values:
#   gh:<user>  build an http.extraheader from `gh auth token --user <user>`,
#              scheme+host derived from the remote URL (works for github.com
#              and GitHub enterprise).
#   ""         plain `git push` using the repo's ambient credentials.
#
# The library never lets a push failure abort a caller running under `set -e`:
# push_retry_push_or_enqueue always returns 0, and drain is best-effort.

PUSH_RETRY_STATE_DIR="${PUSH_RETRY_STATE_DIR:-$HOME/.copilot/state}"
PUSH_RETRY_QUEUE="${PUSH_RETRY_QUEUE:-$PUSH_RETRY_STATE_DIR/push-retry.jsonl}"
PUSH_RETRY_LOCK="${PUSH_RETRY_LOCK:-$PUSH_RETRY_STATE_DIR/.push-retry.lock}"
PUSH_RETRY_LOCK_STALE_SECS="${PUSH_RETRY_LOCK_STALE_SECS:-120}"

_prq_log() { printf '[push-retry] %s\n' "$*" >&2; }

# --- locking (macOS has no flock) ------------------------------------------
_prq_lock() {
  mkdir -p "$PUSH_RETRY_STATE_DIR" 2>/dev/null || true
  local waited=0
  while ! mkdir "$PUSH_RETRY_LOCK" 2>/dev/null; do
    # Break a stale lock left by a crashed run.
    local age
    if age=$(_prq_lock_age) && [ "$age" -ge "$PUSH_RETRY_LOCK_STALE_SECS" ]; then
      rm -rf "$PUSH_RETRY_LOCK" 2>/dev/null || true
      continue
    fi
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$PUSH_RETRY_LOCK_STALE_SECS" ]; then
      _prq_log "could not acquire lock after ${waited}s — proceeding without it"
      return 0
    fi
  done
  return 0
}

_prq_lock_age() {
  [ -d "$PUSH_RETRY_LOCK" ] || return 1
  local now mtime
  now=$(date +%s)
  # stat is BSD on macOS, GNU on Linux — try both.
  mtime=$(stat -f %m "$PUSH_RETRY_LOCK" 2>/dev/null || stat -c %Y "$PUSH_RETRY_LOCK" 2>/dev/null) || return 1
  printf '%s' "$((now - mtime))"
}

_prq_unlock() { rm -rf "$PUSH_RETRY_LOCK" 2>/dev/null || true; }

# --- the actual push --------------------------------------------------------
# push_retry_try_push REPO BRANCH REMOTE AUTH  -> 0 on success, non-zero on fail
push_retry_try_push() {
  local repo="$1" branch="${2:-main}" remote="${3:-origin}" auth="${4:-}"
  [ -d "$repo/.git" ] || [ -f "$repo/.git" ] || { _prq_log "not a git repo: $repo"; return 2; }
  (
    cd "$repo" || exit 1
    case "$auth" in
      gh:*)
        local ghuser="${auth#gh:}" token url base hdr
        token=$(gh auth token --user "$ghuser" 2>/dev/null)
        if [ -n "$token" ]; then
          url=$(git remote get-url "$remote" 2>/dev/null)
          base=$(printf '%s' "$url" | sed -E 's#(https?://[^/]+/).*#\1#')
          [ -n "$base" ] || base="https://github.com/"
          hdr="Authorization: basic $(printf 'x-access-token:%s' "$token" | base64)"
          git -c "http.${base}.extraheader=$hdr" push "$remote" "$branch"
        else
          git push "$remote" "$branch"
        fi
        ;;
      *)
        git push "$remote" "$branch"
        ;;
    esac
  )
}

# --- enqueue ----------------------------------------------------------------
# push_retry_enqueue REPO BRANCH REMOTE SOURCE AUTH
push_retry_enqueue() {
  local repo="$1" branch="${2:-main}" remote="${3:-origin}" source="${4:-unknown}" auth="${5:-}"
  local commit subject
  commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")
  subject=$(git -C "$repo" log -1 --format=%s 2>/dev/null || echo "")
  _prq_lock
  mkdir -p "$PUSH_RETRY_STATE_DIR" 2>/dev/null || true
  PRQ_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" PRQ_SRC="$source" PRQ_REPO="$repo" \
  PRQ_BRANCH="$branch" PRQ_REMOTE="$remote" PRQ_COMMIT="$commit" \
  PRQ_SUBJECT="$subject" PRQ_AUTH="$auth" PUSH_RETRY_QUEUE="$PUSH_RETRY_QUEUE" \
  python3 -c '
import json, os
rec = {
    "ts": os.environ["PRQ_TS"],
    "source": os.environ["PRQ_SRC"],
    "repo_dir": os.environ["PRQ_REPO"],
    "branch": os.environ["PRQ_BRANCH"],
    "remote": os.environ["PRQ_REMOTE"],
    "commit": os.environ["PRQ_COMMIT"],
    "subject": os.environ["PRQ_SUBJECT"],
    "auth": os.environ["PRQ_AUTH"],
}
with open(os.environ["PUSH_RETRY_QUEUE"], "a") as f:
    f.write(json.dumps(rec) + "\n")
' 2>/dev/null
  local rc=$?
  _prq_unlock
  if [ "$rc" -eq 0 ]; then
    _prq_log "queued push: $source $repo ($branch) ${commit:0:8}"
  else
    _prq_log "FAILED to queue push for $repo — record lost"
  fi
  return "$rc"
}

# --- convenience: try, enqueue on failure, always return 0 ------------------
# push_retry_push_or_enqueue REPO BRANCH REMOTE SOURCE AUTH
push_retry_push_or_enqueue() {
  local repo="$1" branch="${2:-main}" remote="${3:-origin}" source="${4:-unknown}" auth="${5:-}"
  if push_retry_try_push "$repo" "$branch" "$remote" "$auth"; then
    _prq_log "pushed: $source $repo ($branch)"
    return 0
  fi
  _prq_log "push failed: $source $repo ($branch) — enqueuing for retry"
  push_retry_enqueue "$repo" "$branch" "$remote" "$source" "$auth" || true
  return 0
}

# --- drain ------------------------------------------------------------------
# push_retry_drain -> best-effort; pushes each queued entry, keeps failures.
push_retry_drain() {
  [ -s "$PUSH_RETRY_QUEUE" ] || return 0
  _prq_lock
  local tmp survivors=0 drained=0 total=0
  tmp=$(mktemp "${PUSH_RETRY_QUEUE}.XXXXXX") || { _prq_unlock; return 0; }

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    total=$((total + 1))
    local repo branch remote auth src
    repo=$(printf '%s' "$line"   | jq -r '.repo_dir // ""' 2>/dev/null)
    branch=$(printf '%s' "$line" | jq -r '.branch   // "main"' 2>/dev/null)
    remote=$(printf '%s' "$line" | jq -r '.remote   // "origin"' 2>/dev/null)
    auth=$(printf '%s' "$line"   | jq -r '.auth     // ""' 2>/dev/null)
    src=$(printf '%s' "$line"    | jq -r '.source   // "unknown"' 2>/dev/null)

    if [ -z "$repo" ]; then
      _prq_log "dropping malformed queue entry"
      continue
    fi
    if push_retry_try_push "$repo" "$branch" "$remote" "$auth"; then
      drained=$((drained + 1))
      _prq_log "drained: $src $repo ($branch)"
    else
      survivors=$((survivors + 1))
      printf '%s\n' "$line" >> "$tmp"
      _prq_log "still failing, kept: $src $repo ($branch)"
    fi
  done < "$PUSH_RETRY_QUEUE"

  if [ "$survivors" -eq 0 ]; then
    rm -f "$tmp" "$PUSH_RETRY_QUEUE"
  else
    mv "$tmp" "$PUSH_RETRY_QUEUE"
  fi
  _prq_unlock
  [ "$total" -gt 0 ] && _prq_log "drain complete: $drained delivered, $survivors pending"
  return 0
}

# --- CLI --------------------------------------------------------------------
_prq_cli() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    drain) push_retry_drain ;;
    list)
      if [ -s "$PUSH_RETRY_QUEUE" ]; then cat "$PUSH_RETRY_QUEUE"; else echo "(queue empty)"; fi
      ;;
    enqueue)
      local repo="" branch="main" remote="origin" source="cli" auth=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo) repo="$2"; shift 2 ;;
          --branch) branch="$2"; shift 2 ;;
          --remote) remote="$2"; shift 2 ;;
          --source) source="$2"; shift 2 ;;
          --auth) auth="$2"; shift 2 ;;
          *) _prq_log "unknown arg: $1"; return 2 ;;
        esac
      done
      [ -n "$repo" ] || { _prq_log "enqueue: --repo required"; return 2; }
      push_retry_enqueue "$repo" "$branch" "$remote" "$source" "$auth"
      ;;
    *)
      cat >&2 <<'USAGE'
usage: push-retry-queue.sh <command>
  drain                       attempt all queued pushes; keep failures
  list                        print the raw queue
  enqueue --repo DIR [--branch main] [--remote origin]
          [--source name] [--auth gh:<user>]
USAGE
      return 2
      ;;
  esac
}

# Run CLI only when executed directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _prq_cli "$@"
fi
