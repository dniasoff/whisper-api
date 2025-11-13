# Building Whisper API MSI Installer

This guide explains how to build a professional Windows MSI installer package for Whisper API using WiX Toolset.

## Prerequisites

You need the following tools installed on your build machine:

### 1. WiX Toolset 3.11 (or later)

Download and install from: https://github.com/wixtoolset/wix3/releases

**Option A: Manual Installation**
1. Download `wix311.exe` or later
2. Run the installer
3. Choose "Complete" installation

**Option B: Using Chocolatey**
```powershell
choco install wixtoolset
```

### 2. Visual C++ Build Tools (Required by WiX)

Download from: https://visualstudio.microsoft.com/downloads/
- Search for "Build Tools for Visual Studio"
- Install "Desktop development with C++"

**Or via Chocolatey:**
```powershell
choco install visualstudio2019buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools"
```

### 3. PowerShell 5.0+ (Usually pre-installed on Windows 10+)

Verify:
```powershell
$PSVersionTable.PSVersion
```

## Build Steps

### Step 1: Prepare the WiX Source

The WiX directory contains:
```
wix/
├── Product.wxs           # WiX XML source file
├── License.rtf           # License displayed during installation
├── build-msi.ps1         # Build script
└── BUILD_MSI.md          # This file
```

All source files should already be in the parent directory (`..`).

### Step 2: Build the MSI

Open PowerShell and navigate to the `wix` directory:

```powershell
cd "C:\Users\dnias\repos\whisper-api\wix"
```

Run the build script with default settings:

```powershell
.\build-msi.ps1
```

Or with custom version and output directory:

```powershell
.\build-msi.ps1 -OutputDir ".\dist" -Version "1.0.1.0"
```

### Step 3: Verify the MSI

The script will output:
```
✓ MSI package created successfully!

Output File:    C:\Users\dnias\repos\whisper-api\wix\Whisper-API-1.0.0.0.msi
File Size:      2.45 MB
SHA256 (short): A3B4C5D6E7F8G9H0...
Version:        1.0.0.0
```

## MSI File Details

### Location
Default: `wix/` directory (current working directory when you run the script)

Customize with:
```powershell
.\build-msi.ps1 -OutputDir "C:\dist"
```

### File Naming
```
Whisper-API-<version>.msi
```

Example: `Whisper-API-1.0.0.0.msi`

### File Size
- Typical size: 2-3 MB
- Contains all PowerShell scripts, documentation, and configuration files
- Does NOT include Python, CUDA, or PyTorch (downloaded during installation)

## Distribution

### Method 1: Direct File Sharing
1. Copy the `.msi` file to users
2. Users double-click to install
3. Windows Installer wizard launches
4. Service setup begins automatically

### Method 2: Website Download
1. Host the MSI on your website
2. Users download and run it
3. Standard Windows installer experience

### Method 3: Group Policy (Enterprise)
Deploy via Group Policy to multiple Windows computers in your domain.

## Installation Experience

### What Users See

When a user double-clicks `Whisper-API-1.0.0.0.msi`:

1. **Windows Installer Wizard**
   - Welcome screen
   - License agreement (from License.rtf)
   - Install location: `C:\Program Files\Whisper Api`
   - Ready to Install confirmation

2. **File Installation**
   - Extracts all files to install directory
   - Creates "Whisper API" folder in Start Menu
   - Adds registry entries

3. **Start Menu Shortcuts Created**
   - "Install Whisper API" (launches setup wizard)
   - "Quick Start Guide" (opens QUICKSTART.md)
   - "Manage Service" (PowerShell utility)
   - "Check GPU Compatibility" (GPU diagnostic)
   - "Uninstall Whisper API"

4. **User Launches Installation**
   - User clicks "Install Whisper API" from Start Menu
   - `install-whisper.bat` runs with admin elevation
   - Interactive PowerShell installer launches
   - User selects model, port, and CUDA preferences
   - Service is configured and started

### Directory Structure After Installation

```
C:\Program Files\Whisper Api\
├── install-whisper.bat
├── install-whisper.ps1
├── uninstall-whisper.ps1
├── README.md
├── QUICKSTART.md
├── install.log              (created during setup)
├── utils/
│   ├── check-gpu.ps1
│   └── manage-service.ps1
├── config/
│   ├── requirements.txt
│   └── service-config.json
├── .venv/                   (created during setup)
└── logs/                    (created during service startup)
```

## Customization

### Change Product Information

Edit `Product.wxs`:

```xml
<Product Id="*"
         Name="Whisper API"        <!-- Your product name -->
         Version="1.0.0.0"         <!-- Your version -->
         Manufacturer="Your Company" <!-- Your company -->
         UpgradeCode="A3B2D4E6..."> <!-- Keep this unique -->
```

### Change Install Location

Default: `C:\Program Files\Whisper Api`

To change, edit `Product.wxs`:

```xml
<Directory Id="INSTALLFOLDER" Name="Whisper Api" />
```

