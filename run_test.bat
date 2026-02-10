@echo off
:: Test file to verify the watcher is working
echo Test was executed at %date% %time% > "%APPDATA%\WinData\test_result.txt"
msg * "Watcher is working! Check WinData folder for test_result.txt"
