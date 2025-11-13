# Whisper API - MSI Installer Build Guide

Complete guide to building and distributing the Whisper API Windows MSI installer.

## Quick Start

### For End Users (Installing the MSI)

1. **Get the MSI file** - Download `Whisper-API-1.0.0.0.msi`
2. **Double-click** the MSI file
3. **Follow the wizard** - Accept license, choose install location
4. **Start Menu** - Find "Whisper API" folder
5. **Click "Install Whisper API"** - This launches the interactive setup
6. **Configure**:
   - Choose model (tiny, base, small, medium, large, turbo)
   - Enter port (default: 4444)
   - Confirm CUDA preference
7. **Done!** - Service is installed and running

See [QUICKSTART.md](QUICKSTART.md) for post-installation usage.

---

## For Developers (Building the MSI)

### Prerequisites

Install these tools on your Windows machine:

1. **WiX Toolset 3.11 or later**
   - Download: https://github.com/wixtoolset/wix3/releases
   - Or: `choco install wixtoolset`

2. **Visual C++ Build Tools**
   - Download: https://visualstudio.microsoft.com/downloads/
   - Search: "Build Tools for Visual Studio"
   - Or: `choco install visualstudio2019buildtools`

3. **PowerShell 5.0+** (Usually pre-installed)

### Build Steps

#### Step 1: Verify Prerequisites

```powershell
# Check WiX installation
Test-Path "C:\Program Files (x86)\WiX Toolset v3.11\bin\candle.exe"
# Should return: True

# Check PowerShell version
$PSVersionTable.PSVersion
# Should be 5.0 or higher
```

#### Step 2: Navigate to WiX Directory

```powershell
cd C:\Users\dnias\repos\whisper-api\wix
```

#### Step 3: Run Build Script

**Default (simple):**
```powershell
.\build-msi.ps1
```

Output: `Whisper-API-1.0.0.0.msi`

**Custom version:**
```powershell
.\build-msi.ps1 -Version "1.0.1.0"
```

Output: `Whisper-API-1.0.1.0.msi`

**Custom output directory:**
```powershell
.\build-msi.ps1 -OutputDir "C:\releases"
```

Output: `C:\releases\Whisper-API-1.0.0.0.msi`

#### Step 4: Verify Build Success

You should see:
```
======================================================================
✓ MSI package created successfully!
======================================================================

Output File:    ...\Whisper-API-1.0.0.0.msi
File Size:      2.45 MB
SHA256 (short): A3B4C5D6E7F8G9H0...
Version:        1.0.0.0
```

### Testing the MSI

#### Test 1: Basic Installation

```powershell
# Double-click the MSI or
msiexec /i Whisper-API-1.0.0.0.msi /L*v install.log
```

Verify:
- Installation directory created
- Start Menu shortcuts created
- Files in place

#### Test 2: Run Setup

```powershell
# In Start Menu, click "Install Whisper API"
# Or run directly:
C:\Program Files\Whisper Api\install-whisper.bat
```

#### Test 3: Service Status

```powershell
Get-Service whisper-api
```

Expected: Service is "Running"

#### Test 4: API Verification

```powershell
curl http://127.0.0.1:4444/v1/health
```

Expected: JSON response with service status

## File Structure

```
whisper-api/
├── install-whisper.bat            # Quick installer script
├── install-whisper.ps1            # Main installer (1000+ lines)
├── uninstall-whisper.ps1          # Uninstaller
├── QUICKSTART.md                  # User quick start guide
├── README.md                       # Full documentation
├── MSI-BUILD-GUIDE.md             # This file
│
├── utils/
│   ├── check-gpu.ps1              # GPU compatibility tool
│   └── manage-service.ps1         # Service management
│
├── config/
│   ├── requirements.txt           # Python dependencies
│   └── service-config.json        # Configuration reference
│
├── wix/                           # MSI BUILDER (You are here)
│   ├── Product.wxs                # WiX XML source (main MSI definition)
│   ├── build-msi.ps1              # Build automation script
│   ├── License.rtf                # License file (shown during install)
│   ├── BUILD_MSI.md               # Detailed MSI build guide
│   └── obj/                       # Build artifacts (auto-generated)
│
└── .claude/                       # Claude Code config
```

