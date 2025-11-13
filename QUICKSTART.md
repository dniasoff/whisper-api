# Whisper API - Quick Start Guide

Get Whisper API running on Windows in 5 minutes!

## 30-Second Installation

1. **Download** the MSI installer: `Whisper-API-1.0.0.0.msi`
2. **Double-click** the MSI file to install
3. **Follow** the installation wizard
4. **Run installer** from Start Menu: `Start > Whisper API > Install Whisper API`
5. **Answer prompts:**
   - Model: Choose `small` (if unsure)
   - Port: Press Enter for 4444
   - CUDA: Answer based on installer suggestion
6. **Wait** 10-20 minutes
7. **Done!** Service is running automatically

## Verify Installation

Open your browser and go to:
```
http://127.0.0.1:4444/docs
```

You should see the interactive API documentation.

## Test the API

### Using curl

```bash
# Health check
curl http://127.0.0.1:4444/v1/health

# Transcribe an audio file
curl -X POST http://127.0.0.1:4444/v1/audio/transcriptions \
  -F "file=@myaudio.mp3" \
  -F "model=whisper-1"
```

### Using Python

```python
import requests

# Health check
response = requests.get('http://127.0.0.1:4444/v1/health')
print(response.json())

# Transcribe
with open('myaudio.mp3', 'rb') as f:
    files = {'file': f}
    data = {'model': 'whisper-1'}
    response = requests.post(
        'http://127.0.0.1:4444/v1/audio/transcriptions',
        files=files,
        data=data
    )
    print(response.json())
```

## Manage the Service

### Start / Stop

```powershell
# Start
net start whisper-api

# Stop
net stop whisper-api

# Restart
net stop whisper-api && net start whisper-api
```

### View Status and Logs

```powershell
# Status
Get-Service whisper-api

# View logs
Get-Content "C:\Program Files\Whisper Api\logs\stderr.log" -Tail 50

# Follow logs in real-time
Get-Content "C:\Program Files\Whisper Api\logs\stderr.log" -Wait
```

## Troubleshooting

### Service won't start?
```powershell
# Check what's wrong
Get-Content "C:\Program Files\Whisper Api\logs\stderr.log"
```

### Port already in use?
Change the port after installation:
```powershell
# Stop service
net stop whisper-api

# Update registry
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_PORT /t REG_SZ /d 5000 /f

# Start service
net start whisper-api
```

Or reinstall via:
- Windows Settings > Apps > Whisper API > Uninstall
- Then reinstall from MSI

### GPU not working?
```powershell
# Check GPU compatibility
cd "C:\Program Files\Whisper Api\utils"
.\check-gpu.ps1

# Service will auto-fallback to CPU for unsupported GPUs (P1000, P2000, etc.)
# Check logs to see if GPU is being used
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log" | Select-String "GPU"
```

## Configuration After Installation

### Change Model

Edit the service to use a different model:

```powershell
# Stop service
net stop whisper-api

# Change model in registry
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" `
  /v WHISPER_MODEL /t REG_SZ /d "large"

# Restart
net start whisper-api
```

Available models: `tiny`, `base`, `small`, `medium`, `large`, `turbo`

### Change Port

```powershell
# Stop service
net stop whisper-api

# Update registry
reg add "HKLM\SYSTEM\CurrentControlSet\Services\whisper-api\Environment" /v WHISPER_PORT /t REG_SZ /d 8000 /f

# Start service
net start whisper-api
```

## API Examples

### Transcribe with language detection

```bash
curl -X POST http://127.0.0.1:4444/v1/audio/transcriptions \
  -F "file=@audio.mp3" \
  -F "model=whisper-1" \
  -F "response_format=json"
```

### Transcribe specific language

```bash
curl -X POST http://127.0.0.1:4444/v1/audio/transcriptions \
  -F "file=@audio.mp3" \
  -F "model=whisper-1" \
  -F "language=es"  # Spanish
```

### Get plain text response

```bash
curl -X POST http://127.0.0.1:4444/v1/audio/transcriptions \
  -F "file=@audio.mp3" \
  -F "response_format=text"
```

## Full Documentation

See [README.md](README.md) for complete documentation including:
- System requirements
- GPU compatibility details
- Advanced configuration
- Performance optimization
- Troubleshooting guide

## Common Commands

```powershell
# Service management
net start whisper-api          # Start service
net stop whisper-api           # Stop service
Get-Service whisper-api        # Check status

# View logs
Get-Content "C:\Program Files\Whisper Api\logs\stdout.log"

# Uninstall
# Use Windows Settings > Apps > Whisper API > Uninstall
# Or PowerShell:
cd "C:\Program Files\Whisper Api"
.\uninstall-whisper.ps1

# Check GPU
.\utils\check-gpu.ps1

# Manage service
.\utils\manage-service.ps1 -Action status
```

## Installation Directory

```
C:\Program Files\Whisper Api\
├── .python\                 # Portable Python 3.13
├── logs\                    # Service logs
│   ├── whisper_service.log # Service control log
│   ├── stdout.log          # Application output
│   └── stderr.log          # Error log
├── server.py                # FastAPI server
├── whisper_service.py       # Windows service wrapper
├── install-whisper.ps1      # Installation script
├── uninstall-whisper.ps1    # Uninstallation script
├── utils\                   # Utility scripts
└── README.md                # Full documentation
```

---

**Need help?** Check the logs first:
```powershell
Get-Content "C:\Program Files\Whisper Api\logs\stderr.log" -Tail 100
```

Then see the [Troubleshooting](README.md#troubleshooting) section in README.md.
