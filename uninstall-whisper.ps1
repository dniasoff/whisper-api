#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls Whisper API from Windows
.DESCRIPTION
    Removes the Whisper API service, virtual environment, and optionally Python installation
.PARAMETER KeepInstallation
    If specified, keeps the installation directory (C:\Program Files\Whisper Api)
.PARAMETER InstallPath
    Installation directory (default: C:\Program Files\Whisper Api)
#>

param(
    [switch]$KeepInstallation,
    [string]$InstallPath = "C:\Program Files\Whisper Api"
)

$ErrorActionPreference = "Stop"
$serviceName = "whisper-api"

# ============================================================================
# Logging
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        default   { "White" }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
        exit 1
    }
}

function Write-Header {
    param([string]$Text)
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan
}

# ============================================================================
# Uninstallation Functions
# ============================================================================
function Stop-WhisperService {
    Write-Host "Stopping service..." -ForegroundColor Cyan

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Log "Service not found (already removed or not installed)" "INFO"
        return
    }

    if ($service.Status -eq "Running") {
        try {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-Log "Service stopped, waiting for processes to release files..."
            Write-Host "Waiting for service to fully stop..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5  # Match install script wait time
            Write-Log "Service stopped successfully"
            Write-Host "[OK] Service stopped" -ForegroundColor Green
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Log "ERROR: Failed to stop service: $errorMsg" "ERROR"
            throw $_
        }
    }
}

function Remove-WhisperService {
    Write-Host "Removing service..." -ForegroundColor Cyan

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Log "Service not found" "INFO"
        return
    }

    try {
        # Try to remove using pywin32 first (if whisper_service.py exists)
        $pythonExe = "$InstallPath\.python\python.exe"
        $servicePy = "$InstallPath\whisper_service.py"

        if ((Test-Path $pythonExe) -and (Test-Path $servicePy)) {
            Write-Log "Attempting to remove service using pywin32..." "INFO"
            try {
                & "$pythonExe" "$servicePy" remove 2>&1 | Out-Null
                Start-Sleep -Seconds 2
                Write-Log "Service removed via pywin32" "SUCCESS"
            } catch {
                Write-Log "pywin32 removal failed, falling back to sc.exe" "WARNING"
            }
        }

        # Fallback or additional cleanup with sc.exe
        $serviceCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($serviceCheck) {
            Write-Log "Removing service via sc.exe..." "INFO"
            sc.exe delete $serviceName | Out-Null
            Start-Sleep -Seconds 2
        }

        $serviceCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $serviceCheck) {
            Write-Log "Service removed successfully" "SUCCESS"
        } else {
            Write-Log "WARNING: Service still exists (may require system restart)" "WARNING"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "ERROR: Failed to remove service: $errorMsg" "ERROR"
        throw $_
    }
}

