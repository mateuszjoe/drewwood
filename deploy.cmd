@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy-ftp.ps1" %*
