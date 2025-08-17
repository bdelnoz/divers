#!/bin/bash
pkill xfdesktop
sleep 1
nohup xfdesktop >/dev/null 2>&1 &
xfce4-panel --restart