## What's in the MSI

The MSI contains:
- ✅ All PowerShell scripts
- ✅ Documentation (README, QUICKSTART)
- ✅ Utility scripts (GPU check, service manager)
- ✅ Configuration files
- ❌ Python 3.13 (downloaded during install)
- ❌ CUDA 13.0 (downloaded if needed)
- ❌ PyTorch (downloaded during install)

Total MSI size: 2-3 MB

## Customization

### Change Product Information

Edit `wix/Product.wxs`:

```xml
<Product Id="*"
         Name="Whisper API"                    <!-- Product name -->
         Version="1.0.0.0"                     <!-- Version -->
         Manufacturer="Your Company"           <!-- Your company -->
         UpgradeCode="A3B2D4E6-F1A3-...">     <!-- Keep unique -->
```

### Change Install Location

Edit `wix/Product.wxs`:

```xml
<Directory Id="INSTALLFOLDER" Name="Your App Name" />
```

Currently: `C:\Program Files\Whisper Api`

### Add Company Branding

1. Create banner image: `Banner.bmp` (493x58 pixels)
2. Create dialog image: `Dialog.bmp` (493x312 pixels)
3. Place in `wix/` directory
4. Build MSI - images will be included

### Update License Text

Edit or replace `wix/License.rtf` with your license text.

## Distribution Methods

### Method 1: Direct Download

1. Build MSI
2. Upload to website/server
3. Users download and run
4. Minimal support needed

### Method 2: Email Distribution

1. Build MSI
2. Attach to email or upload to file sharing
3. Recipients run it
4. Works for small audiences

### Method 3: Internal Deployment

1. Build and test MSI
2. Place on internal file server
3. IT deploys to user machines
4. Centralized management

### Method 4: Group Policy (Enterprise)

For domain-joined Windows computers:

1. Build and code-sign MSI
2. Create Group Policy object
3. Deploy via GPO
4. Automatic installation

## Troubleshooting Build Issues

### Problem: "WiX Toolset not found"

```
ERROR: WiX Toolset not found!
```

**Solution:**
1. Install WiX Toolset 3.11+: https://github.com/wixtoolset/wix3/releases
2. Or use Chocolatey: `choco install wixtoolset`
3. Verify: `Test-Path "C:\Program Files (x86)\WiX Toolset v3.11"`

### Problem: "Candle compilation failed"

```
Candle compilation failed with exit code 1
```

**Causes & Solutions:**
- XML syntax error in `Product.wxs` - Check XML structure
- Missing source files - Verify all `.ps1` files exist in parent directory
- Invalid paths - Ensure no files are missing

**Debug:**
```powershell
cd wix
& "C:\Program Files (x86)\WiX Toolset v3.11\bin\candle.exe" Product.wxs
```

### Problem: "Light linking failed"

**Solution:**
1. Delete build artifacts: `Remove-Item obj -Recurse -Force`
2. Reinstall WiX Toolset
3. Try build again

### Problem: File not found errors

**Solution:**
Verify all files exist:
```powershell
cd wix
Test-Path ..\install-whisper.ps1      # Should be True
Test-Path ..\install-whisper.bat
Test-Path ..\uninstall-whisper.ps1
Test-Path ..\README.md
Test-Path ..\QUICKSTART.md
Test-Path ..\utils\check-gpu.ps1
Test-Path ..\utils\manage-service.ps1
Test-Path ..\config\requirements.txt
Test-Path ..\config\service-config.json
```

## Version Management

### Incrementing Versions

Standard format: `Major.Minor.Patch.Build`

Examples:
- `1.0.0.0` - Initial release
- `1.0.1.0` - Bug fix
- `1.1.0.0` - New features
- `2.0.0.0` - Major overhaul

### Build New Version

```powershell
# Build version 1.0.1.0
.\build-msi.ps1 -Version "1.0.1.0" -OutputDir ".\releases"
```

