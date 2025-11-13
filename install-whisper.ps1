<#
.SYNOPSIS
    Installs Whisper API as a Windows Service
.DESCRIPTION
    Comprehensive installer that downloads Python 3.13, installs dependencies,
    configures CUDA if available, and sets up a Windows Service.
    Can be run standalone for testing or from MSI installer.
.PARAMETER InstallPath
    Installation directory (default: C:\Program Files\Whisper Api)
.PARAMETER SkipElevation
    Skip automatic elevation to admin (for testing only)
#>

param(
    [string]$InstallPath = "C:\Program Files\Whisper Api",
    [switch]$SkipElevation
)

# ============================================================================
# Self-Elevation (Run as Administrator)
# ============================================================================
if (-not $SkipElevation) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "This script requires Administrator privileges." -ForegroundColor Yellow
        Write-Host "Attempting to elevate..." -ForegroundColor Cyan

        try {
            # Re-launch as administrator
            $scriptPath = $MyInvocation.MyCommand.Path
            $arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`""

            if ($InstallPath -ne "C:\Program Files\Whisper Api") {
                $arguments += " -InstallPath `"$InstallPath`""
            }

            Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
            exit
        } catch {
            Write-Host "Failed to elevate to administrator. Please run PowerShell as Administrator manually." -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:IsInteractive = [Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() | Where-Object { $_ -like "-NonInteractive" })

# Set up logging paths - primary in temp, secondary in install directory
# Add milliseconds and random number to avoid conflicts
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$random = Get-Random -Minimum 1000 -Maximum 9999
$script:LogPathTemp = Join-Path $env:TEMP "Whisper-API-Install-$timestamp-$random.log"
$script:LogPathInstall = "$InstallPath\install.log"
$script:LogPath = $script:LogPathTemp  # Use temp path as primary

# ============================================================================
# Logging Functions
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to temp log file with retry logic
    $maxRetries = 3
    $retryCount = 0
    $logWritten = $false

    while (-not $logWritten -and $retryCount -lt $maxRetries) {
        try {
            # Ensure temp log directory exists
            $logDirTemp = Split-Path $script:LogPathTemp
            if (-not (Test-Path $logDirTemp)) {
                New-Item -ItemType Directory -Path $logDirTemp -Force -ErrorAction SilentlyContinue | Out-Null
            }

            # Write to temp log file
            [System.IO.File]::AppendAllText($script:LogPathTemp, "$logMessage`r`n")
            $logWritten = $true
        } catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Start-Sleep -Milliseconds (100 * $retryCount)
            }
        }
    }

    # Also write to install directory log if it exists
    if ($script:LogPathInstall -and (Test-Path (Split-Path $script:LogPathInstall) -ErrorAction SilentlyContinue)) {
        try {
            [System.IO.File]::AppendAllText($script:LogPathInstall, "$logMessage`r`n")
        } catch {
            # Silently ignore install directory log errors
        }
    }

    # Write to console with colors
    if (-not $NoConsole) {
        $color = switch ($Level) {
            "SUCCESS" { "Green" }
            "ERROR"   { "Red" }
            "WARNING" { "Yellow" }
            default   { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}

function Write-Header {
    param([string]$Text)
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan
    Write-Log $Text "INFO"

    # Update progress window if it exists
    if ($script:ProgressWindow) {
        try {
            $script:ProgressWindow.Dispatcher.Invoke([Action]{
                $script:ProgressLog.AppendText("$Text`r`n")
                $script:ProgressLog.ScrollToEnd()
            }, "Normal") | Out-Null
        } catch {
            # Silently ignore progress window errors in non-interactive contexts
            Write-Log "Progress window update failed in Write-Header (expected in some contexts): $_" "WARNING"
        }
    }
}

function Update-ProgressWindow {
    param([string]$Message)

    if ($script:ProgressWindow) {
        try {
            $script:ProgressWindow.Dispatcher.Invoke([Action]{
                $timestamp = Get-Date -Format "HH:mm:ss"
                $script:ProgressLog.AppendText("[$timestamp] $Message`r`n")
                $script:ProgressLog.ScrollToEnd()
            }, "Normal") | Out-Null
        } catch {
            # Silently ignore progress window errors in non-interactive contexts
            Write-Log "Progress window update failed (expected in some contexts): $_" "WARNING"
        }
    }
}

function Show-ProgressWindow {
    [void][System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Whisper API Installation" Height="500" Width="700"
        WindowStartupLocation="CenterScreen" Background="#F5F5F5"
        Topmost="True" ResizeMode="CanResizeWithGrip">
    <StackPanel Margin="20">
        <TextBlock FontSize="18" FontWeight="Bold" Foreground="#1F1F1F" Margin="0,0,0,10">
            Installing Whisper API...
        </TextBlock>
        <TextBlock FontSize="12" Foreground="#666666" Margin="0,0,0,15">
            Installation in progress. This may take 5-10 minutes depending on your internet connection.
        </TextBlock>
        <TextBlock FontSize="11" Foreground="#999999" Margin="0,0,0,5">
            Installation Log:
        </TextBlock>
        <TextBox Name="ProgressLog" Height="350" VerticalScrollBarVisibility="Auto"
                 FontFamily="Courier New" FontSize="10" IsReadOnly="True"
                 Foreground="#333333" Background="White" Margin="0,0,0,15"
                 TextWrapping="Wrap"/>
        <ProgressBar Height="25" IsIndeterminate="True" Foreground="#4CAF50"/>
        <TextBlock FontSize="10" Foreground="#666666" Margin="0,10,0,0">
            Do NOT close this window during installation.
        </TextBlock>
    </StackPanel>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
    $script:ProgressWindow = [Windows.Markup.XamlReader]::Load($reader)
    $script:ProgressLog = $script:ProgressWindow.FindName("ProgressLog")

    # Show window in background thread
    $threadStart = [System.Threading.ThreadStart]{
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke({
            $script:ProgressWindow.ShowDialog() | Out-Null
        }, "Normal")
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Run()
    }
    $windowThread = [System.Threading.Thread]::new($threadStart)
    $windowThread.ApartmentState = "STA"
    $windowThread.IsBackground = $true
    $windowThread.Start()

    Start-Sleep -Milliseconds 500
}

# ============================================================================
# Validation Functions
# ============================================================================
function Test-AdminPrivileges {
    Write-Log "Checking admin privileges..." "INFO"
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "ERROR: Script does not have admin privileges!" "ERROR"
        Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
        Update-ProgressWindow "ERROR: Script requires Administrator privileges"
        Start-Sleep -Seconds 3
        exit 1
    }
    Write-Log "Admin privileges verified" "INFO"
    Write-Host "[OK] Admin privileges confirmed" -ForegroundColor Green
}

function Test-InternetConnectivity {
    Write-Host "Checking internet connectivity..." -ForegroundColor Cyan
    Update-ProgressWindow "Checking internet connectivity..."

    # List of reliable endpoints to test (Google, Cloudflare, Microsoft)
    $endpoints = @(
        @{ Host = "www.google.com"; Port = 443 },
        @{ Host = "one.one.one.one"; Port = 443 },
        @{ Host = "www.microsoft.com"; Port = 443 }
    )

    foreach ($endpoint in $endpoints) {
        try {
            Write-Log "Testing connectivity to $($endpoint.Host):$($endpoint.Port)..."

            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.BeginConnect($endpoint.Host, $endpoint.Port, $null, $null)
            $timeout = 3000  # 3 seconds timeout

            $success = $connectTask.AsyncWaitHandle.WaitOne($timeout, $false)

            if ($success) {
                try {
                    $tcpClient.EndConnect($connectTask)
                    $tcpClient.Close()
                    Write-Log "Internet connectivity verified via $($endpoint.Host)"
                    Write-Host "[OK] Internet connection verified" -ForegroundColor Green
                    Update-ProgressWindow "Internet connection verified"
                    return $true
                } catch {
                    Write-Log "Connection to $($endpoint.Host) failed: $_" "WARNING"
                }
            } else {
                Write-Log "Connection to $($endpoint.Host) timed out after ${timeout}ms" "WARNING"
                $tcpClient.Close()
            }
        } catch {
            Write-Log "Error testing $($endpoint.Host): $_" "WARNING"
        }
    }

    # All endpoints failed
    Write-Log "WARNING: Could not verify internet connectivity to any endpoint" "WARNING"
    Write-Host "[WARNING] Internet connectivity check failed" -ForegroundColor Yellow
    Write-Host "  Installation will continue, but downloads may fail" -ForegroundColor Yellow
    Update-ProgressWindow "WARNING: Internet check failed - continuing anyway"

    return $false
}

function Test-FFmpegInstallation {
    Write-Host "Checking FFmpeg installation..." -ForegroundColor Cyan
    Update-ProgressWindow "Checking FFmpeg installation..."

    try {
        $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
        if ($ffmpeg) {
            Write-Log "FFmpeg found: $($ffmpeg.Source)"
            Write-Host "[OK] FFmpeg is installed" -ForegroundColor Green
            Update-ProgressWindow "FFmpeg found at $($ffmpeg.Source)"
            return $true
        }
    } catch {}

    Write-Log "WARNING: FFmpeg not found in PATH" "WARNING"
    Write-Host "[WARNING] FFmpeg not found. Install it via: choco install ffmpeg -y" -ForegroundColor Yellow
    Update-ProgressWindow "FFmpeg not found - will continue without it"

    # Skip interactive prompt in non-interactive mode
    if (-not $script:IsInteractive) {
        Write-Log "Non-interactive mode: skipping FFmpeg installation prompt"
        return $false
    }

    $install = Read-Host "Would you like to install FFmpeg via Chocolatey? (y/n)"
    if ($install -eq "y") {
        try {
            choco install ffmpeg -y
            Write-Log "FFmpeg installed successfully"
            Update-ProgressWindow "FFmpeg installed successfully"
            return $true
        } catch {
            Write-Log "Failed to install FFmpeg: $_" "WARNING"
            Update-ProgressWindow "FFmpeg installation failed - continuing without it"
            return $false
        }
    }

    return $false
}

# ============================================================================
# Python Installation
# ============================================================================
function Install-Python {
    Write-Header "Installing Python 3.13"

    $pythonVersion = "3.13.0"
    $pythonDir = "$InstallPath\.python"
    $pythonExe = "$pythonDir\python.exe"

    # Check if Python already exists and if it's working properly
    if (Test-Path $pythonExe) {
        Write-Log "Found existing Python installation at $pythonExe"

        # Test if Python is working
        try {
            $existingPythonVersion = & "$pythonExe" --version 2>&1
            $pythonWorks = $LASTEXITCODE -eq 0
            Write-Log "Existing Python version check: $existingPythonVersion (exit code: $LASTEXITCODE)"
        } catch {
            $pythonWorks = $false
            Write-Log "Existing Python is not working: $_"
        }

        # Test if pip module is working
        try {
            $existingPipVersion = & "$pythonExe" -m pip --version 2>&1
            $pipWorks = $LASTEXITCODE -eq 0
            Write-Log "Existing pip version check: $existingPipVersion (exit code: $LASTEXITCODE)"
        } catch {
            $pipWorks = $false
            Write-Log "Existing pip is not working: $_"
        }

        if ($pythonWorks -and $pipWorks) {
            Write-Log "Existing Python and pip are working - will reuse installation"
            Write-Host "[OK] Using existing Python 3.13 installation" -ForegroundColor Green
            Update-ProgressWindow "Python 3.13 already installed and working"
            return $pythonExe
        } else {
            Write-Log "Existing Python installation has issues - will remove and reinstall"
            Write-Host "Existing Python installation is corrupted, removing..." -ForegroundColor Yellow
            Update-ProgressWindow "Removing corrupted Python installation..."

            # Stop the service if it's running (files may be locked)
            $serviceName = "whisper-api"
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -eq 'Running') {
                    Write-Log "Stopping service $serviceName before removing Python..."
                    Write-Host "Stopping whisper-api service..." -ForegroundColor Cyan
                    try {
                        Stop-Service -Name $serviceName -Force -ErrorAction Stop
                        Start-Sleep -Seconds 3  # Wait for service to fully stop and release file locks
                        Write-Log "Service stopped successfully"
                        Write-Host "[OK] Service stopped" -ForegroundColor Green
                    } catch {
                        Write-Log "WARNING: Failed to stop service: $_" "WARNING"
                        Write-Host "[WARNING] Could not stop service, some files may be locked" -ForegroundColor Yellow
                    }
                }
            }

            # Stop any running processes from the Python directory
            try {
                $pythonProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.Path -and $_.Path.StartsWith($pythonDir, [StringComparison]::OrdinalIgnoreCase)
                }

                if ($pythonProcesses) {
                    Write-Log "Found $($pythonProcesses.Count) process(es) using Python directory, stopping..."
                    Write-Host "Stopping Python processes..." -ForegroundColor Cyan
                    foreach ($proc in $pythonProcesses) {
                        Write-Log "Stopping process: $($proc.Name) (PID: $($proc.Id))"
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 2  # Additional wait for file handles to release
                    Write-Log "Python processes stopped"
                    Write-Host "[OK] Processes stopped" -ForegroundColor Green
                }
            } catch {
                Write-Log "WARNING: Error stopping processes: $_" "WARNING"
            }

            # Remove corrupted installation
            try {
                Remove-Item -Path $pythonDir -Recurse -Force -ErrorAction Stop
                Write-Log "Corrupted Python installation removed"
                Write-Host "[OK] Corrupted installation removed" -ForegroundColor Green
            } catch {
                Write-Log "WARNING: Could not remove corrupted installation: $_" "WARNING"
                Write-Host "[WARNING] Could not remove old installation, will try to overwrite" -ForegroundColor Yellow
            }
        }
    }

    try {
        # Create temp directory for download with random name for security
        $randomName = [System.IO.Path]::GetRandomFileName()
        $tempDir = Join-Path $env:TEMP "python_install_$randomName"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        # Use embeddable (portable) Python package instead of MSI installer
        # This avoids MSI conflicts and is much faster
        $zipFileName = "python-$pythonVersion-embed-amd64.zip"
        $zipPath = Join-Path $tempDir $zipFileName
        $downloadUrl = "https://www.python.org/ftp/python/$pythonVersion/$zipFileName"

        if (-not (Test-Path $zipPath)) {
            Write-Host "Downloading Python 3.13 embeddable package..." -ForegroundColor Cyan
            Write-Log "Downloading from: $downloadUrl"
            Update-ProgressWindow "Downloading Python 3.13 portable package (25 MB)..."

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $zipPath)

            Write-Log "Python package downloaded to $zipPath"
            Update-ProgressWindow "Python 3.13 downloaded successfully"
        } else {
            Write-Log "Python package already cached"
            Update-ProgressWindow "Python 3.13 package found in cache"
        }

        Write-Host "Extracting Python 3.13 to $pythonDir" -ForegroundColor Cyan
        Write-Log "Extracting Python embeddable package"
        Update-ProgressWindow "Extracting Python 3.13..."

        # Create installation directory
        if (-not (Test-Path $pythonDir)) {
            New-Item -ItemType Directory -Path $pythonDir -Force | Out-Null
        }

        # Extract the ZIP file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $pythonDir)

        Write-Log "Python extracted to $pythonDir"
        Update-ProgressWindow "Python 3.13 extracted successfully"

        # Verify Python executable exists
        if (Test-Path $pythonExe) {
            # Enable pip by uncommenting import site in pythonXX._pth file
            $pthFile = Get-ChildItem -Path $pythonDir -Filter "python*._pth" | Select-Object -First 1
            if ($pthFile) {
                Write-Log "Enabling pip by modifying $($pthFile.Name)"
                $content = Get-Content $pthFile.FullName
                $content = $content -replace '#import site', 'import site'
                $content | Set-Content $pthFile.FullName
            }

            # Download and install pip
            Write-Host "Installing pip..." -ForegroundColor Cyan
            Write-Log "Downloading get-pip.py"
            Update-ProgressWindow "Installing pip package manager..."

            $getPipPath = Join-Path $tempDir "get-pip.py"
            Write-Log "Downloading get-pip.py to $getPipPath"

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile("https://bootstrap.pypa.io/get-pip.py", $getPipPath)
            Write-Log "get-pip.py downloaded successfully"

            if (-not (Test-Path $getPipPath)) {
                throw "Failed to download get-pip.py"
            }

            Write-Log "Running: `"$pythonExe`" `"$getPipPath`" --no-warn-script-location"
            Update-ProgressWindow "Running pip installer (get-pip.py)..."

            try {
                # Run get-pip.py with explicit error handling
                # Use array for ArgumentList to handle paths with spaces correctly
                $pipInstallProcess = Start-Process -FilePath "$pythonExe" `
                    -ArgumentList @("$getPipPath", "--no-warn-script-location") `
                    -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput "$env:TEMP\pip-install-stdout.txt" `
                    -RedirectStandardError "$env:TEMP\pip-install-stderr.txt"

                $pipExitCode = $pipInstallProcess.ExitCode
                Write-Log "get-pip.py exit code: $pipExitCode"

                # Read and log output
                if (Test-Path "$env:TEMP\pip-install-stdout.txt") {
                    $pipStdout = Get-Content "$env:TEMP\pip-install-stdout.txt" -Raw
                    Write-Log "get-pip.py stdout: $pipStdout"
                }
                if (Test-Path "$env:TEMP\pip-install-stderr.txt") {
                    $pipStderr = Get-Content "$env:TEMP\pip-install-stderr.txt" -Raw
                    Write-Log "get-pip.py stderr: $pipStderr"
                }

                if ($pipExitCode -ne 0) {
                    Write-Log "WARNING: get-pip.py returned exit code $pipExitCode" "WARNING"
                }
            } catch {
                Write-Log "ERROR: Failed to run get-pip.py: $_" "ERROR"
                throw $_
            }

            # Wait a moment for filesystem to update
            Start-Sleep -Milliseconds 500

            # Verify pip was installed
            $pipExe = Join-Path $pythonDir "Scripts\pip.exe"
            if (Test-Path $pipExe) {
                Write-Log "pip.exe installed successfully at $pipExe"
                Write-Host "[OK] pip installed successfully" -ForegroundColor Green
                Update-ProgressWindow "pip installed successfully"
            } else {
                Write-Log "pip.exe not found at $pipExe after installation" "WARNING"

                # Try to find pip.exe in other locations
                $altPipPath = Join-Path $pythonDir "pip.exe"
                if (Test-Path $altPipPath) {
                    Write-Log "Found pip.exe at alternate location: $altPipPath"
                }

                # Check if pip module works even without pip.exe
                $pipModuleTest = & "$pythonExe" -m pip --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "pip module is functional: $pipModuleTest"
                    Write-Host "[OK] pip module installed (will use python -m pip)" -ForegroundColor Green
                    Update-ProgressWindow "pip module installed successfully"
                } else {
                    Write-Log "ERROR: pip installation failed - neither pip.exe nor pip module works" "ERROR"
                    Write-Host "[X] pip installation failed" -ForegroundColor Red
                    throw "pip installation failed"
                }
            }

            Write-Log "Python installed successfully at $pythonExe"
            Write-Host "[OK] Python 3.13 installed successfully" -ForegroundColor Green
            Update-ProgressWindow "Python 3.13 installation completed successfully"
            return $pythonExe
        } else {
            throw "Python installation failed - executable not found at $pythonExe"
        }
    } catch {
        Write-Log "ERROR: Failed to install Python: $_" "ERROR"
        Update-ProgressWindow "ERROR: Failed to install Python - $_"
        throw $_
    }
}

# ============================================================================
# GPU Detection & CUDA Installation
# ============================================================================
function Test-CudaCapability {
    Write-Header "Detecting GPU Capability"

    try {
        # Find nvidia-smi - check common locations
        $nvidiaSmi = $null
        $commonPaths = @(
            "C:\Windows\System32\nvidia-smi.exe",
            "C:\Windows\Sysnative\nvidia-smi.exe",  # Bypass WoW64 redirection if running 32-bit
            "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
            "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
        )

        # Try full paths first
        foreach ($path in $commonPaths) {
            Write-Log "Checking for nvidia-smi at: $path"
            $exists = Test-Path $path
            Write-Log "Test-Path result for $path : $exists"

            if ($exists) {
                $nvidiaSmi = $path
                Write-Log "Found nvidia-smi at: $path"
                Write-Host "[OK] Found nvidia-smi at: $path" -ForegroundColor Green
                break
            }
        }

        # If not found, try PATH
        if (-not $nvidiaSmi) {
            try {
                $pathCommand = Get-Command nvidia-smi -ErrorAction SilentlyContinue
                if ($pathCommand) {
                    $nvidiaSmi = $pathCommand.Source
                    Write-Log "Found nvidia-smi in PATH: $nvidiaSmi"
                    Write-Host "[OK] Found nvidia-smi in PATH" -ForegroundColor Green
                }
            } catch {
                Write-Log "nvidia-smi not found in PATH"
            }
        }

        if (-not $nvidiaSmi) {
            Write-Log "nvidia-smi not found in PATH or common locations"
            return @{ Available = $false; Reason = "nvidia-smi not found" }
        }

        $nvidiaInfo = & $nvidiaSmi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>$null

        if ($LASTEXITCODE -ne 0) {
            Write-Log "nvidia-smi command failed"
            return @{ Available = $false; Reason = "nvidia-smi command failed" }
        }

        Write-Log "GPU detected: $nvidiaInfo"
        Write-Host "[OK] NVIDIA GPU detected" -ForegroundColor Green

        # Check compute capability (require 5.0+ for CUDA 13.0 support)
        $gpuInfo = & $nvidiaSmi --query-gpu=compute_cap --format=csv,noheader 2>$null
        if ($gpuInfo -match "(\d+)\.(\d+)") {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $capability = "{0}.{1}" -f $major, $minor
            $capabilityFloat = [double]"$major.$minor"

            Write-Log "Compute capability: $capability"
            Write-Host "GPU Compute Capability: $capability" -ForegroundColor Cyan

            # Check PyTorch compatibility
            # PyTorch 2.9+ requires compute capability >= 7.5 (sm_75) - Turing/Volta and newer
            $pytorchMinCapability = 7.5

            Write-Host "PyTorch 2.9+ Minimum Required: sm_75 (7.5+)" -ForegroundColor Cyan

            if ($capabilityFloat -ge $pytorchMinCapability) {
                Write-Host "[OK] GPU is compatible with PyTorch 2.9+ (compute capability $capability >= 7.5)" -ForegroundColor Green
                Write-Host "     CUDA acceleration will be available" -ForegroundColor Green
                Write-Log "GPU is PyTorch compatible (compute capability $capability >= 7.5)"
                return @{ Available = $true; ComputeCapability = $capability }
            } else {
                # GPU exists but isn't compatible with PyTorch 2.9+
                Write-Host ""
                Write-Host "[WARNING] GPU Not Compatible with PyTorch 2.9+" -ForegroundColor Yellow
                Write-Host "   Your GPU: Compute Capability $capability (sm_$major$minor)" -ForegroundColor Yellow
                Write-Host "   PyTorch 2.9+ requires: 7.5+ (sm_75+)" -ForegroundColor Yellow
                Write-Host ""

                # Determine architecture
                $arch = if ($capabilityFloat -ge 6.0) { "Pascal (2016)" }
                        elseif ($capabilityFloat -ge 5.0) { "Maxwell (2014)" }
                        else { "Kepler or older (2012-)" }

                Write-Host "   Explanation:" -ForegroundColor Yellow
                Write-Host "   - Your GPU is based on $arch architecture" -ForegroundColor Yellow
                Write-Host "   - PyTorch 2.9+ dropped support for GPUs older than Turing/Volta (2018)" -ForegroundColor Yellow
                Write-Host "   - Supported GPUs: RTX 20/30/40 series, Tesla V100+, A100, H100" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "   Options:" -ForegroundColor Yellow
                Write-Host "   1. Continue with CPU mode (slower but works fine)" -ForegroundColor Yellow
                Write-Host "   2. Downgrade PyTorch to version 2.4 to use this GPU" -ForegroundColor Yellow
                Write-Host "   3. Upgrade GPU to RTX 2060 or newer for CUDA support" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "   The installer will configure the service to run in CPU mode." -ForegroundColor Cyan
                Write-Host ""

                Write-Log "GPU compute capability $capability is below PyTorch 2.9 requirement (7.5)"
                return @{ Available = $false; Reason = "PyTorch incompatible - compute capability $capability < 7.5"; ComputeCapability = $capability }
            }
        }

        return @{ Available = $true; ComputeCapability = "Unknown" }
    } catch {
        Write-Log "Exception during GPU detection: $_" "WARNING"
        return @{ Available = $false; Reason = "Detection failed: $_" }
    }
}

function Install-Cuda {
    param(
        [string]$PythonExe
    )

    Write-Header "Setting up CUDA 13.0"

    $cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0"

    if (Test-Path $cudaPath) {
        Write-Log "CUDA 13.0 already installed at $cudaPath"
        Write-Host "[OK] CUDA 13.0 already installed" -ForegroundColor Green
        Update-ProgressWindow "CUDA 13.0 already installed at $cudaPath"
        return $true
    }

    try {
        Write-Host "Downloading CUDA 13.0..." -ForegroundColor Cyan
        Write-Log "Starting CUDA 13.0 download and installation"
        Update-ProgressWindow "Downloading CUDA 13.0 installer (this may take 5-10 minutes)..."

        # Create temp directory with random name for security
        $randomName = [System.IO.Path]::GetRandomFileName()
        $tempDir = Join-Path $env:TEMP "cuda_install_$randomName"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $cudaInstaller = Join-Path $tempDir "cuda_13.0_windows_network.exe"

        if (-not (Test-Path $cudaInstaller)) {
            $downloadUrl = "https://developer.download.nvidia.com/compute/cuda/13.0/local_installers/cuda_13.0.0_528.33_windows.exe"

            Write-Host "This may take a few minutes..." -ForegroundColor Yellow
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $cudaInstaller)
            Write-Log "CUDA installer downloaded"
            Update-ProgressWindow "CUDA 13.0 installer downloaded successfully"
        } else {
            Update-ProgressWindow "CUDA 13.0 installer found in cache"
        }

        Write-Host "Installing CUDA 13.0 (this may take 10+ minutes)..." -ForegroundColor Cyan
        Update-ProgressWindow "Installing CUDA 13.0 (this may take 10-15 minutes)..."
        & $cudaInstaller -s | Out-Null

        Write-Log "CUDA installation completed"
        Update-ProgressWindow "CUDA 13.0 installation completed"
        return $true
    } catch {
        Write-Log "CUDA installation failed (non-critical): $_" "WARNING"
        Write-Host "[WARNING] CUDA installation failed, will use CPU mode" -ForegroundColor Yellow
        Update-ProgressWindow "CUDA installation failed - falling back to CPU mode"
        return $false
    }
}

# ============================================================================
# Interactive Configuration
# ============================================================================
function Get-ModelSelection {
    Write-Header "Whisper Model Selection"

    $models = @(
        @{ Name = "tiny";   Params = "39M";    Vram = "~1 GB";  Speed = "~10x" },
        @{ Name = "base";   Params = "74M";    Vram = "~1 GB";  Speed = "~7x" },
        @{ Name = "small";  Params = "244M";   Vram = "~2 GB";  Speed = "~4x" },
        @{ Name = "medium"; Params = "769M";   Vram = "~5 GB";  Speed = "~2x" },
        @{ Name = "large";  Params = "1550M";  Vram = "~10 GB"; Speed = "~1x" },
        @{ Name = "turbo";  Params = "809M";   Vram = "~6 GB";  Speed = "~8x" }
    )

    Write-Host "`nAvailable Models:" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor Cyan

    for ($i = 0; $i -lt $models.Count; $i++) {
        $m = $models[$i]
        Write-Host "$($i+1). $($m.Name.PadRight(10)) | Params: $($m.Params.PadRight(8)) | VRAM: $($m.Vram.PadRight(8)) | Speed: $($m.Speed)"
    }

    Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor Cyan

    do {
        [int]$choice = Read-Host "Select model (1-6)"
        if ($choice -ge 1 -and $choice -le 6) {
            $selected = $models[$choice - 1]
            Write-Log "Model selected: $($selected.Name)"
            return $selected.Name
        }
        Write-Host "Invalid selection. Please enter 1-6." -ForegroundColor Yellow
    } while ($true)
}

function Test-PortAvailability {
    param(
        [int]$Port,
        [string]$HostAddress = "127.0.0.1"
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($HostAddress, $Port).Wait(500) | Out-Null

        if ($tcpClient.Connected) {
            $tcpClient.Close()
            return $false  # Port is in use
        }
        return $true  # Port is available
    } catch {
        # If connection fails, port is available
        return $true
    }
}

function Get-PortSelection {
    Write-Header "Port Configuration"

    # Check if service exists and get its current port
    $serviceName = "whisper-api"
    $currentServicePort = $null
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($service) {
        # Try to get current port from service environment
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Environment"
        if (Test-Path $regPath) {
            $currentServicePort = (Get-ItemProperty -Path $regPath -Name "WHISPER_PORT" -ErrorAction SilentlyContinue).WHISPER_PORT
            if ($currentServicePort) {
                Write-Host "Current service port: $currentServicePort" -ForegroundColor Cyan
            }
        }
    }

    if (-not $currentServicePort) {
        Write-Host "Default port: 4444" -ForegroundColor Cyan
    }

    Write-Host "Note: Port should be between 1024 and 65535`n" -ForegroundColor Gray

    do {
        $portInput = Read-Host "Enter port number (or press Enter for $(if ($currentServicePort) { $currentServicePort } else { '4444' }))"

        if ([string]::IsNullOrWhiteSpace($portInput)) {
            $port = if ($currentServicePort) { [int]$currentServicePort } else { 4444 }
        } else {
            if (-not [int]::TryParse($portInput, [ref]$port)) {
                Write-Host "Invalid port number. Please enter a valid integer." -ForegroundColor Yellow
                continue
            }

            if ($port -lt 1024 -or $port -gt 65535) {
                Write-Host "Port must be between 1024 and 65535." -ForegroundColor Yellow
                continue
            }
        }

        # Check if port is available
        Write-Host "Checking if port $port is available..." -ForegroundColor Cyan
        if (Test-PortAvailability -Port $port) {
            Write-Host "[OK] Port $port is available" -ForegroundColor Green
            Write-Log "Port selected: $port (verified available)"
            return $port
        } else {
            # Port is in use - check if it's our service (upgrade scenario)
            if ($service -and $currentServicePort -eq $port) {
                Write-Host "[OK] Port $port is in use by the existing whisper-api service (upgrade)" -ForegroundColor Green
                Write-Log "Port $port is in use by existing whisper-api service (upgrade scenario)"
                return $port
            } else {
                # Port is in use by another application
                Write-Host "[WARNING] Port $port is already in use by another application" -ForegroundColor Yellow
                Write-Host "The service will be configured to use this port anyway." -ForegroundColor Yellow
                Write-Host "You may need to stop the other application or change the port later.`n" -ForegroundColor Yellow
                Write-Log "WARNING: Port $port is in use by another application (not whisper-api)" "WARNING"

                # Store warning for end of script
                $script:PortInUseWarning = "Port $port is already in use by another application (not whisper-api service)"

                return $port
            }
        }
    } while ($true)
}

function Get-CudaPreference {
    param([bool]$IsAvailable)

    Write-Header "CUDA Configuration"

    if (-not $IsAvailable) {
        Write-Host "GPU detection shows: CUDA is NOT available" -ForegroundColor Yellow
        Write-Host "The service will run on CPU mode." -ForegroundColor Cyan
        Write-Log "CUDA disabled - GPU not compatible"
        return $false
    }

    Write-Host "GPU detection shows: CUDA is available" -ForegroundColor Green
    $useCuda = Read-Host "Enable CUDA acceleration? (Y/n) [default: Yes]"

    # Default to yes if empty input
    if ([string]::IsNullOrWhiteSpace($useCuda)) {
        $useCuda = "y"
    }

    $result = $useCuda -match "^[yY]"
    Write-Log "CUDA preference: $result"
    return $result
}

# ============================================================================
# Virtual Environment & Dependencies
# ============================================================================
function New-VirtualEnvironment {
    param(
        [string]$PythonExe,
        [string]$VenvPath
    )

    Write-Header "Creating Python Virtual Environment"

    if (Test-Path $VenvPath) {
        Write-Log "Virtual environment already exists at $VenvPath"
        Write-Host "[OK] Virtual environment already exists" -ForegroundColor Green
        Update-ProgressWindow "Virtual environment already exists at $VenvPath"
        return $true
    }

    try {
        Write-Host "Creating venv at $VenvPath..." -ForegroundColor Cyan
        Write-Log "Creating venv: $VenvPath"
        Update-ProgressWindow "Creating Python virtual environment (this may take 1-2 minutes)..."

        & "$PythonExe" -m venv "$VenvPath"

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Virtual environment created successfully"
            Write-Host "[OK] Virtual environment created" -ForegroundColor Green
            Update-ProgressWindow "Virtual environment created successfully at $VenvPath"
            return $true
        } else {
            throw "venv creation failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Log "ERROR: Failed to create virtual environment: $_" "ERROR"
        Update-ProgressWindow "ERROR: Failed to create virtual environment - $_"
        throw $_
    }
}

function Install-Dependencies {
    param(
        [string]$PythonExe,
        [bool]$UseCuda
    )

    Write-Header "Installing Python Dependencies"

    # Get pip path from Python directory
    $pythonDir = Split-Path $PythonExe
    $pipExe = Join-Path $pythonDir "Scripts\pip.exe"

    # Check if pip.exe exists
    $pipExeExists = Test-Path $pipExe
    Write-Log "Checking pip.exe at $pipExe - Exists: $pipExeExists"

    # Also check if pip module is available
    $pipModuleTest = & "$PythonExe" -m pip --version 2>&1
    $pipModuleWorks = $LASTEXITCODE -eq 0
    Write-Log "pip module test - Exit code: $LASTEXITCODE, Output: $pipModuleTest"

    if (-not $pipExeExists -and -not $pipModuleWorks) {
        Write-Log "ERROR: Neither pip.exe nor pip module is available" "ERROR"
        throw "pip is not installed or not working. Please check the installation logs."
    }

    try {
        # Determine pip command - prefer pip.exe if it exists, otherwise use python -m pip
        if ($pipExeExists) {
            Write-Log "Using pip.exe at $pipExe"
            $pipCmd = $pipExe
            $pipArgs = @()
        } else {
            Write-Log "pip.exe not found, using python -m pip"
            Write-Host "Note: Using 'python -m pip' instead of pip.exe" -ForegroundColor Yellow
            Update-ProgressWindow "Using 'python -m pip' for package installation"
            $pipCmd = $PythonExe
            $pipArgs = @("-m", "pip")
        }

        # Upgrade pip
        Write-Host "Upgrading pip..." -ForegroundColor Cyan
        Write-Log "Running: $pipCmd $($pipArgs -join ' ') install --upgrade pip"
        Update-ProgressWindow "Upgrading pip..."

        try {
            # Capture output explicitly before checking exit code
            $pipUpgradeOutput = & "$pipCmd" @pipArgs install --upgrade pip 2>&1 | Out-String
            $pipUpgradeExitCode = $LASTEXITCODE

            Write-Log "pip upgrade output: $pipUpgradeOutput"
            Write-Log "pip upgrade exit code: $pipUpgradeExitCode"

            if ($pipUpgradeExitCode -ne 0) {
                Write-Log "WARNING: pip upgrade returned exit code $pipUpgradeExitCode, but continuing..." "WARNING"
            }
        } catch {
            Write-Log "ERROR during pip upgrade: $_" "ERROR"
            Write-Log "Exception: $($_.Exception.Message)" "ERROR"
            # Don't throw - continue even if pip upgrade fails
            Write-Log "Continuing despite pip upgrade error..." "WARNING"
        }

        Update-ProgressWindow "Pip upgrade completed"

        # Core dependencies
        $corePackages = @(
            "fastapi",
            "uvicorn[standard]",
            "faster-whisper",
            "pydantic",
            "python-multipart",
            "numpy",
            "soundfile",
            "pywin32"
        )

        Write-Host "Installing core packages..." -ForegroundColor Cyan
        Write-Log "Installing core packages: $($corePackages -join ', ')"
        Update-ProgressWindow "Installing core packages: fastapi, uvicorn, faster-whisper, pydantic, python-multipart..."

        try {
            $coreOutput = & "$pipCmd" @pipArgs install $corePackages 2>&1 | Out-String
            $coreExitCode = $LASTEXITCODE

            Write-Log "Core packages output: $coreOutput"
            Write-Log "Core packages install exit code: $coreExitCode"

            if ($coreExitCode -ne 0) {
                throw "Failed to install core packages (exit code: $coreExitCode)"
            }
        } catch {
            Write-Log "ERROR during core packages install: $_" "ERROR"
            throw $_
        }

        Update-ProgressWindow "Core packages installed successfully"

        # PyTorch with or without CUDA
        if ($UseCuda) {
            Write-Host "Installing PyTorch with CUDA support..." -ForegroundColor Cyan
            Write-Log "Installing PyTorch with CUDA support (cu130)"
            Update-ProgressWindow "Installing PyTorch with CUDA support (this may take several minutes)..."

            try {
                $torchOutput = & "$pipCmd" @pipArgs install torch torchvision --index-url https://download.pytorch.org/whl/cu130 2>&1 | Out-String
                $torchExitCode = $LASTEXITCODE

                Write-Log "PyTorch CUDA output: $torchOutput"
                Write-Log "PyTorch CUDA install exit code: $torchExitCode"

                if ($torchExitCode -ne 0) {
                    throw "Failed to install PyTorch with CUDA (exit code: $torchExitCode)"
                }
            } catch {
                Write-Log "ERROR during PyTorch CUDA install: $_" "ERROR"
                throw $_
            }
        } else {
            Write-Host "Installing PyTorch (CPU mode)..." -ForegroundColor Cyan
            Write-Log "Installing PyTorch in CPU mode"
            Update-ProgressWindow "Installing PyTorch (CPU mode - this may take several minutes)..."

            try {
                $torchOutput = & "$pipCmd" @pipArgs install torch torchvision 2>&1 | Out-String
                $torchExitCode = $LASTEXITCODE

                Write-Log "PyTorch CPU output: $torchOutput"
                Write-Log "PyTorch CPU install exit code: $torchExitCode"

                if ($torchExitCode -ne 0) {
                    throw "Failed to install PyTorch CPU (exit code: $torchExitCode)"
                }
            } catch {
                Write-Log "ERROR during PyTorch CPU install: $_" "ERROR"
                throw $_
            }
        }

        Write-Log "All dependencies installed successfully"
        Write-Host "[OK] All dependencies installed" -ForegroundColor Green
        Update-ProgressWindow "All Python dependencies installed successfully"
        return $true
    } catch {
        Write-Log "ERROR: Failed to install dependencies: $_" "ERROR"
        Update-ProgressWindow "ERROR: Failed to install dependencies - $_"
        throw $_
    }
}

# ============================================================================
# Service Creation
# ============================================================================
function New-WhisperService {
    param(
        [string]$InstallPath,
        [string]$Model,
        [int]$Port,
        [bool]$UseCuda
    )

    Write-Header "Creating Windows Service"

    $serviceName = "whisper-api"
    $pythonExe = "$InstallPath\.python\python.exe"

    # Check if service exists
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $serviceExists = $null -ne $service

    if ($serviceExists) {
        Write-Log "Service $serviceName already exists, will update configuration"
        Write-Host "Updating existing service..." -ForegroundColor Cyan
        Update-ProgressWindow "Stopping existing whisper-api service..."

        # Stop the service if it's running
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Update-ProgressWindow "Service stopped, will update configuration"
    }

    try {
        # Create logs directory
        $logsPath = "$InstallPath\logs"
        if (-not (Test-Path $logsPath)) {
            New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
            Write-Log "Created logs directory: $logsPath"
            Update-ProgressWindow "Created logs directory at $logsPath"
        }

        # Verify required files exist (MSI installer should have placed them)
        $serverPy = "$InstallPath\server.py"
        $servicePy = "$InstallPath\whisper_service.py"

        if (-not (Test-Path $serverPy)) {
            Write-Log "ERROR: server.py not found at $serverPy" "ERROR"
            throw "server.py not found in installation directory. MSI installation may have failed."
        }

        if (-not (Test-Path $servicePy)) {
            Write-Log "ERROR: whisper_service.py not found at $servicePy" "ERROR"
            throw "whisper_service.py not found in installation directory. MSI installation may have failed."
        }

        Write-Log "Verified server.py and whisper_service.py are present"
        Update-ProgressWindow "Verified required Python files"

        # Remove old service if it exists (to switch from direct Python to pywin32 service)
        if ($serviceExists) {
            Write-Host "Removing old service to upgrade to pywin32 service..." -ForegroundColor Cyan
            Write-Log "Removing existing service: $serviceName"
            Update-ProgressWindow "Removing old service..."

            try {
                # Try to uninstall using pywin32 first (in case it's already a pywin32 service)
                & "$pythonExe" "$servicePy" remove 2>&1 | Out-Null
            } catch {}

            # Also try sc.exe delete to ensure it's gone
            sc.exe delete $serviceName 2>&1 | Out-Null
            Start-Sleep -Seconds 2

            Write-Log "Old service removed"
            Update-ProgressWindow "Old service removed"
        }

        # Create Windows Service using pywin32
        Write-Host "Installing pywin32 service: $serviceName" -ForegroundColor Cyan
        Write-Log "Installing Windows Service using pywin32: $serviceName"
        Update-ProgressWindow "Installing Windows Service using pywin32..."

        try {
            # Install the service using pywin32
            $installOutput = & "$pythonExe" "$servicePy" install 2>&1 | Out-String
            Write-Log "Service install output: $installOutput"

            if ($LASTEXITCODE -ne 0) {
                throw "Service installation failed with exit code $LASTEXITCODE"
            }

            Write-Log "Service installed successfully"
            Update-ProgressWindow "Service registered with Windows"

            # Update service description
            $description = "OpenAI Whisper API compatible transcription service (Model: $Model, Port: $Port, CUDA: $UseCuda)"
            sc.exe description $serviceName $description | Out-Null

            # Set to automatic start
            sc.exe config $serviceName start= auto | Out-Null

        } catch {
            Write-Log "ERROR: Failed to install pywin32 service: $_" "ERROR"
            throw $_
        }

        # Set environment variables for the service
        Write-Host "Configuring service environment variables..." -ForegroundColor Cyan
        Update-ProgressWindow "Configuring service environment variables..."

        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

        # Add Environment subkey if it doesn't exist
        if (-not (Test-Path "$regPath\Environment")) {
            New-Item -Path "$regPath\Environment" -Force | Out-Null
        }

        # Set environment variables in registry
        $envVars = @{
            "WHISPER_MODEL" = $Model
            "WHISPER_PORT" = $Port.ToString()
            "WHISPER_HOST" = "127.0.0.1"
            "CUDA_DEVICE_ID" = "0"
        }

        if (-not $UseCuda) {
            $envVars["CUDA_VISIBLE_DEVICES"] = ""
        }

        foreach ($key in $envVars.Keys) {
            Set-ItemProperty -Path "$regPath\Environment" -Name $key -Value $envVars[$key]
            Write-Log "Set environment variable: $key=$($envVars[$key])"
        }

        Update-ProgressWindow "Environment variables configured"
        Write-Host "[OK] Service created successfully" -ForegroundColor Green
        Write-Log "Service configuration completed"

        return @{
            ServiceName = $serviceName
            Status = "Created"
            Model = $Model
            Port = $Port
            CudaEnabled = $UseCuda
        }
    } catch {
        Write-Log "ERROR: Failed to create service: $_" "ERROR"
        Update-ProgressWindow "ERROR: Failed to create service - $_"
        throw $_
    }
}

# ============================================================================
# Service Testing
# ============================================================================
function Start-WhisperService {
    param([string]$ServiceName)

    Write-Header "Starting Service"

    try {
        Write-Host "Starting service: $ServiceName" -ForegroundColor Cyan
        Update-ProgressWindow "Starting Windows Service..."
        Start-Service -Name $ServiceName -ErrorAction Stop

        # Wait for service to start
        Update-ProgressWindow "Waiting for service to start..."
        Start-Sleep -Seconds 3

        $service = Get-Service -Name $ServiceName
        if ($service.Status -eq "Running") {
            Write-Log "Service started successfully"
            Write-Host "[OK] Service is running" -ForegroundColor Green
            Update-ProgressWindow "Service is running successfully!"
            return $true
        } else {
            Write-Log "Service failed to start (status: $($service.Status))" "WARNING"
            Write-Host "[WARNING] Service status: $($service.Status)" -ForegroundColor Yellow
            Update-ProgressWindow "Service status: $($service.Status) - may start on next boot"
            return $false
        }
    } catch {
        Write-Log "ERROR: Failed to start service: $_" "WARNING"
        Write-Host "[WARNING] Could not start service immediately (it may start on next boot)" -ForegroundColor Yellow
        Update-ProgressWindow "Service will start on next system boot"
        return $false
    }
}

# ============================================================================
# Main Installation Flow
# ============================================================================
function Start-Installation {
    try {
        # Initialize logging immediately
        $logDir = Split-Path $script:LogPath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Write-Log "========================================" "INFO"
        Write-Log "Installation process started" "INFO"
        Write-Log "IsInteractive: $script:IsInteractive" "INFO"
        Write-Log "InstallPath: $InstallPath" "INFO"

        # Require interactive mode
        if (-not $script:IsInteractive) {
            Write-Log "ERROR: This installer requires interactive mode" "ERROR"
            Write-Host "`nERROR: This installer must be run in interactive mode." -ForegroundColor Red
            Write-Host "Please run the script directly from PowerShell:" -ForegroundColor Yellow
            Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor Cyan
            Write-Host "`nDo NOT use -NonInteractive flag.`n" -ForegroundColor Yellow
            Read-Host "Press Enter to exit"
            exit 1
        }

        Write-Log "Interactive mode confirmed" "INFO"

        Write-Header "Whisper API Windows Installer"
        Write-Host "Installation Path: $InstallPath`n" -ForegroundColor Cyan
        Write-Log "Installation started. Target path: $InstallPath"

        # Pre-flight checks
        Test-AdminPrivileges
        Test-InternetConnectivity
        Test-FFmpegInstallation

        # Get user preferences
        Write-Host "`n" -ForegroundColor Cyan
        $model = Get-ModelSelection
        $port = Get-PortSelection
        Write-Host "`n" -ForegroundColor Cyan

        # GPU detection
        $gpuInfo = Test-CudaCapability
        $useCuda = Get-CudaPreference -IsAvailable $gpuInfo.Available

        # Create installation directory
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Log "Created installation directory: $InstallPath"
            Update-ProgressWindow "Created installation directory"
        }

        # Clean up old Python installation for fresh install
        $pythonInstallDir = Join-Path $InstallPath ".python"
        if (Test-Path $pythonInstallDir) {
            Write-Log "Found existing Python installation at $pythonInstallDir - removing for clean install"
            Write-Host "Removing old Python installation for clean install..." -ForegroundColor Yellow
            Update-ProgressWindow "Removing old Python installation..."

            try {
                # Stop the service first if it's running (files may be locked)
                $serviceName = "whisper-api"
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($service -and $service.Status -eq 'Running') {
                    Write-Log "Stopping service $serviceName before removing Python..."
                    Write-Host "Stopping whisper-api service..." -ForegroundColor Cyan
                    try {
                        Stop-Service -Name $serviceName -Force -ErrorAction Stop
                        Write-Log "Service stopped, waiting for processes to release files..."
                        Write-Host "Waiting for service to fully stop..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 5  # Increased wait time
                        Write-Log "Service stopped successfully"
                        Write-Host "[OK] Service stopped" -ForegroundColor Green
                    } catch {
                        Write-Log "WARNING: Failed to stop service: $_" "WARNING"
                        Write-Host "[WARNING] Could not stop service, some files may be locked" -ForegroundColor Yellow
                    }
                }

                # Stop any remaining Python processes from this installation
                Write-Log "Checking for Python processes from installation directory..."
                $pythonProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.Path -and $_.Path.StartsWith($pythonInstallDir, [StringComparison]::OrdinalIgnoreCase)
                }

                if ($pythonProcesses) {
                    Write-Log "Found $($pythonProcesses.Count) process(es) using Python directory, stopping..."
                    Write-Host "Stopping Python processes..." -ForegroundColor Cyan
                    foreach ($proc in $pythonProcesses) {
                        Write-Log "Stopping process: $($proc.Name) (PID: $($proc.Id))"
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    }
                    Write-Log "Waiting for file handles to release..."
                    Start-Sleep -Seconds 3  # Additional wait for file handles to release
                    Write-Host "[OK] Processes stopped" -ForegroundColor Green
                }

                # Remove the directory
                Remove-Item -Path $pythonInstallDir -Recurse -Force -ErrorAction Stop
                Write-Log "Old Python installation removed successfully"
                Write-Host "[OK] Old Python installation removed" -ForegroundColor Green
                Update-ProgressWindow "Old Python installation removed"
            } catch {
                Write-Log "WARNING: Could not fully remove old Python installation: $_" "WARNING"
                Write-Host "[WARNING] Could not fully remove old installation, will try to install over it" -ForegroundColor Yellow
                Update-ProgressWindow "WARNING: Partial removal, continuing..."
            }
        }

        # Installation steps
        Update-ProgressWindow "Starting Python installation (step 1/4)..."
        $pythonExe = Install-Python

        # Add Python and Scripts to PATH for this session
        $pythonDir = Split-Path $pythonExe -Parent
        $scriptsDir = Join-Path $pythonDir "Scripts"
        $env:Path = "$pythonDir;$scriptsDir;$env:Path"
        Write-Log "Added to PATH: $pythonDir and $scriptsDir"
        Write-Host "[OK] Python Scripts folder added to PATH" -ForegroundColor Green

        # Note: Portable Python is already isolated, no need for venv
        Write-Log "Using portable Python at $pythonExe (no venv needed)"
        Update-ProgressWindow "Python is ready (portable installation)"

        # Note: No need to install CUDA toolkit - PyTorch includes CUDA libraries
        if ($useCuda -and $gpuInfo.Available) {
            Write-Log "CUDA GPU detected - will install PyTorch with CUDA support"
            Update-ProgressWindow "GPU detected - will use CUDA acceleration"
        } else {
            Write-Log "No CUDA GPU or CUDA disabled - will use CPU mode"
            Update-ProgressWindow "No GPU detected - will use CPU mode"
        }

        Update-ProgressWindow "Installing Python dependencies (step 2/3)..."
        Install-Dependencies -PythonExe $pythonExe -UseCuda $useCuda

        # Create service
        Update-ProgressWindow "Creating Windows Service (step 3/3)..."
        $serviceInfo = New-WhisperService -InstallPath $InstallPath -Model $model -Port $port -UseCuda $useCuda

        # Start service
        Update-ProgressWindow "Starting Whisper API service..."
        Start-WhisperService -ServiceName $serviceInfo.ServiceName

        # Installation summary
        Update-ProgressWindow "Installation completed successfully!"
        Write-Header "Installation Complete!"
        Write-Host @"
Service Configuration:
  Name:        $($serviceInfo.ServiceName)
  Status:      $($serviceInfo.Status)
  Model:       $($serviceInfo.Model)
  Port:        $($serviceInfo.Port)
  CUDA:        $($serviceInfo.CudaEnabled)
  Location:    $InstallPath

Next Steps:
  1. Copy your server.py to: $InstallPath\server.py
  2. Test the API: http://127.0.0.1:$($serviceInfo.Port)/v1/health
  3. View logs: $InstallPath\logs\

Service Management:
  Start:       net start whisper-api
  Stop:        net stop whisper-api
  Restart:     net stop whisper-api; net start whisper-api
  Status:      Get-Service whisper-api
  Remove:      sc delete whisper-api

Installation Logs:
  Primary:     $script:LogPathTemp
  Secondary:   $script:LogPathInstall
"@ -ForegroundColor Green

        # Keep progress window visible for 5 seconds before closing
        if ($script:ProgressWindow) {
            Update-ProgressWindow ""
            Update-ProgressWindow "=========================================="
            Update-ProgressWindow "Installation completed successfully!"
            Update-ProgressWindow "The service is now installed and running."
            Update-ProgressWindow "This window will close in a moment..."
            Update-ProgressWindow "=========================================="
            Start-Sleep -Seconds 5
            $script:ProgressWindow.Dispatcher.InvokeShutdown() | Out-Null
        }

        Write-Log "Installation completed successfully"

        # Show warnings if port was in use
        if ($script:PortInUseWarning) {
            Write-Host "`n"
            Write-Host ("="*70) -ForegroundColor Yellow
            Write-Host "WARNING" -ForegroundColor Yellow
            Write-Host ("="*70) -ForegroundColor Yellow
            Write-Host $script:PortInUseWarning -ForegroundColor Yellow
            Write-Host "The service may fail to start if another application is using the port." -ForegroundColor Yellow
            Write-Host "Consider stopping the other application or reconfiguring the port." -ForegroundColor Yellow
            Write-Host ("="*70) -ForegroundColor Yellow
            Write-Host "`n"
        }

    } catch {
        $errorMsg = $_.ToString()
        $errorLine = $_.InvocationInfo.ScriptLineNumber
        $errorScript = $_.InvocationInfo.ScriptName
        Write-Log "FATAL ERROR at line $errorLine in $errorScript" "ERROR"
        Write-Log "Error: $errorMsg" "ERROR"
        Write-Log "Exception: $($_.Exception)" "ERROR"
        Write-Host "`nInstallation failed!" -ForegroundColor Red
        Write-Host "Error: $errorMsg" -ForegroundColor Red
        Write-Host "`nLog files:" -ForegroundColor Yellow
        Write-Host "  Primary:   $script:LogPathTemp" -ForegroundColor Yellow
        if (Test-Path (Split-Path $script:LogPathInstall)) {
            Write-Host "  Secondary: $script:LogPathInstall" -ForegroundColor Yellow
        }
        if ($script:ProgressWindow) {
            Update-ProgressWindow ""
            Update-ProgressWindow "=========================================="
            Update-ProgressWindow "INSTALLATION FAILED"
            Update-ProgressWindow ""
            Update-ProgressWindow "Error: $errorMsg"
            Update-ProgressWindow ""
            Update-ProgressWindow "Check log file for details:"
            Update-ProgressWindow "  $script:LogPathTemp"
            if (Test-Path (Split-Path $script:LogPathInstall)) {
                Update-ProgressWindow "  $script:LogPathInstall"
            }
            Update-ProgressWindow "=========================================="
            Start-Sleep -Seconds 5
            $script:ProgressWindow.Dispatcher.InvokeShutdown() | Out-Null
        }
        exit 1
    }
}

# ============================================================================
# Execute
# ============================================================================
Start-Installation

# Pause at end if there were warnings or if in interactive mode
if ($script:IsInteractive) {
    if ($script:PortInUseWarning) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
