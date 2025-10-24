# WTF Config Sync Script (PowerShell)
#
# Usage:
#   .\sync.ps1 [-ConfigPath <PATH>] [-DryRun] [-Verbose]
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

param(
    [string]$ConfigPath = "config.conf",
    [switch]$DryRun,
    [switch]$Verbose
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Get script directory and WTF root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WTF_ROOT = Split-Path -Parent $ScriptDir
$CONFIG_FILE = Join-Path $ScriptDir $ConfigPath

# Logging functions
function Write-Log {
    param([string]$Message)
    Write-Host "[sync] $Message"
}

function Write-VerboseLog {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "[sync] $Message"
    }
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[sync][error] $Message" -ForegroundColor Red
}

# Check if config file exists
if (-not (Test-Path $CONFIG_FILE)) {
    Write-ErrorLog "Config not found: $CONFIG_FILE"
    exit 1
}

# Read config file
$config = @{}
Get-Content $CONFIG_FILE | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        $parts = $line -split "=", 2
        if ($parts.Length -eq 2) {
            $config[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
}

# Validate required config
if (-not $config.ContainsKey("prototype")) {
    Write-ErrorLog "prototype is required in config"
    exit 1
}

# Parse prototype
$prototype = $config["prototype"]
$parts = $prototype -split "/"
if ($parts.Length -eq 2) {
    $proto_acc = $parts[0]
    $proto_realm = ""
    $proto_char = $parts[1]
} elseif ($parts.Length -eq 3) {
    $proto_acc = $parts[0]
    $proto_realm = $parts[1]
    $proto_char = $parts[2]
} else {
    Write-ErrorLog "Invalid prototype: $prototype"
    exit 1
}

# Parse arrays from config
function Parse-Array {
    param([string]$value)
    if ([string]::IsNullOrEmpty($value)) {
        return @()
    }
    return $value -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$EXCLUDE_ADDONS = Parse-Array $config["addon_excluded"]
$EXCLUDE_CHAR_FILES = Parse-Array $config["char_files_excluded"]
$ONLY_CHARS = Parse-Array $config["only_chars"]

# Set up paths
$ACCOUNT_DIR = Join-Path $WTF_ROOT "Account"
if (-not (Test-Path $ACCOUNT_DIR)) {
    Write-ErrorLog "Account dir not found: $ACCOUNT_DIR"
    exit 1
}

# Find prototype character path
function Find-ProtoPath {
    if ($proto_realm) {
        $path = Join-Path $ACCOUNT_DIR "$proto_acc\$proto_realm\$proto_char"
        if (Test-Path $path) {
            return $path
        }
    } else {
        # Find first matching realm that contains char
        $protoAccDir = Join-Path $ACCOUNT_DIR $proto_acc
        if (Test-Path $protoAccDir) {
            $realms = Get-ChildItem $protoAccDir -Directory
            foreach ($realm in $realms) {
                $charPath = Join-Path $realm.FullName $proto_char
                if (Test-Path $charPath) {
                    return $charPath
                }
            }
        }
    }
    return $null
}

$PROTO_PATH = Find-ProtoPath
if (-not $PROTO_PATH) {
    Write-ErrorLog "Prototype path not found for $prototype"
    exit 1
}

Write-VerboseLog "Prototype path: $PROTO_PATH"

# Character files to sync
$CHAR_ITEMS = @(
    "bindings-cache.wtf",
    "camera-settings.txt",
    "chat-cache.txt",
    "layout-cache.txt",
    "macros-cache.txt",
    "macros-local.txt",
    "AddOns.txt",
    "SavedVariables"
)

# Helper functions
function Test-ShouldIncludeChar {
    param([string]$charName)
    if ($ONLY_CHARS.Count -eq 0) { return $true }
    return $ONLY_CHARS -contains $charName
}

function Test-ShouldSkipItem {
    param([string]$item)
    return $EXCLUDE_CHAR_FILES -contains $item
}

function Test-ShouldSkipAddon {
    param([string]$fileName)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    foreach ($exclude in $EXCLUDE_ADDONS) {
        if ($baseName -eq $exclude -or $baseName.StartsWith("$exclude-")) {
            return $true
        }
    }
    return $false
}

# Sync functions
function Sync-ToAccount {
    param(
        [string]$srcAccPath,
        [string]$dstAccPath
    )
    
    Write-VerboseLog "Syncing account files -> $dstAccPath"
    
    # Ensure destination exists
    if (-not (Test-Path $dstAccPath)) {
        New-Item -ItemType Directory -Path $dstAccPath -Force | Out-Null
    }
    
    # Sync SavedVariables.lua
    $srcPath = Join-Path $srcAccPath "SavedVariables.lua"
    if (Test-Path $srcPath) {
        $dstPath = Join-Path $dstAccPath "SavedVariables.lua"
        if ($DryRun) {
            Write-VerboseLog "Would copy: $srcPath -> $dstPath"
        } else {
            Copy-Item $srcPath $dstPath -Force
        }
    } else {
        Write-VerboseLog "Skipping missing: $srcPath"
    }
    
    # Sync SavedVariables folder
    $srcFolder = Join-Path $srcAccPath "SavedVariables"
    if (Test-Path $srcFolder) {
        $dstFolder = Join-Path $dstAccPath "SavedVariables"
        if (-not (Test-Path $dstFolder)) {
            New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
        }
        
        # Get all files in SavedVariables, excluding addons
        $files = Get-ChildItem $srcFolder -File
        foreach ($file in $files) {
            if (Test-ShouldSkipAddon $file.Name) {
                Write-VerboseLog "Excluded addon: $($file.Name)"
                continue
            }
            
            $dstFile = Join-Path $dstFolder $file.Name
            if ($DryRun) {
                Write-VerboseLog "Would copy: $($file.FullName) -> $dstFile"
            } else {
                Copy-Item $file.FullName $dstFile -Force
            }
        }
        
        # Remove files that shouldn't be there (cleanup)
        if (-not $DryRun) {
            $dstFiles = Get-ChildItem $dstFolder -File
            foreach ($dstFile in $dstFiles) {
                if (Test-ShouldSkipAddon $dstFile.Name) {
                    Write-VerboseLog "Removing excluded addon: $($dstFile.Name)"
                    Remove-Item $dstFile.FullName -Force
                }
            }
        }
    } else {
        Write-VerboseLog "Skipping missing: $srcFolder"
    }
}

function Sync-ToChar {
    param(
        [string]$srcCharPath,
        [string]$dstCharPath
    )
    
    Write-VerboseLog "Syncing -> $dstCharPath"
    
    # Ensure destination exists
    if (-not (Test-Path $dstCharPath)) {
        New-Item -ItemType Directory -Path $dstCharPath -Force | Out-Null
    }
    
    foreach ($item in $CHAR_ITEMS) {
        # Skip configured character-level files
        if (Test-ShouldSkipItem $item) {
            Write-VerboseLog "Excluded by config: $item"
            continue
        }
        
        $srcPath = Join-Path $srcCharPath $item
        if (Test-Path $srcPath) {
            if ($item -eq "SavedVariables") {
                # Handle SavedVariables folder with addon exclusions
                $dstFolder = Join-Path $dstCharPath "SavedVariables"
                if (-not (Test-Path $dstFolder)) {
                    New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
                }
                
                $files = Get-ChildItem $srcPath -File
                foreach ($file in $files) {
                    if (Test-ShouldSkipAddon $file.Name) {
                        Write-VerboseLog "Excluded addon: $($file.Name)"
                        continue
                    }
                    
                    $dstFile = Join-Path $dstFolder $file.Name
                    if ($DryRun) {
                        Write-VerboseLog "Would copy: $($file.FullName) -> $dstFile"
                    } else {
                        Copy-Item $file.FullName $dstFile -Force
                    }
                }
                
                # Remove files that shouldn't be there (cleanup)
                if (-not $DryRun) {
                    $dstFiles = Get-ChildItem $dstFolder -File
                    foreach ($dstFile in $dstFiles) {
                        if (Test-ShouldSkipAddon $dstFile.Name) {
                            Write-VerboseLog "Removing excluded addon: $($dstFile.Name)"
                            Remove-Item $dstFile.FullName -Force
                        }
                    }
                }
            } else {
                # Handle regular files
                $dstPath = Join-Path $dstCharPath $item
                if ($DryRun) {
                    Write-VerboseLog "Would copy: $srcPath -> $dstPath"
                } else {
                    Copy-Item $srcPath $dstPath -Force
                }
            }
        } else {
            Write-VerboseLog "Skipping missing: $srcPath"
        }
    }
}

# Main sync logic
if ($DryRun) {
    Write-Log "Dry-run enabled"
}

# Sync characters within prototype account first
$PROTO_ACC_DIR = Join-Path $ACCOUNT_DIR $proto_acc
if (Test-Path $PROTO_ACC_DIR) {
    Write-Log "Syncing characters within prototype account: $proto_acc"
    
    $realms = Get-ChildItem $PROTO_ACC_DIR -Directory
    foreach ($realm in $realms) {
        $realmName = $realm.Name
        $charDirs = Get-ChildItem $realm.FullName -Directory
        foreach ($charDir in $charDirs) {
            $charName = $charDir.Name
            $charPath = $charDir.FullName
            
            # Skip source character path
            if ($charPath -eq $PROTO_PATH) { continue }
            
            # Filter by only_chars
            if (-not (Test-ShouldIncludeChar $charName)) { continue }
            
            Write-Log "Syncing character: $proto_acc/$realmName/$charName"
            Sync-ToChar $PROTO_PATH $charPath
        }
    }
}

# Get all accounts except prototype
$allAccounts = Get-ChildItem $ACCOUNT_DIR -Directory | Where-Object { $_.Name -ne $proto_acc }

# Iterate other destination accounts
foreach ($acc in $allAccounts) {
    $accName = $acc.Name
    $accDir = $acc.FullName
    
    Write-Log "Syncing account: $accName"
    
    # Sync account-level files
    Sync-ToAccount $PROTO_ACC_DIR $accDir
    
    # Sync characters in this account
    $realms = Get-ChildItem $accDir -Directory
    foreach ($realm in $realms) {
        $realmName = $realm.Name
        $charDirs = Get-ChildItem $realm.FullName -Directory
        foreach ($charDir in $charDirs) {
            $charName = $charDir.Name
            $charPath = $charDir.FullName
            
            # Skip source character path
            if ($charPath -eq $PROTO_PATH) { continue }
            
            # Filter by only_chars
            if (-not (Test-ShouldIncludeChar $charName)) { continue }
            
            Write-Log "Syncing character: $accName/$realmName/$charName"
            Sync-ToChar $PROTO_PATH $charPath
        }
    }
}

Write-Log "Done."
