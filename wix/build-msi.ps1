<#
.SYNOPSIS
    Build Whisper API MSI installer using WiX Toolset 3
.DESCRIPTION
    Creates a professional MSI installer package for Whisper API
    Requires WiX Toolset 3.11+ to be installed
.PARAMETER OutputDir
    Output directory for the MSI (default: current directory)
.PARAMETER Version
    MSI version string (default: 1.0.0.0)
.PARAMETER WixPath
    Path to WiX installation (auto-detected if not specified)
.EXAMPLE
    .\build-msi.ps1
    .\build-msi.ps1 -OutputDir "..\dist" -Version "1.0.1.0"
#>

param(
    [string]$OutputDir = ".",
    [string]$Version = "1.0.0.0",
    [string]$DisplayVersion = "",
    [string]$WixPath = $null
)

$ErrorActionPreference = "Stop"

# If DisplayVersion not provided, use Version
if ([string]::IsNullOrWhiteSpace($DisplayVersion)) {
    $DisplayVersion = $Version
}

# ============================================================================
# Utility Functions
# ============================================================================
function Write-Header {
    param([string]$Text)
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan
}

function Find-WixPath {
    Write-Host "Searching for WiX Toolset..." -ForegroundColor Cyan

    # Common WiX installation paths
    $possiblePaths = @(
        "C:\Program Files (x86)\WiX Toolset v3.11",
        "C:\Program Files (x86)\WiX Toolset v3.14",
        "C:\Program Files\WiX Toolset v3.11",
        "C:\Program Files\WiX Toolset v3.14"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Host "Found WiX at: $path" -ForegroundColor Green
            return $path
        }
    }

    Write-Host "[ERROR] WiX Toolset not found!" -ForegroundColor Red
    Write-Host "WiX Toolset is required to build the MSI installer." -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "To install WiX:" -ForegroundColor Yellow
    Write-Host "  - Download from: https://github.com/wixtoolset/wix3/releases" -ForegroundColor Yellow
    Write-Host "  - Install WiX Toolset v3.11 or later" -ForegroundColor Yellow
    Write-Host "  - Install Visual Studio Build Tools (if not already installed)" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Or install via Chocolatey:" -ForegroundColor Yellow
    Write-Host "  choco install wixtoolset" -ForegroundColor Yellow
    Write-Host "  choco install visualstudio2019buildtools" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    return $null
}

function Test-SourceFiles {
    Write-Host "Checking source files..." -ForegroundColor Cyan

    $requiredFiles = @(
        "..\install-whisper.ps1",
        "..\server.py",
        "..\whisper_service.py",
        "..\uninstall-whisper.ps1",
        "..\README.md",
        "Product.wxs"
    )

    $allFound = $true
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $PSScriptRoot $file
        if (Test-Path $fullPath) {
            Write-Host "  [OK] $file" -ForegroundColor Green
        } else {
            Write-Host "  [MISSING] $file" -ForegroundColor Red
            $allFound = $false
        }
    }

    return $allFound
}

