@echo off
rem Lets desk_ctrl_agent.exe (in this folder) receive connections from the phone on private networks.
rem Run it once: right-click > "Run as administrator".
netsh advfirewall firewall add rule name="DeskCtrl Agent" dir=in action=allow program="%~dp0desk_ctrl_agent.exe" enable=yes profile=private,domain
if errorlevel 1 (echo Could not add the rule. Right-click this file and choose "Run as administrator".) else (echo Done: the phone can now reach the agent.)
pause
