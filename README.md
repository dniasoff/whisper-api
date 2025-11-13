# Whisper API for Windows

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/yourusername/whisper-api/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-blue.svg)](https://www.microsoft.com/windows)

Professional Windows installer for OpenAI's Whisper speech recognition API. Runs as a native Windows Service with automatic GPU detection, comprehensive logging, and complete lifecycle management.

## 🚀 Features

### Core Functionality
- **OpenAI-Compatible API** - Drop-in replacement for OpenAI's Whisper API
- **Windows Service** - Runs reliably as a native service using pywin32
- **No Timeout Issues** - Proper service signaling prevents Windows timeout errors
- **Auto-Start** - Starts automatically with Windows

### Intelligent GPU Support
- **Smart GPU Detection** - Automatically detects compatible NVIDIA GPUs
- **Automatic Fallback** - Uses CPU for older/unsupported GPUs (Pascal, Maxwell, etc.)
- **PyTorch 2.9+ Compatibility** - Requires compute capability 7.5+ (Turing/Volta 2018+)
- **Detailed Explanations** - Clear GPU detection logs explain why CUDA is disabled

### Installation & Management
- **MSI Installer** - Professional Windows installer with setup wizard
- **Interactive Configuration** - Choose model, port, and CUDA settings during install
- **Smart Port Detection** - Recognizes upgrades vs. port conflicts
- **Complete Uninstall** - Removes service, processes, and all files cleanly
- **Portable Python** - Includes Python 3.13 (no conflicts with system Python)

### Monitoring & Logging
- **Comprehensive Logs** - Service logs, application logs, and error logs
- **File-Based Logging** - Easy to access and monitor
- **Real-Time Monitoring** - View logs as they happen
- **Service Management** - Built-in utilities for service control

## 📋 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Windows 10 (Build 14393+) | Windows 11 |
| **CPU** | x64 processor | Modern Intel/AMD |
| **RAM** | 4 GB | 16 GB |
| **Storage** | 15 GB free | 30 GB free |
| **GPU** | Optional (NVIDIA RTX 20+) | RTX 30/40 series |
| **Admin** | ✓ Required | - |
| **Internet** | ✓ Required (install only) | - |

### GPU Compatibility

#### ✅ Supported GPUs (PyTorch 2.9+, Compute Capability 7.5+)
- **NVIDIA RTX Series**: 20-series and newer (2060, 2080, 3090, 4090, etc.)
- **NVIDIA Tesla/Data Center**: V100, A100, H100
- **NVIDIA Quadro RTX**: RTX 4000, RTX 5000, RTX 6000, RTX 8000
- **Architecture**: Turing (2018), Volta (2017), Ampere (2020), Ada Lovelace (2022), Hopper (2022)

#### ❌ Unsupported GPUs (Auto-fallback to CPU)
- **Older Quadro**: P-series (P1000, P2000, P4000, P5000, P6000) - compute capability 6.1
- **GTX 10-series**: 1050, 1060, 1070, 1080, 1080 Ti - compute capability 6.1
- **GTX 16-series**: 1650, 1660 - compute capability 7.5 but lacks required features
- **GTX 900-series and older**: All models - compute capability 5.2 or lower
- **Maxwell/Pascal/Kepler**: All architectures older than Turing (2018)

**Note**: PyTorch 2.9+ dropped support for GPUs with compute capability < 7.5. Unsupported GPUs automatically fallback to CPU mode (slower but fully functional). The installer provides detailed explanations of GPU compatibility during setup.

## 📦 Installation

### Quick Install (Recommended)

1. **Download** the latest MSI installer from [GitHub Releases](https://github.com/dniasoff/whisper-api/releases)
2. **Double-click** the MSI file
3. **Follow** the installation wizard
4. **Run** the installer from Start Menu: `Start > Whisper API > Install Whisper API`
5. **Configure** during interactive setup:
   - Select Whisper model (tiny/base/small/medium/large/turbo)
   - Choose port (default: 4444)
   - Enable/disable CUDA (auto-detected)
6. **Wait** 10-20 minutes for installation
7. **Test** the API: `http://127.0.0.1:4444/v1/health`

### Advanced Installation

```powershell
# Run PowerShell as Administrator
cd "C:\Program Files\Whisper Api"
.\install-whisper.ps1 -InstallPath "C:\Program Files\Whisper Api"
```

### Installation Directory Structure

```
C:\Program Files\Whisper Api\
├── .python\                    # Portable Python 3.13
│   ├── python.exe
│   ├── pythonservice.exe      # Windows service host
│   └── Lib\site-packages\     # Python packages
├── server.py                   # FastAPI server (your code)
├── whisper_service.py          # Windows service wrapper
├── install-whisper.ps1         # Installation script
├── uninstall-whisper.ps1       # Uninstallation script
├── logs\
│   ├── whisper_service.log    # Service control log
│   ├── stdout.log             # Application output
│   └── stderr.log             # Error log
├── utils\
│   ├── check-gpu.ps1          # GPU diagnostic
│   └── manage-service.ps1     # Service management
└── config\
    ├── requirements.txt        # Python dependencies
    └── service-config.json     # Configuration reference
```

## 🎛️ Configuration

### Model Selection

Choose the Whisper model during installation based on your needs:

| Model | Size | VRAM | Speed | Accuracy | Use Case |
|-------|------|------|-------|----------|----------|
| **tiny** | 39M | ~1 GB | Fastest (10x) | Lowest | Real-time, low quality OK |
| **base** | 74M | ~1 GB | Very Fast (7x) | Low | Quick transcription |
| **small** | 244M | ~2 GB | Fast (4x) | Good | **Recommended default** |
| **medium** | 769M | ~5 GB | Medium (2x) | High | High accuracy needed |
| **large** | 1550M | ~10 GB | Slow (1x) | Highest | Maximum accuracy |
| **turbo** | 809M | ~6 GB | Fast (8x) | High | Best speed/accuracy |

**Recommendation**: Start with `small` for the best balance of speed and accuracy.

### Port Configuration

- **Default**: 4444 (http://127.0.0.1:4444)
- **Range**: 1024-65535
- **Binding**: localhost only (127.0.0.1) - not exposed to network
- **Upgrades**: Installer detects existing service port automatically

### Environment Variables

After installation, service environment is configured via Windows Registry:

```
HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment\
├── WHISPER_MODEL=small       # Selected model
├── WHISPER_PORT=4444          # API port
├── WHISPER_HOST=127.0.0.1     # Bind address
└── CUDA_DEVICE_ID=0           # GPU device (if enabled)
```

## 🔧 Service Management

### Using Windows Services

```powershell
# View status
Get-Service whisper-api

# Start service
Start-Service whisper-api
# or
net start whisper-api

# Stop service
Stop-Service whisper-api
# or
net stop whisper-api

# Restart service
Restart-Service whisper-api
# or
net stop whisper-api && net start whisper-api
```

### Using Built-in Utility

```powershell
cd "C:\Program Files\Whisper Api\utils"

# View status
.\manage-service.ps1 -Action status

# View logs
.\manage-service.ps1 -Action logs

# View configuration
.\manage-service.ps1 -Action config

# Remove service
.\manage-service.ps1 -Action remove
```

### View Logs

```powershell
# Service control log
Get-Content "C:\Program Files\Whisper Api\logs\whisper_service.log" -Tail 50

# Application output
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log" -Tail 50

# Follow logs in real-time
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log" -Wait
```

## 🔌 API Usage

### Base URL

```
http://127.0.0.1:4444
```

### Health Check

**Endpoint**: `GET /v1/health`

```bash
curl http://127.0.0.1:4444/v1/health
```

**Response**:
```json
{
  "status": "ok",
  "device": "cpu",
  "model": "small",
  "compute_type": "int8",
  "cuda_available": true,
  "cuda_version": "13.0"
}
```

### Transcribe Audio

**Endpoint**: `POST /v1/audio/transcriptions`

```bash
curl -X POST http://127.0.0.1:4444/v1/audio/transcriptions \
  -F "file=@audio.mp3" \
  -F "model=whisper-1"
```

**Response**:
```json
{
  "text": "This is the transcribed audio content.",
  "language": "en"
}
```

### Translate Audio

**Endpoint**: `POST /v1/audio/translations`

```bash
curl -X POST http://127.0.0.1:4444/v1/audio/translations \
  -F "file=@audio.mp3" \
  -F "model=whisper-1"
```

**Response**:
```json
{
  "text": "Translated to English text here."
}
```

### Supported Audio Formats

- MP3, MP4, MPEG, MPGA, M4A
- WAV, WEBM
- OGG, FLAC

### API Documentation

Interactive API documentation (Swagger UI):
```
http://127.0.0.1:4444/docs
```

OpenAPI schema:
```
http://127.0.0.1:4444/openapi.json
```

## 🐛 Troubleshooting

### Service Won't Start

**Symptom**: Service fails to start or times out

**Solution 1**: Check logs
```powershell
Get-Content "C:\Program Files\Whisper Api\logs\whisper_service.log"
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log"
```

**Solution 2**: Check service status
```powershell
Get-Service whisper-api | Format-List *
```

**Solution 3**: Try manual start for debugging
```powershell
cd "C:\Program Files\Whisper Api"
& .python\python.exe whisper_service.py debug
```

### Port Already in Use

**Symptom**: "Port 4444 is already in use"

**Solution**: During installation, the installer will detect this and:
- If it's the existing Whisper API service → Continue (upgrade scenario)
- If it's another application → Warn but allow continuation

To change port after installation:
```powershell
# Stop service
net stop whisper-api

# Update registry
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_PORT /t REG_SZ /d 5000 /f

# Start service
net start whisper-api
```

### GPU Not Being Used

**Symptom**: Health check shows `"device": "cpu"` but you have a GPU

**Check 1**: Is your GPU supported?
```powershell
cd "C:\Program Files\Whisper Api\utils"
.\check-gpu.ps1
```

**Check 2**: View startup log for GPU detection
```powershell
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log" | Select-String "GPU"
```

You should see:
- `[INFO] CUDA enabled - GPU: NVIDIA GeForce RTX...` (GPU mode)
- `[WARNING] GPU ... is not supported, using CPU` (unsupported GPU)
- `[INFO] CUDA not available, using CPU` (no GPU detected)

### Model Not Loading

**Symptom**: Service starts but model doesn't load

**Solution**: Check for download/permission issues
```powershell
# View model download logs
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log" | Select-String "faster-whisper"

# Check HuggingFace cache
ls $env:USERPROFILE\.cache\huggingface\hub
```

### High Memory Usage

**Symptom**: System runs out of RAM

**Cause**: Large models need significant memory
- `large`: ~10 GB VRAM + 10 GB RAM
- `medium`: ~5 GB VRAM + 6 GB RAM
- `small`: ~2 GB VRAM + 4 GB RAM

**Solution**: Switch to smaller model
```powershell
# Stop service
net stop whisper-api

# Change model
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_MODEL /t REG_SZ /d small /f

# Start service
net start whisper-api
```

### Slow Transcription

**CPU Mode Performance**:
- `tiny`: ~10x slower than real-time
- `small`: ~4x slower than real-time
- `large`: Can be 50-100x slower

**Solutions**:
1. **Use smaller model** (sacrifice accuracy for speed)
2. **Upgrade to supported GPU** (RTX 20-series or newer)
3. **Add more CPU cores** (limited improvement)
4. **Batch multiple files** (amortize startup cost)

## 🗑️ Uninstallation

### Using Windows Settings

1. `Windows Settings` > `Apps` > `Installed apps`
2. Find `Whisper API` > Click `...` > `Uninstall`
3. Follow uninstall wizard

### Using Control Panel

1. `Control Panel` > `Programs` > `Programs and Features`
2. Right-click `Whisper API` > `Uninstall`

### Using Start Menu

1. `Start` > `Whisper API` > `Uninstall Whisper API`

### Using PowerShell

```powershell
# Complete removal (recommended)
cd "C:\Program Files\Whisper Api"
.\uninstall-whisper.ps1

# Keep installation directory (optional)
.\uninstall-whisper.ps1 -KeepInstallation
```

### What Gets Removed

The uninstaller performs the following:
1. ✅ Stops the Windows service (5 second wait)
2. ✅ Removes the service registration (using pywin32)
3. ✅ Kills any running Python processes (3 second wait)
4. ✅ Removes registry entries
5. ✅ Deletes Python installation directory (`.python` folder)
6. ✅ Deletes logs, cache, and temporary files
7. ✅ WiX MSI uninstaller removes remaining application files
8. ✅ Removes Start Menu shortcuts

**Note**: The PowerShell uninstall script only removes the Python environment and generated files. The MSI uninstaller handles removing the core application files (server.py, whisper_service.py, etc.).

## ⚙️ Advanced Configuration

### Change Model After Installation

```powershell
net stop whisper-api
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_MODEL /t REG_SZ /d medium /f
net start whisper-api
```

### Change Port After Installation

```powershell
net stop whisper-api
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_PORT /t REG_SZ /d 8000 /f
net start whisper-api
```

### Enable Network Access (⚠️ Development Only)

**WARNING**: This exposes your API to the local network without authentication!

```powershell
net stop whisper-api
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_HOST /t REG_SZ /d 0.0.0.0 /f
net start whisper-api
```

**Secure Alternative**: Use nginx/Apache reverse proxy with authentication.

### View Service Environment

```powershell
reg query "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment"
```

## 🔒 Security Considerations

### Current Security Posture

- ✅ **Localhost Only**: API binds to 127.0.0.1 (not exposed to network)
- ✅ **Service Account**: Runs as LocalSystem (full privileges)
- ❌ **No Authentication**: No API keys or authentication
- ❌ **No HTTPS**: HTTP only (plain text)
- ❌ **No Rate Limiting**: Can be overwhelmed

### Production Recommendations

For production use, consider:

1. **Reverse Proxy**: Use nginx/Apache with authentication
2. **HTTPS/TLS**: Enable encryption
3. **API Keys**: Implement authentication
4. **Rate Limiting**: Prevent abuse
5. **Monitoring**: Log access and errors
6. **Firewall**: Restrict access
7. **Container**: Consider Docker for isolation

## 📊 Performance Tips

### Model Selection

Choose based on your speed vs accuracy requirements:

| Priority | Model | Notes |
|----------|-------|-------|
| **Speed** | `tiny` | 10x faster, acceptable for captions |
| **Balance** | `small` | 4x faster, good for most uses |
| **Accuracy** | `large` | Slowest, best for transcription |
| **Best of Both** | `turbo` | 8x faster, nearly large accuracy |

### GPU Optimization

1. **Update Drivers**: Use latest NVIDIA drivers
2. **Monitor Temperature**: Check `nvidia-smi` for thermal throttling
3. **VRAM Usage**: Ensure model fits in VRAM
4. **Dedicated GPU**: Avoid running other GPU workloads

### CPU Optimization

1. **Use Smaller Model**: `tiny` or `small` for CPU
2. **More Cores**: Limited benefit (single model instance)
3. **Disable VAD**: Can speed up processing slightly
4. **Batch Processing**: Process multiple files efficiently

### Network & Storage

1. **Local Files**: Store audio locally (don't stream from network)
2. **SSD Storage**: Faster model loading
3. **Compression**: Use compressed formats (MP3 vs WAV)

## 📝 Version Information

- **Version**: 1.0.0
- **Python**: 3.13.x (portable, included)
- **PyTorch**: 2.9.1 with CUDA 13.0 or CPU-only
- **CUDA Requirement**: Compute capability 7.5+ (sm_75) for GPU acceleration
- **Whisper**: faster-whisper (latest from HuggingFace)
- **Service**: pywin32 (Windows native service)
- **Installer**: WiX Toolset 3.x MSI

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Whisper is developed by OpenAI and licensed under MIT.

## 🔗 Related Resources

- [OpenAI Whisper](https://github.com/openai/whisper) - Original Whisper model
- [Faster Whisper](https://github.com/guillaumekln/faster-whisper) - Optimized implementation
- [PyTorch](https://pytorch.org) - Deep learning framework
- [CUDA Toolkit](https://developer.nvidia.com/cuda-downloads) - NVIDIA GPU acceleration
- [pywin32](https://github.com/mhammond/pywin32) - Windows service support

## 🆘 Getting Help

### Check Logs First

90% of issues can be diagnosed from logs:

```powershell
Get-Content "C:\Program Files\Whisper Api\logs\whisper_service.log"
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log"
```

### Run Diagnostics

```powershell
# GPU compatibility
cd "C:\Program Files\Whisper Api\utils"
.\check-gpu.ps1

# Service status
.\manage-service.ps1 -Action status

# View logs
.\manage-service.ps1 -Action logs
```

### Common Issues

See the **Troubleshooting** section above for solutions to common problems.

## 🎉 Acknowledgments

Built with:
- [OpenAI Whisper](https://github.com/openai/whisper) by OpenAI
- [Faster Whisper](https://github.com/guillaumekln/faster-whisper) by Guillaume Klein
- [FastAPI](https://fastapi.tiangolo.com) by Sebastián Ramírez
- [pywin32](https://github.com/mhammond/pywin32) by Mark Hammond
- [WiX Toolset](https://wixtoolset.org) for MSI creation

Special thanks to Claude Code for assistance in development.

---

**Last Updated**: November 2024
**Status**: Production Ready ✅
