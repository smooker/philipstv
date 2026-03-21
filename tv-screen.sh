#!/bin/bash
# tv-screen.sh — Virtual X screen on Philips TV via DLNA
# Creates a virtual display, captures it with ffmpeg NVENC, serves via HTTP, plays on TV
#
# Usage: ./tv-screen.sh [resolution] [display]
# Example: ./tv-screen.sh 1920x1080 :1

set -uo pipefail

RESOLUTION="${1:-1920x1080}"
DISPLAY_NUM="${2:-:1}"
PORT=8889
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHILIPS="$SCRIPT_DIR/philipstv.pl"
OUTFILE="/tmp/tv-screen.mp4"

echo "=== TV Virtual Screen ==="
echo "Display: $DISPLAY_NUM ($RESOLUTION)"
echo ""

# 1. Kill previous instances
fuser -k $PORT/tcp 2>/dev/null
pkill -f "Xephyr $DISPLAY_NUM" 2>/dev/null
sleep 1

# 2. Start Xephyr (virtual X server)
echo ">>> Starting Xephyr $DISPLAY_NUM ($RESOLUTION)..."
Xephyr $DISPLAY_NUM -screen $RESOLUTION -resizeable -no-host-grab &
XEPHYR_PID=$!
sleep 2

# 3. Start a window manager on virtual display
DISPLAY=$DISPLAY_NUM xfwm4 &
sleep 1

# 4. Open a terminal on virtual display
DISPLAY=$DISPLAY_NUM xterm -geometry 120x40 &

echo ">>> Virtual display ready"
echo ">>> Run apps with: DISPLAY=$DISPLAY_NUM <command>"
echo ""

# 5. Start ffmpeg capture → fragmented MP4
echo ">>> Starting screen capture (NVENC)..."
mkdir -p /tmp/tv-screen
DISPLAY=$DISPLAY_NUM ffmpeg -y     -f x11grab -framerate 25 -video_size $RESOLUTION -i $DISPLAY_NUM     -f pulse -i default     -c:v h264_nvenc -preset p4 -b:v 10M -g 50     -c:a aac -b:a 192k     -movflags +frag_keyframe+empty_moov+default_base_moof     -f mp4     -listen 1     "http://0.0.0.0:$PORT" &
FFMPEG_PID=$!
sleep 3

# 6. Send to TV via DLNA
LOCAL_IP=$(ip route get $(grep host ~/.philipstv.conf | awk "{print \$3}") 2>/dev/null | grep -oP "src \K[\d.]+")
STREAM_URL="http://$LOCAL_IP:$PORT"
echo ">>> Stream URL: $STREAM_URL"
echo ">>> Sending to TV..."
$PHILIPS dlna-play "$STREAM_URL"

echo ""
echo "=== TV Screen Active ==="
echo "Display: DISPLAY=$DISPLAY_NUM"
echo "Run apps: DISPLAY=$DISPLAY_NUM firefox"
echo "          DISPLAY=$DISPLAY_NUM vlc movie.mp4"
echo "Stop: kill $XEPHYR_PID (Xephyr) + kill $FFMPEG_PID (ffmpeg)"
echo ""

# Save PIDs
echo "$XEPHYR_PID" > /tmp/tv-screen.pids
echo "$FFMPEG_PID" >> /tmp/tv-screen.pids

# Wait
wait $FFMPEG_PID 2>/dev/null
