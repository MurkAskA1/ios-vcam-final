@echo off
REM ========================================
REM Virtual Camera Pro - Stream Starter
REM Converts OBS RTMP to HTTP for iPhone
REM ========================================

echo.
echo ========================================
echo Virtual Camera Pro - Stream Server
echo ========================================
echo.
echo Starting RTMP to HTTP converter...
echo.
echo OBS Stream: rtmp://localhost:1935/live/stream
echo HTTP Stream: http://0.0.0.0:8888/live
echo.
echo iPhone should connect to:
echo http://192.168.1.44:8888/live
echo.
echo Press CTRL+C to stop streaming
echo.

REM Check if FFmpeg is installed
where ffmpeg >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: FFmpeg not found!
    echo.
    echo Please download FFmpeg from:
    echo https://www.gyan.dev/ffmpeg/builds/ffmpeg-full.7z
    echo.
    echo Or use Windows Store:
    echo winget install FFmpeg
    echo.
    pause
    exit /b 1
)

REM Start streaming
ffmpeg -i rtmp://localhost:1935/live/stream ^
    -vcodec mjpeg ^
    -q:v 5 ^
    -f mpjpeg ^
    http://0.0.0.0:8888/live

pause
