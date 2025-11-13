<#
.SYNOPSIS
    Manage Whisper API Windows Service
.DESCRIPTION
    Control the whisper-api service: start, stop, restart, status, view logs
.PARAMETER Action
    Action to perform: status, start, stop, restart, logs, remove
.EXAMPLE
    .\manage-service.ps1 -Action status
    .\manage-service.ps1 -Action restart
    .\manage-service.ps1 -Action logs
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("status", "start", "stop", "restart", "logs", "remove", "config")]
    [string]$Action = "status",

    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "C:\Program Files\Whisper Api"
)

$ErrorActionPreference = "Continue"
$serviceName = "whisper-api"

function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
        exit 1
    }
}

function Show-ServiceStatus {
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "Whisper API Service Status" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan + "`n"

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Host "✗ Service not found!" -ForegroundColor Red
        Write-Host "Run: install-whisper.bat to install the service" -ForegroundColor Yellow
        return
    }

    $statusColor = if ($service.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "Service Name:     $($service.Name)" -ForegroundColor Cyan
    Write-Host "Display Name:     $($service.DisplayName)" -ForegroundColor Cyan
    Write-Host "Status:           $($service.Status)" -ForegroundColor $statusColor
    Write-Host "Startup Type:     $($service.StartType)" -ForegroundColor Cyan

    # Get service details from registry
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
    $regItem = Get-Item -Path $regPath -ErrorAction SilentlyContinue

    if ($regItem) {
        $envPath = "$regPath\Environment"
        if (Test-Path $envPath) {
            Write-Host "`nEnvironment Variables:" -ForegroundColor Cyan
            $env = Get-ItemProperty -Path $envPath
            foreach ($prop in $env.PSObject.Properties) {
                if ($prop.Name -notlike "PS*") {
                    Write-Host "  $($prop.Name) = $($prop.Value)" -ForegroundColor Cyan
                }
            }
        }
    }

    # Check API endpoint
    Write-Host "`nAPI Health Check:" -ForegroundColor Cyan
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:4444/v1/health" -ErrorAction SilentlyContinue
        if ($health) {
            Write-Host "✓ API is responding" -ForegroundColor Green
            Write-Host "  Device:  $($health.device)" -ForegroundColor Green
            Write-Host "  Model:   $($health.model)" -ForegroundColor Green
            Write-Host "  CUDA:    $($health.cuda_available)" -ForegroundColor Green
        }
    } catch {
        Write-Host "✗ API endpoint not responding (port 4444)" -ForegroundColor Yellow
        Write-Host "  (Service may still be starting...)" -ForegroundColor Yellow
    }

    Write-Host "`n"
}

function Start-WhisperService {
    Write-Host "Starting $serviceName..." -ForegroundColor Cyan

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "✗ Service not found!" -ForegroundColor Red
        return
    }

    if ($service.Status -eq "Running") {
        Write-Host "✓ Service is already running" -ForegroundColor Green
        return
    }

    try {
        Start-Service -Name $serviceName -ErrorAction Stop
        Start-Sleep -Seconds 2

        $service = Get-Service -Name $serviceName
        if ($service.Status -eq "Running") {
            Write-Host "✓ Service started successfully" -ForegroundColor Green
        } else {
            Write-Host "⚠ Service failed to start (status: $($service.Status))" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "✗ Error starting service: $_" -ForegroundColor Red
    }
}

function Stop-WhisperService {
    Write-Host "Stopping $serviceName..." -ForegroundColor Cyan

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "✗ Service not found!" -ForegroundColor Red
        return
    }

    if ($service.Status -eq "Stopped") {
        Write-Host "✓ Service is already stopped" -ForegroundColor Green
        return
    }

    try {
        Stop-Service -Name $serviceName -ErrorAction Stop
        Start-Sleep -Seconds 1
        Write-Host "✓ Service stopped successfully" -ForegroundColor Green
    } catch {
        Write-Host "✗ Error stopping service: $_" -ForegroundColor Red
    }
}

