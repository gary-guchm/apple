<#
.SYNOPSIS
Clears all active and recent Microsoft Edge browsing session data for the current user.

.DESCRIPTION
This script performs two main actions:
1. Stops all running instances of the Microsoft Edge browser.
2. Deletes the specific files and folders responsible for the "Restore pages"
   dialog and storing the last session/open tabs.
#>

# --- Configuration Section ---
# Set this to $true to automatically apply the Registry policy
# which prevents the "Restore pages" dialog from ever showing up again.
$SetPermanentPolicy = $true
# Time (in seconds) to wait for the msedge process to fully terminate
$ProcessWaitTime = 3

# --- 1. Terminate Microsoft Edge Processes ---

Write-Host "Attempting to stop all running Microsoft Edge processes..." -ForegroundColor Yellow

# Stop the msedge process forcefully, suppressing errors if it's not running
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force

# Wait briefly to ensure the processes have fully released file locks
Start-Sleep -Seconds $ProcessWaitTime
Write-Host "Edge processes terminated (or were not running)." -ForegroundColor Green


# --- 2. Define Paths and Files to Delete ---

# The Edge profile path often defaults to 'Default' for the main user profile
# NOTE: If the user uses a different profile, this path needs adjustment.
$edgeUserDataPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
$sessionFiles = @(
    "Last Session",       # Stores the state of the last closed session
    "Last Tabs",          # Stores the tabs from the last closed session
    "Current Session",    # Stores the currently running session state
    "Current Tabs",       # Stores the currently running tabs
    "History"             # Optionally clear browsing history file
)

# --- 3. Delete Session Files and Folders ---

Write-Host "Clearing specific session and crash recovery files..." -ForegroundColor Yellow

# Clear individual session files
foreach ($file in $sessionFiles) {
    $filePath = Join-Path $edgeUserDataPath $file
    
    if (Test-Path $filePath) {
        # Use a Try/Catch block for robust error handling during file deletion
        try {
            Remove-Item $filePath -Force -ErrorAction Stop
            Write-Host "   [SUCCESS] Removed: $file" -ForegroundColor Green
        }
        catch {
            Write-Host "   [ERROR] Could not remove $file. It might still be in use: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Clear the 'Sessions' folder (which contains backup session files)
$sessionsFolder = Join-Path $edgeUserDataPath "Sessions"
if (Test-Path $sessionsFolder) {
    try {
        Remove-Item $sessionsFolder -Recurse -Force -ErrorAction Stop
        Write-Host "   [SUCCESS] Cleared Sessions folder." -ForegroundColor Green
    }
    catch {
        Write-Host "   [ERROR] Could not clear Sessions folder: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nSession and crash recovery data clearance complete." -ForegroundColor Cyan


