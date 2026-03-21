#!/bin/bash
# tv-screen-stop.sh — Stop virtual TV screen
echo "Stopping TV screen..."
if [ -f /tmp/tv-screen.pids ]; then
    while read pid; do
        kill "$pid" 2>/dev/null && echo "Killed PID $pid"
    done < /tmp/tv-screen.pids
    rm /tmp/tv-screen.pids
fi
fuser -k 8889/tcp 2>/dev/null
pkill -f "Xephyr :1" 2>/dev/null
echo "Done."
