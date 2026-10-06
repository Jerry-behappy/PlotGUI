@echo off
cd /d "%~dp0"
python plot_gui.py %*
if errorlevel 1 pause
