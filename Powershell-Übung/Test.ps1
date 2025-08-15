
# Get Operating System information
Write-Host "Operating System:" -ForegroundColor Cyan
sw_vers

# Get CPU information
Write-Host "`nCPU Information:" -ForegroundColor Cyan
sysctl -n machdep.cpu.brand_string

# Get Memory information
Write-Host "`nMemory Information:" -ForegroundColor Cyan
sysctl hw.memsize | ForEach-Object { "Memory Size: $($_ -replace 'hw.memsize: ', '') bytes" }

# Get Disk information
Write-Host "`nDisk Information:" -ForegroundColor Cyan
diskutil list

# Get GPU information
Write-Host "`nGPU Information:" -ForegroundColor Cyan
system_profiler SPDisplaysDataType | Select-String -Pattern "Chipset Model|VRAM"