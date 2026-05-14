@echo off
REM ======================================
REM Virtual Camera Pro - Stream Starter
REM Converts OBS RTMP to HTTP for iPhone
REM ======================================

echo.
echo ======================================
echo Virtual Camera Pro - Stream Server
echo ======================================
echo.
echo Starting RTMP to HTTP converter...
echo.
echo OBS Stream: rtmp://localhost:1935/live/stream
echo HTTP Stream: http://localhost:8888/live
echo.
echo iPhone should connect to your local IP address.
echo Example: http://192.168.1.XX:8888/live
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

REM Start streaming with -listen flag to act as a server
ffmpeg -i rtmp://localhost:1935/live/stream ^
    -vcodec mjpeg ^
    -q:v 5 ^
    -f mpjpeg ^
    -listen 1 ^
    http://0.0.0.0:8888/live

pause
