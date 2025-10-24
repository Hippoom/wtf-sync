# WTF Config Sync

A script to synchronize World of Warcraft addon variables and UI layouts across multiple characters and accounts.

## Features

- **Cross-character sync**: Copy configuration from a prototype character to all other characters
- **Cross-account sync**: Automatically sync to all accounts except the prototype account
- **Addon exclusions**: Skip specific addons (e.g., pfQuest) when syncing SavedVariables
- **Character file exclusions**: Skip specific character files (e.g., AddOns.txt, bindings-cache.wtf)
- **Account-level sync**: Sync SavedVariables.lua and SavedVariables folder at account level
- **Progress tracking**: Clear progress messages showing which account/character is being synced
- **Dry-run mode**: Preview changes without applying them

## Files

- `config.conf` - Configuration file (shared by both versions)
- `sync.sh` - Bash script for macOS/Linux
- `sync.ps1` - PowerShell script for Windows 10/11
- `sync.bat` - Windows batch wrapper for easier execution

## Configuration

Edit `config.conf` to set up your sync preferences:

```ini
# Config for WTF configuration sync
# Lines are key=value. Comments start with #

# prototype: The source character to copy FROM.
#   Format: account/realm/character (recommended) or account/character
prototype={Account}/{Server}/{Char}

# addon_excluded: Comma-separated list of addon names to skip when copying
# SavedVariables. Names are matched against file basenames without extensions,
# and also as prefixes (e.g. pfQuest matches pfQuest.lua and pfQuest-turtle.lua).
addon_excluded=pfQuest

# char_files_excluded: Comma-separated list of character-level files
# to skip when copying (e.g., AddOns.txt, bindings-cache.wtf, macros-cache.txt).
char_files_excluded=AddOns.txt,bindings-cache.wtf,macros-cache.txt

# only_chars: Comma-separated character names to restrict the
# destination set. If empty, applies to all characters in target accounts.
# only_chars=Horrag,Yelmor
```

## Usage

### macOS/Linux (Bash)

```bash
# Basic sync
bash sync.sh

# Dry-run to preview changes
bash sync.sh --dry-run

# Verbose output
bash sync.sh -v

# Dry-run with verbose output
bash sync.sh --dry-run -v

# Custom config file
bash sync.sh --config myconfig.conf
```

### Windows 10/11 (PowerShell)

```powershell
# Basic sync
.\sync.ps1

# Dry-run to preview changes
.\sync.ps1 -DryRun

# Verbose output
.\sync.ps1 -Verbose

# Dry-run with verbose output
.\sync.ps1 -DryRun -Verbose

# Custom config file
.\sync.ps1 -ConfigPath myconfig.conf
```

### Windows 10/11 (Batch - Easier)

```batch
# Basic sync
sync.bat

# Dry-run to preview changes
sync.bat -dry-run

# Verbose output
sync.bat -verbose

# Dry-run with verbose output
sync.bat -dry-run -verbose
```

## What Gets Synced

### Character-Level Files
- `bindings-cache.wtf` (unless excluded)
- `camera-settings.txt`
- `chat-cache.txt`
- `layout-cache.txt`
- `macros-cache.txt` (unless excluded)
- `macros-local.txt`
- `AddOns.txt` (unless excluded)
- `SavedVariables` folder (with addon exclusions applied)

### Account-Level Files
- `SavedVariables.lua`
- `SavedVariables` folder (with addon exclusions applied)

## Sync Behavior

1. **Within prototype account**: Syncs all characters except the prototype character
2. **Across other accounts**: Syncs account-level files and all characters
3. **Addon exclusions**: Skips addons matching `addon_excluded` list
4. **Character file exclusions**: Skips files matching `char_files_excluded` list
5. **Character filtering**: If `only_chars` is set, only syncs those characters

## Example Output

```
[sync] Dry-run enabled
[sync] Syncing characters within prototype account: {Account-1}
[sync] Syncing character: {Account-1}/{Server-1}/{Char-1}
[sync] Syncing character: {Account-1}/{Server-2}/{Char-2}
[sync] Syncing account: {Account-2}
[sync] Syncing character: {Account-2}/{Server-1}/{Char-1}
[sync] Syncing character: {Account-2}/{Server-2}/{Char-2}
[sync] Done.
```

## Requirements

- **macOS/Linux**: Bash 3+ (default on macOS)
- **Windows**: PowerShell 5.0+ (included with Windows 10/11)
- **All platforms**: World of Warcraft WTF folder structure

## Troubleshooting

### macOS/Linux
- Ensure the script has execute permissions: `chmod +x sync.sh`
- Check that bash is available: `which bash`

### Windows
- If PowerShell execution is blocked, run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Ensure PowerShell is in your PATH
- The batch wrapper (`sync.bat`) handles execution policy automatically

### General
- Verify your `config.conf` file is in the same directory as the script
- Check that the prototype character path exists
- Use `--dry-run` or `-DryRun` to preview changes before applying them
