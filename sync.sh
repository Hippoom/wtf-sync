#!/usr/bin/env bash
set -euo pipefail

# WTF Config Sync Script
#
# Usage:
#   ./sync.sh [--config PATH] [--dry-run] [--verbose]
#
# Behavior:
# - Reads key=value from config.conf (same dir by default)
# - Copies character-specific files from prototype character to others
#   within same account and automatically to other accounts
# - Honors addon_excluded for SavedVariables (skips matching addons)
# - Honors char_files_excluded for top-level character files
# - Supports dry-run to preview changes
#
# Config keys:
#   prototype=ACCOUNT/REALM/CHAR or ACCOUNT/CHAR
#   addon_excluded=a,b,c
#   char_files_excluded=AddOns.txt,bindings-cache.wtf
#   only_chars=Name1,Name2 (optional)
#
# Example:
#   prototype={Account}/{Server}/{Char}
#   addon_excluded=pfQuest,ShaguPlates
#   char_files_excluded=AddOns.txt,bindings-cache.wtf,macros-cache.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WTF_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
DRY_RUN=0
VERBOSE=0

log() { echo "[sync] $*"; }
vecho() { [ "$VERBOSE" -eq 1 ] && echo "[sync] $*" || true; }

err() { echo "[sync][error] $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--config PATH] [--dry-run] [--verbose]
EOF
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --verbose|-v)
      VERBOSE=1; shift;;
    --help|-h)
      usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 2;;
  esac
done

[ -f "$CONFIG_FILE" ] || { err "Config not found: $CONFIG_FILE"; exit 1; }

# Read config (simple key=value, ignore comments)
prototype=""
addon_excluded_raw=""
char_files_excluded_raw=""
only_chars_raw=""

while IFS= read -r line || [ -n "$line" ]; do
  # strip comments
  line="${line%%#*}"
  # trim
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  key="${line%%=*}"
  val="${line#*=}"
  case "$key" in
    prototype) prototype="$val";;
    addon_excluded) addon_excluded_raw="$val";;
    char_files_excluded) char_files_excluded_raw="$val";;
    only_chars) only_chars_raw="$val";;
  esac
done < "$CONFIG_FILE"

[ -n "$prototype" ] || { err "prototype is required in config"; exit 1; }

# Normalize list fields: strip spaces only
norm_list() {
  echo "$1" | sed -e 's/[[:space:]]//g'
}

# Bash 3 + set -u safe CSV -> array
split_csv_to_array() {
  # $1 dest array name, $2 csv string
  local __name="$1"; shift || true
  local __csv="$(norm_list "${1:-}")"
  if [ -z "$__csv" ]; then
    eval "$__name=()"
    return
  fi
  local IFS=','
  local __joined=""
  local __tok
  for __tok in $__csv; do
    if [ -z "$__joined" ]; then
      __joined="$(printf '%q' "$__tok")"
    else
      __joined="$__joined $(printf '%q' "$__tok")"
    fi
  done
  eval "$__name=($__joined)"
}

EXCLUDE_ADDONS=()
EXCLUDE_CHAR_FILES=()
ONLY_CHARS=()

split_csv_to_array EXCLUDE_ADDONS "$addon_excluded_raw"
split_csv_to_array EXCLUDE_CHAR_FILES "$char_files_excluded_raw"
split_csv_to_array ONLY_CHARS "$only_chars_raw"

# Parse prototype
proto_acc=""; proto_realm=""; proto_char=""
IFS='/' read -r proto_acc proto_realm proto_char <<< "$prototype"
if [ -z "$proto_char" ]; then
  # Format account/character (no realm)
  proto_char="$proto_realm"; proto_realm=""
fi

[ -n "$proto_acc" ] && [ -n "$proto_char" ] || { err "Invalid prototype: $prototype"; exit 1; }

ACCOUNT_DIR="${WTF_ROOT}/Account"
[ -d "$ACCOUNT_DIR" ] || { err "Account dir not found: $ACCOUNT_DIR"; exit 1; }

# Locate prototype character path
find_proto_paths() {
  if [ -n "$proto_realm" ]; then
    printf '%s\n' "${ACCOUNT_DIR}/${proto_acc}/${proto_realm}/${proto_char}"
  else
    # find first matching realm that contains char
    find "${ACCOUNT_DIR}/${proto_acc}" -mindepth 2 -maxdepth 2 -type d -name "$proto_char" 2>/dev/null | head -n 1
  fi
}

PROTO_PATH="$(find_proto_paths)"
[ -n "$PROTO_PATH" ] && [ -d "$PROTO_PATH" ] || { err "Prototype path not found for $prototype"; exit 1; }

# Files/folders to sync per character
CHAR_ITEMS=(
  "bindings-cache.wtf"
  "camera-settings.txt"
  "chat-cache.txt"
  "layout-cache.txt"
  "macros-cache.txt"
  "macros-local.txt"
  "AddOns.txt"
  "SavedVariables"
)

# Build rsync base args
RSYNC_ARGS=(-a --human-readable)
[ "$DRY_RUN" -eq 1 ] && RSYNC_ARGS+=(--dry-run) && log "Dry-run enabled"
[ "$VERBOSE" -eq 1 ] && RSYNC_ARGS+=(-v)

