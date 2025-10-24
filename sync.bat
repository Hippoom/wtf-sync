@echo off
REM WTF Config Sync Script - Windows Batch Wrapper
REM 
REM Usage:
REM   sync.bat [-dry-run] [-verbose]
REM
REM This script calls the PowerShell version with appropriate parameters.

setlocal enabledelayedexpansion

set "DRY_RUN="
set "VERBOSE="

:parse_args
if "%~1"=="" goto :run_script
if /i "%~1"=="-dry-run" (
    set "DRY_RUN=-DryRun"
    shift
    goto :parse_args
)
if /i "%~1"=="-verbose" (
    set "VERBOSE=-Verbose"
    shift
    goto :parse_args
)
if /i "%~1"=="-h" goto :help
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-?" goto :help

echo Unknown argument: %~1
goto :help

:help
echo WTF Config Sync Script - Windows Batch Wrapper
echo.
echo Usage:
echo   sync.bat [-dry-run] [-verbose]
echo.
echo Options:
echo   -dry-run    Show what would be synced without making changes
echo   -verbose    Show detailed output
echo   -h, --help  Show this help message
echo.
echo Examples:
echo   sync.bat
echo   sync.bat -dry-run -verbose
echo.
goto :end

:run_script
REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Check if PowerShell is available
powershell -Command "Get-Host" >nul 2>&1
if errorlevel 1 (
    echo Error: PowerShell is not available or not in PATH
    echo Please ensure PowerShell is installed and accessible
    goto :end
)

REM Run the PowerShell script
echo Running WTF Config Sync...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%sync.ps1" %DRY_RUN% %VERBOSE%

if errorlevel 1 (
    echo.
    echo Script completed with errors.
) else (
    echo.
    echo Script completed successfully.
)

:end
pause
