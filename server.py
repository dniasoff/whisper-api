from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse, RedirectResponse
from faster_whisper import WhisperModel
from typing import Optional
import asyncio
import tempfile
import torch
import os
import uvicorn
import logging

# -----------------------------
# Config
# -----------------------------
MODEL_SIZE = os.getenv("WHISPER_MODEL", "small")

# File upload limits
MAX_FILE_SIZE = 100 * 1024 * 1024  # 100 MB
ALLOWED_AUDIO_EXTENSIONS = {
    ".mp3", ".mp4", ".mpeg", ".mpga", ".m4a",
    ".wav", ".webm", ".ogg", ".flac", ".opus"
}

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# Auto-detect CUDA availability and check for modern GPUs
DEVICE = "cpu"
COMPUTE_TYPE = "int8"

# Use print to ensure logs appear during module import (before uvicorn captures logging)
print("="*60)
print("Whisper API Server - GPU Detection")
print("="*60)

if torch.cuda.is_available():
    print("✓ CUDA is available on this system")
    try:
        capability = torch.cuda.get_device_capability(0)
        compute_cap = float(f"{capability[0]}.{capability[1]}")
        gpu_name = torch.cuda.get_device_name(0)

        print(f"GPU Name: {gpu_name}")
        print(f"GPU Compute Capability: sm_{capability[0]}{capability[1]} ({compute_cap})")
        print(f"CUDA Toolkit Version: {torch.version.cuda}")
        print(f"PyTorch Version: {torch.__version__}")

        # Check PyTorch compatibility
        # PyTorch 2.9+ requires compute capability >= 7.5 (sm_75)
        # Older versions support down to 5.0 or 6.0
        pytorch_min_capability = 7.5  # PyTorch 2.9.x minimum requirement

        print(f"PyTorch Minimum Required: sm_75 (7.5+)")

        if compute_cap < pytorch_min_capability:
            print(f"✗ GPU INCOMPATIBLE: Your GPU (sm_{capability[0]}{capability[1]}) is below PyTorch minimum (sm_75)")
            print(f"   Explanation: PyTorch {torch.__version__} dropped support for older GPUs")
            print(f"   - Your GPU: Compute Capability {compute_cap} (Pascal/Maxwell architecture)")
            print(f"   - Required: Compute Capability 7.5+ (Turing/Volta/Ampere/Ada/Hopper)")
            print(f"   - Supported GPUs: RTX 20/30/40 series, Tesla V100+, A100, H100")
            print(f"")
            print(f"   To use this GPU, you would need to downgrade PyTorch to version 2.4 or earlier.")
            print(f"   Current configuration will use CPU mode (int8 precision).")
            print(f"Final Device: CPU (GPU incompatible with PyTorch version)")
        elif compute_cap >= 5.0:
            # GPU is compatible, enable CUDA
            DEVICE = "cuda"
            COMPUTE_TYPE = "float16"
            print(f"✓ GPU COMPATIBLE: Compute capability {compute_cap} meets PyTorch requirement (7.5+)")
            print(f"✓ CUDA ACCELERATION ENABLED")
            print(f"Final Device: CUDA (GPU acceleration active with float16 precision)")
        else:
            print(f"✗ GPU TOO OLD: Compute capability {compute_cap} < 5.0")
            print(f"   This GPU is from pre-2014 era and is not supported by any modern CUDA toolkit.")
            print(f"Final Device: CPU (GPU too old)")

    except Exception as e:
        print(f"✗ Could not get GPU information: {e}")
        print(f"Final Device: CPU (GPU detection failed)")
else:
    print("✗ CUDA is NOT available on this system")
    print("   Possible reasons:")
    print("   - No NVIDIA GPU detected")
    print("   - NVIDIA drivers not installed")
    print("   - PyTorch CPU-only version installed")
    print(f"Final Device: CPU (no CUDA support)")

print("="*60)
print(f"Active Configuration: DEVICE={DEVICE}, COMPUTE_TYPE={COMPUTE_TYPE}, MODEL={MODEL_SIZE}")
print("="*60)

DEVICE_INDEX = int(os.getenv("CUDA_DEVICE_ID", "0"))
CHUNK_LENGTH_S = int(os.getenv("CHUNK_LENGTH", "15"))
VAD_FILTER = os.getenv("VAD_FILTER", "false").lower() == "true"
PORT = 4444
HOST = "127.0.0.1"

