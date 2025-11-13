"""
Whisper API Windows Service Wrapper
Uses pywin32 to create a proper Windows service that communicates with SCM
Signals "running" BEFORE model loads to avoid timeout
"""
import sys
import os
import threading
import time
import logging
from datetime import datetime

# Add the installation directory to path
INSTALL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, INSTALL_DIR)

import win32serviceutil
import win32service
import win32event
import servicemanager

# Set up file logging
LOG_DIR = os.path.join(INSTALL_DIR, "logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "whisper_service.log")
STDOUT_LOG = os.path.join(LOG_DIR, "stdout.log")
STDERR_LOG = os.path.join(LOG_DIR, "stderr.log")

MAX_LOG_LINES = 10000  # Keep only last 10000 lines

def cleanup_log_file(log_path, max_lines=MAX_LOG_LINES):
    """Truncate log file to keep only the last N lines"""
    try:
        if not os.path.exists(log_path):
            return

        file_size = os.path.getsize(log_path)
        file_size_mb = file_size / (1024 * 1024)

        # Only cleanup if file is larger than 1MB
        if file_size < 1024 * 1024:
            return

        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()

        if len(lines) > max_lines:
            removed_lines = len(lines) - max_lines
            # Keep only last max_lines
            with open(log_path, 'w', encoding='utf-8') as f:
                f.write(f"[Log truncated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - removed {removed_lines} old lines, kept last {max_lines} lines]\n")
                f.writelines(lines[-max_lines:])
            print(f"Truncated {log_path}: {file_size_mb:.1f}MB, removed {removed_lines} lines")
    except Exception as e:
        # Don't fail service startup if log cleanup fails
        print(f"Warning: Could not cleanup log file {log_path}: {e}")

# Delete all log files on startup for a fresh start
print("Deleting all log files on startup...")
for log_file in [LOG_FILE, STDOUT_LOG, STDERR_LOG]:
    try:
        if os.path.exists(log_file):
            os.remove(log_file)
            print(f"Deleted: {log_file}")
    except Exception as e:
        print(f"Warning: Could not delete {log_file}: {e}")
print("Log cleanup complete - starting with fresh logs")

# Configure logging to file
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class WhisperAPIService(win32serviceutil.ServiceFramework):
    _svc_name_ = "whisper-api"
    _svc_display_name_ = "Whisper API Server"
    _svc_description_ = "OpenAI Whisper API compatible transcription service"

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.stop_event = win32event.CreateEvent(None, 0, 0, None)
        self.is_running = False
        self.server_thread = None
        self.log_cleanup_thread = None

    def SvcStop(self):
        """Called when the service is requested to stop"""
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.stop_event)
        self.is_running = False
        msg = f"{self._svc_display_name_} - Received stop signal"
        logger.info(msg)
        servicemanager.LogInfoMsg(msg)

    def SvcDoRun(self):
        """Called when the service is started"""
        msg = f"{self._svc_display_name_} - Starting service"
        logger.info(msg)
        logger.info(f"Log file: {LOG_FILE}")
        servicemanager.LogInfoMsg(msg)

        # Report that we're starting
        self.ReportServiceStatus(win32service.SERVICE_START_PENDING)

        try:
            # Start the server in a background thread
            # The server (with model loading) runs in background
            self.is_running = True
            self.server_thread = threading.Thread(target=self._run_server, daemon=True)
            self.server_thread.start()

            # Start periodic log cleanup thread
            self.log_cleanup_thread = threading.Thread(target=self._periodic_log_cleanup, daemon=True)
            self.log_cleanup_thread.start()
            logger.info("Started periodic log cleanup thread (runs every hour)")

            # Wait for the server to become healthy
            host = os.getenv("WHISPER_HOST", "127.0.0.1")
            port = int(os.getenv("WHISPER_PORT", "4444"))
            health_url = f"http://{host}:{port}/v1/health"

            logger.info(f"Waiting for server to become healthy at {health_url}...")
            start_time = time.time()
            max_wait = 30  # 30 seconds max wait

            while time.time() - start_time < max_wait:
                try:
                    import urllib.request
                    with urllib.request.urlopen(health_url, timeout=1) as response:
                        if response.status == 200:
                            logger.info("Server health check passed")
                            break
                except Exception:
                    time.sleep(0.5)
            else:
                # Timeout reached, but continue anyway (server may still be loading model)
                logger.warning(f"Server health check timeout after {max_wait}s, continuing anyway")

            # IMPORTANT: Signal to Windows that we're running NOW
            # This happens BEFORE the model loads (which happens in server.py warmup)
            # Windows gets the "running" signal immediately, avoiding timeout
            self.ReportServiceStatus(win32service.SERVICE_RUNNING)
            msg = f"{self._svc_display_name_} - Service is running (model will load in background)"
            logger.info(msg)
            servicemanager.LogInfoMsg(msg)

            # Wait for stop signal
            win32event.WaitForSingleObject(self.stop_event, win32event.INFINITE)

            # Cleanup
            msg = f"{self._svc_display_name_} - Service stopped"
            logger.info(msg)
            servicemanager.LogInfoMsg(msg)

        except Exception as e:
            msg = f"{self._svc_display_name_} - Error: {str(e)}"
            logger.error(msg)
            servicemanager.LogErrorMsg(msg)
            self.SvcStop()

    def _periodic_log_cleanup(self):
        """Periodically cleanup log files to prevent them from growing too large"""
        while self.is_running:
            try:
                # Sleep for 1 hour between cleanups
                for _ in range(3600):
                    if not self.is_running:
                        break
                    time.sleep(1)

                if self.is_running:
                    logger.info("Running periodic log cleanup...")
                    cleanup_log_file(LOG_FILE)
                    cleanup_log_file(STDOUT_LOG)
                    cleanup_log_file(STDERR_LOG)
                    logger.info("Log cleanup completed")
            except Exception as e:
                logger.error(f"Error during periodic log cleanup: {e}")

    def _run_server(self):
        """Run the FastAPI/uvicorn server - this includes model loading warmup"""
        try:
            # Load environment variables from registry before importing server
            import winreg
            try:
                key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                    f"SYSTEM\\CurrentControlSet\\Services\\{self._svc_name_}\\Environment",
                                    0, winreg.KEY_READ)
                i = 0
                while True:
                    try:
                        name, value, _ = winreg.EnumValue(key, i)
                        os.environ[name] = str(value)
                        logger.info(f"Loaded environment variable: {name}={value}")
                        i += 1
                    except OSError:
                        break
                winreg.CloseKey(key)
            except FileNotFoundError:
                logger.warning("No environment variables found in registry for service")
            except Exception as e:
                logger.error(f"Error loading environment variables from registry: {e}")

            import uvicorn
            from server import app

            # Get configuration from environment or defaults
            host = os.getenv("WHISPER_HOST", "127.0.0.1")
            port = int(os.getenv("WHISPER_PORT", "4444"))

            msg = f"Starting uvicorn on {host}:{port}"
            logger.info(msg)
            servicemanager.LogInfoMsg(msg)

            msg = "Model will load during FastAPI startup event (warmup)"
            logger.info(msg)
            servicemanager.LogInfoMsg(msg)

            # Redirect stdout/stderr to log file
            stdout_log = os.path.join(LOG_DIR, "stdout.log")
            stderr_log = os.path.join(LOG_DIR, "stderr.log")

            logger.info(f"Redirecting stdout to: {stdout_log}")
            logger.info(f"Redirecting stderr to: {stderr_log}")

            # Run uvicorn - this blocks until server shuts down
            # The server.py @app.on_event("startup") warmup() will run here
            # This can take 30+ seconds, but Windows already thinks we're "running"
            uvicorn.run(
                app,
                host=host,
                port=port,
                log_level="info",
                access_log=True,
                log_config={
                    "version": 1,
                    "disable_existing_loggers": False,
                    "formatters": {
                        "default": {
                            "format": "%(asctime)s [%(levelname)s] %(message)s",
                        },
                    },
                    "handlers": {
                        "file": {
                            "class": "logging.FileHandler",
                            "filename": stdout_log,
                            "formatter": "default",
                        },
                    },
                    "root": {
                        "level": "INFO",
                        "handlers": ["file"],
                    },
                }
            )

        except Exception as e:
            import traceback
            error_detail = traceback.format_exc()
            msg = f"Failed to start server: {str(e)}\n{error_detail}"
            logger.error(msg)
            servicemanager.LogErrorMsg(f"Failed to start server: {str(e)}")
            self.is_running = False


if __name__ == '__main__':
    if len(sys.argv) == 1:
        # Called without arguments - start the service
        servicemanager.Initialize()
        servicemanager.PrepareToHostSingle(WhisperAPIService)
        servicemanager.StartServiceCtrlDispatcher()
    else:
        # Called with arguments - handle install/remove/start/stop commands
        win32serviceutil.HandleCommandLine(WhisperAPIService)