function Build-Msi {
    param(
        [string]$WixPath,
        [string]$OutputDir,
        [string]$Version
    )

    Write-Header "Building MSI Package"

    $candle = Join-Path $WixPath "bin\candle.exe"
    $light = Join-Path $WixPath "bin\light.exe"

    # Verify tools exist
    foreach ($tool in @($candle, $light)) {
        if (-not (Test-Path $tool)) {
            throw "WiX tool not found: $tool"
        }
    }

    $scriptDir = $PSScriptRoot
    $wxsFile = Join-Path $scriptDir "Product.wxs"
    $wixobjDir = Join-Path $scriptDir "obj"
    $msiFileName = "Whisper-API-$DisplayVersion.msi"
    $msiOutput = Join-Path $OutputDir $msiFileName

    # Convert to absolute paths
    $scriptDir = (Get-Item $scriptDir).FullName
    $wixobjDir = (Get-Item $wixobjDir -ErrorAction SilentlyContinue).FullName
    if (-not $wixobjDir) {
        $wixobjDir = Join-Path $scriptDir "obj"
    }
    $msiOutput = (Get-Item $OutputDir -ErrorAction SilentlyContinue).FullName
    if (-not $msiOutput) {
        $msiOutput = Join-Path $OutputDir $msiFileName
    } else {
        $msiOutput = Join-Path $msiOutput $msiFileName
    }

    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Create obj directory
    if (-not (Test-Path $wixobjDir)) {
        New-Item -ItemType Directory -Path $wixobjDir -Force | Out-Null
    }

    # Clean old builds
    Remove-Item "$wixobjDir\*" -Force -ErrorAction SilentlyContinue

    try {
        # Step 1: Candle (compile WXS to WIX object)
        Write-Host "Step 1: Compiling WiX source (candle)..." -ForegroundColor Cyan
        Write-Host "  Input:  $wxsFile" -ForegroundColor Gray
        Write-Host "  Output: $wixobjDir" -ForegroundColor Gray

        $candleArgs = @(
            "-dSourceDir=$scriptDir"
            "-dProductVersion=$Version"
            "-out"
            "$wixobjDir\"
            "-ext"
            "WixUIExtension"
            "-ext"
            "WixUtilExtension"
            $wxsFile
        )
        & $candle @candleArgs

        if ($LASTEXITCODE -ne 0) {
            throw "Candle compilation failed with exit code $LASTEXITCODE"
        }

        Write-Host "[OK] Compilation successful" -ForegroundColor Green

        # Step 2: Light (link WIX objects to MSI)
        Write-Host "" -ForegroundColor Cyan
        Write-Host "Step 2: Linking WiX objects (light)..." -ForegroundColor Cyan
        Write-Host "  Input:  $wixobjDir\Product.wixobj" -ForegroundColor Gray
        Write-Host "  Output: $msiOutput" -ForegroundColor Gray

        & $light -out $msiOutput -ext WixUIExtension -ext WixUtilExtension -cultures:en-us "$wixobjDir\Product.wixobj" 2>&1 | Out-Null

        # Verify output file was created (light may return non-zero even on success)
        if (Test-Path $msiOutput) {
            $fileSize = (Get-Item $msiOutput).Length / 1MB
            $fileHash = (Get-FileHash -Path $msiOutput -Algorithm SHA256).Hash.Substring(0, 16)

            Write-Host ""
            Write-Host ("="*70) -ForegroundColor Green
            Write-Host "[OK] MSI package created successfully!" -ForegroundColor Green
            Write-Host ("="*70) -ForegroundColor Green

            Write-Host ""
            Write-Host "MSI Build Complete!" -ForegroundColor Green
            Write-Host "Output File:    $msiOutput" -ForegroundColor Green
            Write-Host "File Size:      $($fileSize.ToString('F2')) MB" -ForegroundColor Green
            Write-Host "SHA256 (short): $fileHash..." -ForegroundColor Green
            Write-Host "Version:        $Version" -ForegroundColor Green
            Write-Host ""

            Write-Host "Installation Instructions:" -ForegroundColor Green
            Write-Host "  - Double-click: $msiFileName" -ForegroundColor Green
            Write-Host "  - Follow the Windows Installer wizard" -ForegroundColor Green
            Write-Host "  - Click Install Whisper API in Start Menu" -ForegroundColor Green
            Write-Host "  - Follow the interactive setup prompts" -ForegroundColor Green
            Write-Host ""

            Write-Host "Distribution:" -ForegroundColor Green
            Write-Host "  - Share this MSI file with end users" -ForegroundColor Green
            Write-Host "  - Users need Windows 10/11 and admin rights" -ForegroundColor Green
            Write-Host "  - Internet connection required for downloads" -ForegroundColor Green
            Write-Host "  - Total install time: 10-20 minutes" -ForegroundColor Green
            Write-Host ""

            return $true
        } else {
            throw "MSI file was not created at expected path"
        }
    } catch {
        Write-Host "ERROR: Build failed" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "- Ensure all source files exist in the current directory" -ForegroundColor Yellow
        Write-Host "- Check that WiX Toolset is properly installed" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# Main
# ============================================================================
function Start-Build {
    try {
        Write-Header "Whisper API MSI Builder"

        Write-Host ""
        Write-Host "Configuration:" -ForegroundColor Cyan
        Write-Host "  Output Directory: $OutputDir" -ForegroundColor Cyan
        Write-Host "  Version:          $Version" -ForegroundColor Cyan
        Write-Host "  MSI Filename:     Whisper-API-$DisplayVersion.msi" -ForegroundColor Cyan
        Write-Host ""

        # Find WiX if not specified
        if (-not $WixPath) {
            $WixPath = Find-WixPath
            if (-not $WixPath) {
                exit 1
            }
        }

        Write-Host "  WiX Path:         $WixPath" -ForegroundColor Cyan
        Write-Host ""

        # Check source files
        if (-not (Test-SourceFiles)) {
            Write-Host "Missing required source files!" -ForegroundColor Red
            exit 1
        }

        # Build MSI
        if (Build-Msi -WixPath $WixPath -OutputDir $OutputDir -Version $Version) {
            Write-Host ""
            Write-Host "Next Steps:" -ForegroundColor Green
            Write-Host "  - Test the MSI on a clean Windows machine" -ForegroundColor Green
            Write-Host "  - Share Whisper-API-$DisplayVersion.msi with end users" -ForegroundColor Green
            Write-Host ""
            Write-Host "Requirements for Installation:" -ForegroundColor Green
            Write-Host "  - Windows 10 Build 14393 or later" -ForegroundColor Green
            Write-Host "  - Administrator privileges" -ForegroundColor Green
            Write-Host "  - Internet connection for downloads" -ForegroundColor Green
            Write-Host "  - 15 GB free disk space" -ForegroundColor Green
            Write-Host ""
        } else {
            exit 1
        }

    } catch {
        Write-Host ""
        Write-Host $PSItem -ForegroundColor Red
        exit 1
    }
}

Start-Build