# -----------------------------
# FastAPI
# -----------------------------
app = FastAPI(title="Whisper Assistant API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  # Disabled for security since we're localhost-only
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# Model load
# -----------------------------
logger.info(f"Loading Whisper model: {MODEL_SIZE}")
try:
    model = WhisperModel(
        MODEL_SIZE,
        device=DEVICE,
        device_index=DEVICE_INDEX,
        compute_type=COMPUTE_TYPE,
        num_workers=1,
    )
    logger.info(f"✓ Model loaded successfully: {MODEL_SIZE} on {DEVICE} with {COMPUTE_TYPE}")
except Exception as e:
    # Fall back to CPU if CUDA fails
    if DEVICE == "cuda":
        logger.warning(f"Failed to load model with CUDA: {e}")
        logger.info("Falling back to CPU mode...")
        DEVICE = "cpu"
        COMPUTE_TYPE = "int8"
        model = WhisperModel(
            MODEL_SIZE,
            device=DEVICE,
            device_index=DEVICE_INDEX,
            compute_type=COMPUTE_TYPE,
            num_workers=1,
        )
        logger.info(f"✓ Model loaded successfully: {MODEL_SIZE} on CPU with int8")
    else:
        logger.error(f"Failed to load model: {e}")
        raise

_gpu_lock = asyncio.Lock()

# -----------------------------
# Routes
# -----------------------------
@app.get("/")
def root():
    return RedirectResponse(url="/docs")

@app.get("/v1/health")
def health():
    return {
        "status": "ok",
        "device": DEVICE,
        "model": MODEL_SIZE,
        "compute_type": COMPUTE_TYPE,
        "cuda_available": torch.cuda.is_available(),
        "cuda_version": getattr(torch.version, "cuda", None),
    }

@app.post("/v1/audio/transcriptions")
async def transcribe_audio(
    file: UploadFile = File(...),
    model_name: str = Form(default="whisper-1"),
    language: Optional[str] = Form(default=None),
    temperature: float = Form(default=0.0),
    response_format: str = Form(default="json"),
):
    # Validate file extension
    suffix = os.path.splitext(file.filename or "")[1].lower() or ".wav"
    if suffix not in ALLOWED_AUDIO_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported audio format: {suffix}. Supported formats: {', '.join(ALLOWED_AUDIO_EXTENSIONS)}"
        )

    # Read file and validate size
    file_content = await file.read()
    file_size = len(file_content)

    if file_size > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"File too large: {file_size / (1024*1024):.1f} MB. Maximum allowed: {MAX_FILE_SIZE / (1024*1024):.0f} MB"
        )

    if file_size == 0:
        raise HTTPException(status_code=400, detail="Empty file uploaded")

    logger.info(f"Processing transcription: {file.filename} ({file_size / 1024:.1f} KB)")

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp_path = tmp.name
            tmp.write(file_content)
            tmp.flush()

        async with _gpu_lock:
            segments, info = model.transcribe(
                tmp_path,
                language=language,
                # Less aggressive duplicate detection:
                condition_on_previous_text=True,
                temperature=0.0,                          # Single temperature, no fallback retries
                beam_size=1,
                best_of=1,
                word_timestamps=False,
                chunk_length=15,
                vad_filter=True,
                vad_parameters={
                    "min_speech_duration_ms": 200,
                    "min_silence_duration_ms": 250,
                    "speech_pad_ms": 120
                }
            )
        
        text = " ".join(s.text for s in segments).strip()
        if response_format == "text":
            return PlainTextResponse(text)
        return JSONResponse({"text": text, "language": getattr(info, "language", language)})

    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except Exception:
                pass

@app.post("/transcribe")
async def transcribe_alias(file: UploadFile = File(...), language: Optional[str] = Form(default=None)):
    return await transcribe_audio(file=file, model_name="whisper-1", language=language, response_format="json")