# Create exclude patterns for SavedVariables
EXCLUDE_OPTS=()
if [ ${#EXCLUDE_ADDONS[@]} -gt 0 ]; then
  for name in "${EXCLUDE_ADDONS[@]}"; do
    # Match exact and prefix variants (e.g., pfQuest.lua, pfQuest-*.lua)
    EXCLUDE_OPTS+=(--exclude="${name}.lua")
    EXCLUDE_OPTS+=(--exclude="${name}-*.lua")
    EXCLUDE_OPTS+=(--exclude="${name}.bak")
    EXCLUDE_OPTS+=(--exclude="${name}-*.bak")
  done
fi

# Build destination accounts list: all accounts except the prototype's
DEST_ACCOUNTS=()
for acc_path in "${ACCOUNT_DIR}"/*; do
  [ -d "$acc_path" ] || continue
  acc_name="$(basename "$acc_path")"
  [ "$acc_name" = "$proto_acc" ] && continue
  DEST_ACCOUNTS+=("$acc_name")
done

# Helper: should include character?
should_include_char() {
  local name="$1"
  if [ ${#ONLY_CHARS[@]} -eq 0 ]; then return 0; fi
  local c
  for c in "${ONLY_CHARS[@]}"; do
    if [ "$c" = "$name" ]; then return 0; fi
  done
  return 1
}

# Helper: should skip char item?
should_skip_item() {
  local item="$1"
  if [ ${#EXCLUDE_CHAR_FILES[@]} -eq 0 ]; then return 1; fi
  local f
  for f in "${EXCLUDE_CHAR_FILES[@]}"; do
    if [ "$item" = "$f" ]; then return 0; fi
  done
  return 1
}

sync_to_account() {
  local src_acc_path="$1" dst_acc_path="$2"
  vecho "Syncing account files -> $dst_acc_path"
  
  # Sync SavedVariables.lua
  local src_path="$src_acc_path/SavedVariables.lua"
  if [ -e "$src_path" ]; then
    rsync "${RSYNC_ARGS[@]}" "$src_path" "$dst_acc_path/"
  else
    vecho "Skipping missing: $src_path"
  fi
  
  # Sync SavedVariables folder
  local src_folder="$src_acc_path/SavedVariables"
  if [ -d "$src_folder" ]; then
    mkdir -p "$dst_acc_path/SavedVariables"
    rsync "${RSYNC_ARGS[@]}" "${EXCLUDE_OPTS[@]}" --delete "$src_folder/" "$dst_acc_path/SavedVariables/"
  else
    vecho "Skipping missing: $src_folder"
  fi
}

sync_to_char() {
  local src_char_path="$1" dst_char_path="$2"
  vecho "Syncing -> $dst_char_path"
  mkdir -p "$dst_char_path"
  local item
  for item in "${CHAR_ITEMS[@]}"; do
    # Skip configured character-level files
    if should_skip_item "$item"; then
      vecho "Excluded by config: $item"
      continue
    fi
    local src_path="$src_char_path/$item"
    local dst_path="$dst_char_path/"
    if [ -e "$src_path" ]; then
      if [ "$item" = "SavedVariables" ]; then
        mkdir -p "$dst_char_path/SavedVariables"
        rsync "${RSYNC_ARGS[@]}" "${EXCLUDE_OPTS[@]}" --delete "$src_path/" "$dst_char_path/SavedVariables/"
      else
        rsync "${RSYNC_ARGS[@]}" "$src_path" "$dst_path"
      fi
    else
      vecho "Skipping missing: $src_path"
    fi
  done
}

# Sync characters within prototype account first
PROTO_ACC_DIR="${ACCOUNT_DIR}/${proto_acc}"
if [ -d "$PROTO_ACC_DIR" ]; then
  log "Syncing characters within prototype account: $proto_acc"
  find "$PROTO_ACC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r realm_dir; do
    realm_name="$(basename "$realm_dir")"
    # character dirs are subdirs that contain layout-cache.txt or SavedVariables, etc.
    find "$realm_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r char_dir; do
      char_name="$(basename "$char_dir")"
      # skip source character path
      if [ "$char_dir" = "$PROTO_PATH" ]; then continue; fi
      # filter by only_chars
      if ! should_include_char "$char_name"; then continue; fi
      log "Syncing character: $proto_acc/$realm_name/$char_name"
      sync_to_char "$PROTO_PATH" "$char_dir"
    done
  done
fi

# Iterate other destination accounts
for acc in "${DEST_ACCOUNTS[@]}"; do
  acc_dir="${ACCOUNT_DIR}/${acc}"
  [ -d "$acc_dir" ] || { vecho "Missing account dir: $acc_dir"; continue; }
  
  log "Syncing account: $acc"
  
  # Sync account-level SavedVariables.lua
  PROTO_ACC_DIR="${ACCOUNT_DIR}/${proto_acc}"
  sync_to_account "$PROTO_ACC_DIR" "$acc_dir"
  
  # realms are direct subdirs except known files
  find "$acc_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r realm_dir; do
    realm_name="$(basename "$realm_dir")"
    # character dirs are subdirs that contain layout-cache.txt or SavedVariables, etc.
    find "$realm_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r char_dir; do
      char_name="$(basename "$char_dir")"
      # skip source character path
      if [ "$char_dir" = "$PROTO_PATH" ]; then continue; fi
      # filter by only_chars
      if ! should_include_char "$char_name"; then continue; fi
      log "Syncing character: $acc/$realm_name/$char_name"
      sync_to_char "$PROTO_PATH" "$char_dir"
    done
  done
done

log "Done."
