<#
.SYNOPSIS
    Check GPU and CUDA capability for Whisper API
.DESCRIPTION
    Validates whether the system GPU is compatible with CUDA 13.0
    Used by the installer and can be run standalone for troubleshooting
#>

function Test-CudaCapability {
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "GPU and CUDA Capability Check" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan

    $result = @{
        GPUFound = $false
        GPUName = $null
        DriverVersion = $null
        ComputeCapability = $null
        CudaCompatible = $false
        CudaVersion = $null
        Message = ""
    }

    # Step 1: Check nvidia-smi
    Write-Host "`nStep 1: Checking nvidia-smi..." -ForegroundColor Yellow
    try {
        $nvidiaOutput = & nvidia-smi --query-gpu=name,driver_version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ nvidia-smi not found or not working" -ForegroundColor Red
            $result.Message = "NVIDIA GPU not detected. GPU support unavailable."
            return $result
        }

        $result.GPUFound = $true
        Write-Host "✓ nvidia-smi is available" -ForegroundColor Green
    } catch {
        Write-Host "✗ Error executing nvidia-smi: $_" -ForegroundColor Red
        $result.Message = "Failed to check GPU: $_"
        return $result
    }

    # Step 2: Get GPU information
    Write-Host "`nStep 2: Getting GPU Information..." -ForegroundColor Yellow
    try {
        $gpuInfo = & nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>$null
        $parts = $gpuInfo -split ','

        if ($parts.Count -ge 3) {
            $result.GPUName = $parts[0].Trim()
            $result.DriverVersion = $parts[1].Trim()
            $result.ComputeCapability = $parts[2].Trim()

            Write-Host "GPU Name:            $($result.GPUName)" -ForegroundColor Cyan
            Write-Host "Driver Version:      $($result.DriverVersion)" -ForegroundColor Cyan
            Write-Host "Compute Capability:  $($result.ComputeCapability)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "✗ Error reading GPU info: $_" -ForegroundColor Red
    }

    # Step 3: Check compute capability for CUDA compatibility
    Write-Host "`nStep 3: Checking CUDA 13.0 Compatibility..." -ForegroundColor Yellow

    if ($result.ComputeCapability -match "(\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]

        # CUDA 13.0 requires compute capability 5.0 or higher
        if ($major -ge 5) {
            Write-Host "✓ GPU is compatible with CUDA 13.0" -ForegroundColor Green
            Write-Host "  Compute capability $($result.ComputeCapability) >= 5.0" -ForegroundColor Green
            $result.CudaCompatible = $true
            $result.Message = "GPU is CUDA 13.0 compatible"
        } else {
            Write-Host "✗ GPU compute capability is TOO OLD for CUDA 13.0" -ForegroundColor Red
            Write-Host "  Your GPU has compute capability $($result.ComputeCapability)" -ForegroundColor Red
            Write-Host "  CUDA 13.0 requires compute capability 5.0 or higher" -ForegroundColor Red
            Write-Host "  (Your $($result.GPUName) is from ~2012 or earlier)" -ForegroundColor Red
            $result.CudaCompatible = $false
            $result.Message = "GPU not compatible: compute capability $($result.ComputeCapability) < 5.0"
        }
    } else {
        Write-Host "? Could not parse compute capability" -ForegroundColor Yellow
    }

    # Step 4: Check CUDA installation
    Write-Host "`nStep 4: Checking CUDA Installation..." -ForegroundColor Yellow

    $cudaPaths = @(
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.1"
    )

    $cudaInstalled = $null
    foreach ($path in $cudaPaths) {
        if (Test-Path $path) {
            Write-Host "✓ CUDA found at: $path" -ForegroundColor Green
            $cudaInstalled = $path
            break
        }
    }

    if (-not $cudaInstalled) {
        Write-Host "✗ CUDA not installed" -ForegroundColor Yellow
        Write-Host "  (Will be installed during Whisper API setup if compatible)" -ForegroundColor Yellow
    }

    # Step 5: Check PyTorch/Torch
    Write-Host "`nStep 5: Checking PyTorch..." -ForegroundColor Yellow

    try {
        $pythonPath = "python.exe"
        $checkCuda = & python -c "import torch; print(f'PyTorch CUDA Available: {torch.cuda.is_available()}')" 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ PyTorch is installed" -ForegroundColor Green
            Write-Host "  $checkCuda" -ForegroundColor Cyan
        } else {
            Write-Host "- PyTorch not yet installed (will be installed during setup)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "- PyTorch check skipped" -ForegroundColor Cyan
    }

    # Summary
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host ("="*70) -ForegroundColor Cyan

    if ($result.CudaCompatible) {
        Write-Host "`n✓ GPU is ready for CUDA acceleration!" -ForegroundColor Green
        Write-Host "  Run: install-whisper.bat and select 'yes' for CUDA" -ForegroundColor Green
    } elseif ($result.GPUFound) {
        Write-Host "`n⚠ GPU found but NOT compatible with CUDA 13.0" -ForegroundColor Yellow
        Write-Host "  Run: install-whisper.bat and select 'no' for CUDA (CPU mode)" -ForegroundColor Yellow
    } else {
        Write-Host "`n- No compatible GPU found" -ForegroundColor Cyan
        Write-Host "  The API will run in CPU mode (slower but still functional)" -ForegroundColor Cyan
    }

    Write-Host "`n"
    return $result
}

# Run the check if called directly
if ($MyInvocation.InvocationName -eq "." -or $MyInvocation.Line.Contains($MyInvocation.MyCommand.Name)) {
    $result = Test-CudaCapability

    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $result | Format-Table -AutoSize

} else {
    # Being dot-sourced by another script
    Test-CudaCapability
}