function Restart-WhisperService {
    Write-Host "Restarting $serviceName..." -ForegroundColor Cyan

    Stop-WhisperService
    Start-Sleep -Seconds 2
    Start-WhisperService

    Write-Host "✓ Service restarted" -ForegroundColor Green
}

function Show-Logs {
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "Service Logs" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan + "`n"

    $stdoutLog = "$InstallPath\logs\stdout.log"
    $stderrLog = "$InstallPath\logs\stderr.log"

    # Show stdout
    if (Test-Path $stdoutLog) {
        Write-Host "STDOUT Log ($stdoutLog):" -ForegroundColor Cyan
        Write-Host ("─"*70) -ForegroundColor Cyan
        Get-Content -Path $stdoutLog -Tail 50 | Write-Host
        Write-Host ""
    } else {
        Write-Host "No stdout log found at $stdoutLog" -ForegroundColor Yellow
    }

    # Show stderr
    if (Test-Path $stderrLog) {
        Write-Host "STDERR Log ($stderrLog):" -ForegroundColor Cyan
        Write-Host ("─"*70) -ForegroundColor Cyan
        Get-Content -Path $stderrLog -Tail 50 | Write-Host
        Write-Host ""
    } else {
        Write-Host "No stderr log found at $stderrLog" -ForegroundColor Yellow
    }

    Write-Host "Tip: To follow logs in real-time, use:" -ForegroundColor Yellow
    Write-Host "  Get-Content -Path '$stderrLog' -Wait" -ForegroundColor Yellow
    Write-Host ""
}

function Show-Config {
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "Installation Configuration" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan + "`n"

    Write-Host "Installation Path:  $InstallPath" -ForegroundColor Cyan
    Write-Host "Service Name:       $serviceName" -ForegroundColor Cyan
    Write-Host "Logs Directory:     $InstallPath\logs" -ForegroundColor Cyan

    $installLog = "$InstallPath\install.log"
    if (Test-Path $installLog) {
        Write-Host "Install Log:        $installLog" -ForegroundColor Cyan
    }

    # Show current config from registry
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
    if (Test-Path $regPath) {
        Write-Host "`nService Registry Path: $regPath" -ForegroundColor Cyan

        $binaryPath = (Get-ItemProperty -Path $regPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
        if ($binaryPath) {
            Write-Host "Binary Path: $binaryPath" -ForegroundColor Cyan
        }
    }

    Write-Host "`n"
}

function Remove-WhisperService {
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "Remove Whisper API Service" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan + "`n"

    $confirm = Read-Host "Are you sure you want to remove the service? (yes/no)"

    if ($confirm -ne "yes") {
        Write-Host "Cancelled" -ForegroundColor Yellow
        return
    }

    try {
        Write-Host "Stopping service..." -ForegroundColor Cyan
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue

        Write-Host "Removing service..." -ForegroundColor Cyan
        sc.exe delete $serviceName | Out-Null

        Start-Sleep -Seconds 1

        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Host "✓ Service removed successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Service still exists (may require system restart)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "✗ Error removing service: $_" -ForegroundColor Red
    }

    Write-Host "`n"
}

# ============================================================================
# Main
# ============================================================================

$Action = $Action.ToLower()

Write-Host "`nWhisper API Service Manager" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Cyan

# Require admin for most operations
if ($Action -in @("start", "stop", "restart", "remove")) {
    Test-AdminPrivileges
}

switch ($Action) {
    "status"  { Show-ServiceStatus }
    "start"   { Start-WhisperService }
    "stop"    { Stop-WhisperService }
    "restart" { Restart-WhisperService }
    "logs"    { Show-Logs }
    "config"  { Show-Config }
    "remove"  { Remove-WhisperService }
    default   { Show-ServiceStatus }
}
