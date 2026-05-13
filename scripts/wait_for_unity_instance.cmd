@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0wait_for_unity_instance.ps1" %*