function Stop-RunningProcesses {
    Write-Host "Stopping any running processes..." -ForegroundColor Cyan

    try {
        # Kill any processes from the installation directory (matching install script logic)
        Write-Log "Checking for processes from installation directory..."
        $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($InstallPath, [StringComparison]::OrdinalIgnoreCase)
        }

        if ($processes) {
            Write-Log "Found $($processes.Count) process(es) using installation directory, stopping..."
            Write-Host "Stopping processes..." -ForegroundColor Cyan
            foreach ($proc in $processes) {
                Write-Log "Stopping process: $($proc.Name) (PID: $($proc.Id))"
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Waiting for file handles to release..."
            Write-Host "Waiting for file handles to release..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3  # Match install script wait time
            Write-Log "Processes stopped"
            Write-Host "[OK] Processes stopped" -ForegroundColor Green
        } else {
            Write-Log "No running processes found from installation directory"
            Write-Host "[OK] No processes to stop" -ForegroundColor Green
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "WARNING: Error stopping processes: $errorMsg" "WARNING"
        Write-Host "[WARNING] Error stopping some processes" -ForegroundColor Yellow
    }
}

function Remove-InstallationDirectory {
    Write-Host "Removing installation files..." -ForegroundColor Cyan

    if (-not (Test-Path $InstallPath)) {
        Write-Log "Installation directory not found at $InstallPath" "INFO"
        return
    }

    try {
        # Only remove specific items - let WiX handle the rest
        # Items to remove: .python, logs, __pycache__, get-pip.py, install.log
        $itemsToRemove = @(
            ".python",
            "logs",
            "__pycache__",
            "get-pip.py",
            "install.log"
        )

        Write-Log "Removing specific installation files (WiX will handle the rest)" "INFO"
        $removedCount = 0
        $failedCount = 0

        foreach ($itemName in $itemsToRemove) {
            $itemPath = Join-Path $InstallPath $itemName

            if (Test-Path $itemPath) {
                try {
                    Write-Log "Removing: $itemName" "INFO"
                    Write-Host "  Removing: $itemName..." -ForegroundColor Yellow

                    # Remove read-only attributes if present
                    if (Test-Path $itemPath -PathType Container) {
                        $items = Get-ChildItem -Path $itemPath -Recurse -Force -ErrorAction SilentlyContinue
                        foreach ($item in $items) {
                            try {
                                if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                                    $item.Attributes = $item.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
                                }
                            } catch {
                                # Ignore attribute errors
                            }
                        }
                    }

                    Remove-Item -Path $itemPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed: $itemName" "SUCCESS"
                    Write-Host "  [OK] $itemName removed" -ForegroundColor Green
                    $removedCount++
                } catch {
                    $errorMsg = $_.Exception.Message
                    Write-Log "WARNING: Could not remove $itemName`: $errorMsg" "WARNING"
                    Write-Host "  [WARNING] Could not remove $itemName" -ForegroundColor Yellow
                    $failedCount++
                }
            } else {
                Write-Log "Item not found: $itemName (already removed or not present)" "INFO"
            }
        }

        if ($removedCount -gt 0) {
            Write-Host "`n[OK] Removed $removedCount item(s)" -ForegroundColor Green
        }

        if ($failedCount -gt 0) {
            Write-Host "[WARNING] Failed to remove $failedCount item(s)" -ForegroundColor Yellow
        }

        Write-Log "Installation file cleanup complete (WiX will remove remaining files)" "INFO"
        Write-Host "`nNote: Remaining files will be removed by the MSI uninstaller" -ForegroundColor Cyan

    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "ERROR: Failed to remove installation files: $errorMsg" "ERROR"
        Write-Host "[ERROR] Failed to remove installation files" -ForegroundColor Red
        Write-Host "Error: $errorMsg" -ForegroundColor Red
    }
}

function Remove-EnvironmentVariables {
    Write-Host "Removing environment variables..." -ForegroundColor Cyan

    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Log "Registry entries removed" "SUCCESS"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "WARNING: Failed to remove registry entries: $errorMsg" "WARNING"
    }
}

function Show-UninstallationSummary {
    Write-Header "Uninstallation Complete!"

    Write-Host "The Whisper API service has been removed.`n" -ForegroundColor Green
    Write-Host "Removed Components:" -ForegroundColor Green
    Write-Host "  [OK] Windows Service (whisper-api)" -ForegroundColor Green
    Write-Host "  [OK] Registry entries" -ForegroundColor Green

    if ($KeepInstallation) {
        Write-Host "  [ - ] Python installation directory (kept as requested)`n" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Python installation directory`n" -ForegroundColor Green
    }
}

# ============================================================================
# Main
# ============================================================================
function Start-Uninstallation {
    try {
        Test-AdminPrivileges

        Write-Header "Whisper API Uninstaller"
        Write-Host "Installation Path: $InstallPath`n" -ForegroundColor Cyan

        # Confirmation
        Write-Host "This will remove the Whisper API service and" -ForegroundColor Yellow
        if (-not $KeepInstallation) {
            Write-Host "all associated files and directories." -ForegroundColor Yellow
        } else {
            Write-Host "associated files (keeping the installation directory)." -ForegroundColor Yellow
        }

        $confirm = Read-Host "`nContinue with uninstallation? (Y/n) [default: Yes]"

        # Default to yes if empty input
        if ([string]::IsNullOrWhiteSpace($confirm)) {
            $confirm = "y"
        }

        if ($confirm -notmatch "^[yY]") {
            Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
            exit 0
        }

        # Uninstall steps
        Stop-WhisperService
        Remove-WhisperService
        Stop-RunningProcesses
        Remove-EnvironmentVariables

        if (-not $KeepInstallation) {
            Remove-InstallationDirectory
        }

        Show-UninstallationSummary

    } catch {
        Write-Host "`nUninstallation failed: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# Execute
# ============================================================================
Start-Uninstallation
