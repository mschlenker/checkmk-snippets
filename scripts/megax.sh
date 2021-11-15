#!/bin/bash
# 
# Start Firefox in a large dummy display to be able to get high resolution
# screenshots.

# Dependencies:
# sudo apt-get install xfce4-terminal xterm rxvt-unicode x11vnc xvfb xfwm4 openbox

# Other suggestions: xterm, xfce4-terminal
TERMINAL=urxvt
# Alternative suggestions: openbox, i3, fluxbox, twm, icewm
WINMANAGER=xfwm4
WIDTH=3840
HEIGHT=3840
DPI=96
DPNUM=":7"
FFPROFILE=CMK

Xvfb ${DPNUM} -retro -nolisten tcp -dpi ${DPI} -screen ${DPNUM} ${WIDTH}x${HEIGHT}x24 &
sleep 3

DISPLAY=${DPNUM} ${TERMINAL} &
DISPLAY=${DPNUM} firefox -P ${FFPROFILE} -no-remote &
# Might be redundant, I don't care...
DISPLAY=${DPNUM} x11vnc -loop -display ${DPNUM} &
DISPLAY=${DPNUM} ${WINMANAGER} &

# Start xfsettingsd here if needed. You can configure the appearance (icons,
# theme, colors, fonts) with xfce4-settings-manager 

# Now use any usable VNC viewer to access the desktop. I suggest Remmina,
# since this allows scaling. 
#
# To take screenshots you can run in any terminal:
#
# DISPLAY=:7 scrot /tmp/mycmkscreenshot.png 
#
# Run in a terminal of its own. Or to kill: Close firefox, then first kill
# x11vnc, then kill Xvfb.
#
# Have fun! Mattias 