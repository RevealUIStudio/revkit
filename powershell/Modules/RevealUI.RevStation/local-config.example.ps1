# Copy this file to local-config.ps1 (gitignored) and fill in your values.
# local-config.ps1 is dot-sourced by Mount-WSLDev at runtime.

# Your Sandbox SSD serial number — find it with: Get-Disk | Select-Object Number, SerialNumber
$DevDriveSerial = 'YOUR-SSD-SERIAL-HERE'