@app.on_event("startup")
async def warmup():
    """Warm up the model with a dummy transcription to improve first-request latency"""
    # Log GPU/CUDA configuration
    logger.info("="*60)
    logger.info("Whisper API Server - GPU/CUDA Configuration")
    logger.info("="*60)
    logger.info(f"Device: {DEVICE}")
    logger.info(f"Compute Type: {COMPUTE_TYPE}")
    logger.info(f"Model: {MODEL_SIZE}")
    logger.info(f"PyTorch Version: {torch.__version__}")

    if torch.cuda.is_available():
        logger.info("CUDA Status: Available")
        try:
            capability = torch.cuda.get_device_capability(0)
            compute_cap = float(f"{capability[0]}.{capability[1]}")
            gpu_name = torch.cuda.get_device_name(0)

            logger.info(f"GPU Name: {gpu_name}")
            logger.info(f"GPU Compute Capability: sm_{capability[0]}{capability[1]} ({compute_cap})")
            logger.info(f"CUDA Toolkit Version: {torch.version.cuda}")

            # Explain why CUDA might be disabled
            pytorch_min_capability = 7.5  # PyTorch 2.9.x requirement
            logger.info(f"PyTorch Minimum Required: sm_75 (7.5+)")

            if DEVICE == "cuda":
                logger.info("✓ CUDA ACCELERATION ENABLED")
                logger.info(f"   GPU is compatible and will be used for acceleration")
            else:
                # CUDA is available but not being used - explain why
                logger.warning("✗ CUDA DISABLED - GPU Not Compatible")
                logger.warning(f"   Your GPU: {gpu_name} with compute capability {compute_cap} (sm_{capability[0]}{capability[1]})")
                logger.warning(f"   PyTorch {torch.__version__} requires: Compute capability 7.5+ (sm_75+)")
                logger.warning(f"")
                # Determine GPU architecture based on compute capability
                if compute_cap >= 9.0:
                    arch = "Hopper (2022+)"
                elif compute_cap >= 8.9:
                    arch = "Ada Lovelace (2022)"
                elif compute_cap >= 8.0:
                    arch = "Ampere (2020)"
                elif compute_cap >= 7.5:
                    arch = "Turing (2018)"
                elif compute_cap >= 7.0:
                    arch = "Volta (2017)"
                elif compute_cap >= 6.0:
                    arch = "Pascal (2016)"
                elif compute_cap >= 5.0:
                    arch = "Maxwell (2014)"
                else:
                    arch = "Kepler or older (2012-)"

                logger.warning(f"   Explanation:")
                logger.warning(f"   - Your GPU is based on {arch} architecture")
                logger.warning(f"   - PyTorch 2.9+ dropped support for GPUs older than Turing/Volta (2018)")
                logger.warning(f"   - Supported GPUs: RTX 20/30/40 series, Tesla V100+, A100, H100")
                logger.warning(f"")
                logger.warning(f"   Options:")
                logger.warning(f"   1. Continue with CPU mode (current - works fine, just slower)")
                logger.warning(f"   2. Downgrade PyTorch to version 2.4 to use this GPU")
                logger.warning(f"   3. Upgrade GPU to RTX 2060 or newer for CUDA support")

        except Exception as e:
            logger.error(f"Error getting GPU details: {e}")
    else:
        logger.info("CUDA Status: Not Available")
        logger.info("   Possible reasons:")
        logger.info("   - No NVIDIA GPU detected")
        logger.info("   - NVIDIA drivers not installed")
        logger.info("   - PyTorch CPU-only version installed")

    logger.info("="*60)

    # Warmup
    tmp_file = None
    try:
        logger.info("Starting model warmup...")
        import numpy as np, soundfile as sf
        import time
        sr = 16000
        dummy = np.zeros(sr, dtype="float32")
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as t:
            tmp_file = t.name
            sf.write(tmp_file, dummy, sr)

        # File is now closed, safe to read
        async with _gpu_lock:
            list(model.transcribe(tmp_file, beam_size=1, vad_filter=False, chunk_length=CHUNK_LENGTH_S))

        # Delete with retry on Windows file lock issues
        for attempt in range(3):
            try:
                if os.path.exists(tmp_file):
                    os.unlink(tmp_file)
                    break
            except PermissionError:
                if attempt < 2:
                    time.sleep(0.5)  # Wait before retry
                else:
                    logger.warning(f"Could not delete warmup temp file: {tmp_file}")

        logger.info("Model warmup completed successfully")
    except Exception as e:
        logger.error(f"Model warmup failed: {e}", exc_info=True)
        logger.warning("Service will continue, but first transcription request may be slower")
        # Try to clean up temp file even on error
        if tmp_file and os.path.exists(tmp_file):
            try:
                os.unlink(tmp_file)
            except:
                pass

if __name__ == "__main__":
    uvicorn.run("server:app", host=HOST, port=PORT, reload=False, workers=1)