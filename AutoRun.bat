echo off
cd /d %~dp0
Powershell -ExecutionPolicy RemoteSigned -File .\AutoRun.ps1
pause