Change "Whisper Api" to your preferred folder name.

### Add Custom License

1. Create your license as an RTF file: `License.rtf`
2. Save it in the `wix/` directory
3. The build script will automatically include it

### Create Branded MSI

1. Create a 493x58 BMP image: `Banner.bmp`
2. Create a 493x312 BMP image: `Dialog.bmp`
3. Save both in the `wix/` directory
4. Edit `Product.wxs` to reference them:

```xml
<WixVariable Id="WixUIBannerBmp" Value="Banner.bmp" />
<WixVariable Id="WixUIDialogBmp" Value="Dialog.bmp" />
```

## Troubleshooting

### "WiX Toolset not found"

**Solution**: Install WiX Toolset 3.11+
```powershell
# Check if installed
Get-Item "C:\Program Files (x86)\WiX Toolset v3.11" -ErrorAction SilentlyContinue
```

### "Candle compilation failed"

**Causes**:
- XML syntax error in `Product.wxs`
- Missing source files
- File path with spaces not quoted

**Solution**:
1. Check `Product.wxs` XML syntax
2. Verify all referenced files exist
3. Run from command line for detailed error:
   ```powershell
   cd wix
   candle -d SourceDir=. Product.wxs
   ```

### "Light linking failed"

**Causes**:
- WiX extensions not installed
- Corrupted object file

**Solution**:
1. Clean build directory: `Remove-Item obj -Recurse -Force`
2. Reinstall WiX with extensions
3. Try build again

### MSI file not created

**Debugging**:
```powershell
# Run with detailed output
$ErrorActionPreference = "Continue"
.\build-msi.ps1 -Verbose
```

Check output directory exists and is writable.

## Updating the MSI

### For New Versions

1. Update version in `build-msi.ps1` call:
   ```powershell
   .\build-msi.ps1 -Version "1.0.1.0"
   ```

2. Update `Product.wxs` if needed:
   ```xml
   <Product Version="1.0.1.0" ...>
   ```

3. Update component GUIDs if you modify files (WiX requirement)

### Testing Updates

1. Uninstall previous version
2. Reboot (recommended)
3. Install new MSI
4. Verify all features work

## Signing the MSI (Optional - for Enterprise)

For production deployments, sign your MSI with a code signing certificate:

```powershell
# Using signtool.exe (part of Windows SDK)
signtool sign /f "cert.pfx" /p "password" /t "http://timestamp.server" Whisper-API-1.0.0.0.msi
```

Benefits:
- Users see your company name during installation
- Reduces SmartScreen warnings
- Required for domain deployment

## Deployment Scenarios

### Scenario 1: Direct Download

1. Build MSI
2. Host on website
3. Users download and install
4. Minimal support needed

### Scenario 2: Internal IT Distribution

1. Build MSI
2. Place on internal file server
3. IT deploys to user machines
4. IT provides support

### Scenario 3: Enterprise Group Policy

1. Build and sign MSI
2. Create Group Policy object
3. Deploy to domain computers
4. Automatic installation on next login
5. Centralized management

## Rollback / Uninstall

Users can uninstall using:

**Method 1: Control Panel**
- Settings > Apps > Installed apps
- Find "Whisper API"
- Click "Uninstall"

**Method 2: Start Menu**
- Start Menu > Whisper API > Uninstall Whisper API

**Method 3: Command Line**
```powershell
msiexec /x "Whisper-API-1.0.0.0.msi"
```

All service files, logs, and Python environment are removed (user's choice).

## Support and Troubleshooting

For installation issues, users should:

1. Check installation log:
   ```powershell
   Get-Content "C:\Program Files\Whisper Api\install.log"
   ```

2. Run diagnostic:
   ```powershell
   cd "C:\Program Files\Whisper Api"
   .\utils\check-gpu.ps1
   ```

3. Check service status:
   ```powershell
   Get-Service whisper-api
   Get-Content "C:\Program Files\Whisper Api\logs\stderr.log" -Tail 100
   ```

## Additional Resources

- [WiX Toolset Documentation](http://wixtoolset.org/documentation/)
- [WiX Tutorial](http://wixtoolset.org/documentation/manual/v3/tutorial/)
- [Windows Installer Docs](https://docs.microsoft.com/en-us/windows/win32/msi/windows-installer-portal)

## Build Command Reference

### Basic Build
```powershell
.\build-msi.ps1
```
Output: `Whisper-API-1.0.0.0.msi` in current directory

### Custom Output Directory
```powershell
.\build-msi.ps1 -OutputDir "C:\dist"
```

### Custom Version
```powershell
.\build-msi.ps1 -Version "1.0.1.0"
```

### Custom WiX Path
```powershell
.\build-msi.ps1 -WixPath "C:\Program Files (x86)\WiX Toolset v3.14"
```

### All Options
```powershell
.\build-msi.ps1 -OutputDir "C:\dist" -Version "2.0.0.0" -WixPath "C:\WiX"
```

---

**Last Updated**: November 2024