### Update Product.wxs

Also update in `wix/Product.wxs`:
```xml
<Product Version="1.0.1.0" ...>
```

## Advanced Topics

### Code Signing MSI

For enterprise deployment, sign your MSI:

```powershell
# Requires code signing certificate
signtool sign /f cert.pfx /p password /t http://timestamp.server /d "Whisper API" Whisper-API-1.0.0.0.msi
```

Benefits:
- Shows company name during install
- Reduces SmartScreen warnings
- Required for domain deployment

### MSI Repair

If installation is corrupted, users can repair:

```powershell
msiexec /f Whisper-API-1.0.0.0.msi
```

Options:
- `/f` - Reinstall all files
- `/a` - Advertise (shortcut only, installs on first use)
- `/x` - Uninstall

### Silent Installation

```powershell
# Install silently without prompts
msiexec /i Whisper-API-1.0.0.0.msi /quiet /norestart /L*v install.log

# With custom location
msiexec /i Whisper-API-1.0.0.0.msi /quiet INSTALLFOLDER="C:\CustomPath\Whisper Api"
```

### Transform Files

For mass customization across multiple deployments:

1. Create transform (.mst) file in WiX
2. Apply during installation:
   ```powershell
   msiexec /i Whisper-API.msi /t custom.mst
   ```

See `wix/BUILD_MSI.md` for advanced WiX topics.

## Deployment Checklist

- [ ] Build MSI successfully
- [ ] Test on clean Windows 10/11 system
- [ ] Verify all shortcuts created
- [ ] Test "Install Whisper API" from Start Menu
- [ ] Confirm service starts and runs
- [ ] Test API endpoint: `http://127.0.0.1:4444/docs`
- [ ] Test uninstall removes all files
- [ ] Create release notes
- [ ] Upload to distribution location
- [ ] Document version in changelog
- [ ] Test upgrade from previous version

## Support Files

### For Developers
- `wix/BUILD_MSI.md` - Detailed WiX build guide
- `wix/Product.wxs` - WiX source code
- `wix/build-msi.ps1` - Automated build script

### For End Users
- `QUICKSTART.md` - 5-minute setup guide
- `README.md` - Complete documentation
- `install-whisper.bat` - Easy installer entry point

### In Installed Directory
- `C:\Program Files\Whisper Api\install.log` - Detailed installation log
- `C:\Program Files\Whisper Api\logs\` - Service logs

## Performance Tips

### Build Performance
- Building MSI takes 2-5 seconds
- First build slower (WiX initialization)
- Subsequent builds faster (incremental)

### Installation Performance
- Typical install time: 10-20 minutes
- Depends on:
  - Python 3.13 download (~25 MB)
  - CUDA 13.0 download (~2-3 GB, if enabled)
  - PyTorch download (~2 GB)
  - System disk speed

## FAQ

**Q: Can I modify the MSI after building?**
A: Not recommended. Rebuild with new version number instead.

**Q: Can users install to custom location?**
A: Yes, installer prompts for location after MSI launches.

**Q: What if user cancels during install?**
A: Service is not created. Files are left in install directory. User can uninstall or try again.

**Q: How do users uninstall?**
A: Control Panel > Programs > Uninstall, or "Uninstall Whisper API" in Start Menu.

**Q: Can multiple versions coexist?**
A: No, only one version per system (upgrade replaces).

**Q: Is internet required?**
A: Yes, for downloading Python, CUDA, and PyTorch during setup.

## Support and Feedback

For issues with:
- **MSI building**: See `wix/BUILD_MSI.md`
- **Installation**: See `README.md` Troubleshooting
- **Service operation**: See `QUICKSTART.md`

## Next Steps

1. ✅ MSI builder is ready - `wix/build-msi.ps1`
2. ✅ All files are in place
3. **→ Run `.\build-msi.ps1` to create your first MSI**
4. **→ Test on a clean Windows machine**
5. **→ Distribute to end users**

---

**Built**: November 2024
**Version**: 1.0.0
**WiX Version**: 3.11+
