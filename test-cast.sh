#!/bin/bash
# test cast to Philips TV
SCRIPT="/chroot/claude/home/claude-agent/work/machines/tools/philipstv/philipstv.pl"
VIDEO="$HOME/Videos/GLASAT_NA_BASHTITE/AQMLAUlB-Cw7nQE27uwkoLP8rOvX-mvWitwUOX8j2r7vr-9QHuJu6kSLGzJQIDDo2smoIoa6nu7FDrjR2ACWJp2Bx4JO3wloJlzEtg47pRZiZw.mp4"

$SCRIPT --nvenc --debug cast "$VIDEO"
