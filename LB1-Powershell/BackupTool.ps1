#!/usr/bin/env pwsh
<#
=========================================
BackupTool.ps1 
Simple backup tool with ZIP creation and versioning
Matches the README documentation
=========================================

Usage:
  Windows (GUI):     pwsh -File BackupTool.ps1
  Terminal mode:     pwsh -File BackupTool.ps1 -Terminal
  macOS/Linux:       Automatically uses terminal mode

Features:
- Source/Target folder selection
- ZIP backup option  
- Automatic versioning (no overwriting)
- Configuration persistence
- Detailed logging
#>

param(
    [switch]$Terminal,
    [string]$SourceFolder = "",
    [string]$TargetFolder = "",
    [switch]$ZipBackup,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Script configuration
$Script:ConfigPath = Join-Path $PSScriptRoot 'config.json'
$Script:LogFile = Join-Path $PSScriptRoot 'backup.log'

# Show help if requested
if ($Help) {
    Write-Host @"
BackupTool.ps1 - Simple Backup Tool with Versioning

USAGE:
  Windows (GUI):     pwsh -File BackupTool.ps1
  Terminal mode:     pwsh -File BackupTool.ps1 -Terminal  
  macOS/Linux:       Uses terminal mode automatically
  
PARAMETERS:
  -Terminal          Force terminal mode
  -SourceFolder      Source folder to backup
  -TargetFolder      Target folder for backup
  -ZipBackup         Create ZIP archive instead of folder copy
  -Help              Show this help

EXAMPLES:
  pwsh -File BackupTool.ps1 -Terminal
  pwsh -File BackupTool.ps1 -SourceFolder "C:\MyData" -TargetFolder "C:\Backups" -ZipBackup
  
The tool supports automatic versioning - existing backups are never overwritten.
"@
    exit 0
}

# Force terminal mode on non-Windows or when explicitly requested
if (-not $IsWindows -or $Terminal) {
    $Terminal = $true
}

#region Core Functions

function Get-DefaultConfig {
    return [pscustomobject]@{
        SourceFolder = ""
        TargetFolder = ""
        ZipBackup    = $false
        LogFile      = "./LB1-Powershell/backup.log"
    }
}

function Get-Configuration {
    try {
        if (Test-Path -LiteralPath $Script:ConfigPath) {
            $cfg = Get-Content -Raw -LiteralPath $Script:ConfigPath | ConvertFrom-Json
            Write-Log "Configuration loaded from $Script:ConfigPath"
            return $cfg
        }
    } catch {
        Write-Log "Error loading configuration: $($_.Exception.Message)" 'WARN'
    }
    
    $cfg = Get-DefaultConfig
    Set-Configuration $cfg
    return $cfg
}

function Set-Configuration([object]$cfg) {
    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $Script:ConfigPath
        Write-Log "Configuration saved to $Script:ConfigPath"
    } catch {
        Write-Log "Error saving configuration: $($_.Exception.Message)" 'ERROR'
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$timestamp [$Level] $Message" | Out-File -Append -FilePath $Script:LogFile -Encoding UTF8
    } catch {
        Write-Host "LOG ERROR: $Message" -ForegroundColor Yellow
    }
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        [void][System.IO.Directory]::CreateDirectory($full)
        return $full
    } catch {
        throw
    }
}

function Get-NextVersionedPath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [string]$VersionFormat = '_{DATE}_v{0}'
    )

    $directory = Split-Path -Path $BasePath -Parent
    $filename  = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
    $extension = [System.IO.Path]::GetExtension($BasePath)

    # If the original path doesn't exist, return it unchanged
    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $BasePath
    }

    # Build versioned name with date
    $now = Get-Date
    $vf  = $VersionFormat -replace '\{DATE\}', $now.ToString('dd-MM-yyyy')

    $version = 1
    do {
        $suffixRaw  = $vf -f $version
        $suffixSafe = $suffixRaw -replace '[\\\/:*?"<>|]', '-'
        $versionedName = "$filename$suffixSafe$extension"
        $versionedPath = if ([string]::IsNullOrWhiteSpace($directory)) { $versionedName } else { Join-Path $directory $versionedName }
        $version++
    } while (Test-Path -LiteralPath $versionedPath)

    Write-Log "Created versioned path: $versionedPath (version $($version-1))"
    return $versionedPath
}

function Start-BackupProcess {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [switch]$CreateZip
    )
    
    # Validate source
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source path does not exist: $Source"
    }
    
    # Prepare target with versioning
    $finalTarget = Get-NextVersionedPath -BasePath $Target
    
    try {
        if ($CreateZip) {
            # Ensure ZIP extension
            if ([System.IO.Path]::GetExtension($finalTarget) -ne '.zip') {
                $finalTarget = "$finalTarget.zip"
            }
            
            Write-Log "Creating ZIP backup: $Source -> $finalTarget"
            Write-Host "Creating ZIP backup..." -ForegroundColor Yellow
            
            Compress-Archive -Path $Source -DestinationPath $finalTarget -Force
            
            $zipInfo = Get-Item -LiteralPath $finalTarget
            Write-Log "ZIP backup completed: $($zipInfo.Length) bytes"
            Write-Host "✓ ZIP backup completed: $finalTarget" -ForegroundColor Green
            Write-Host "  Size: $([Math]::Round($zipInfo.Length/1MB, 2)) MB" -ForegroundColor Gray
            
        } else {
            # Folder backup
            $targetFull = New-DirectoryIfMissing $finalTarget
            
            Write-Log "Starting folder backup: $Source -> $targetFull"
            Write-Host "Creating folder backup..." -ForegroundColor Yellow
            
            $items = Get-ChildItem -Path $Source -Recurse
            $totalFiles = ($items | Where-Object { -not $_.PSIsContainer }).Count
            $processed = 0
            $errors = 0
            
            foreach ($item in $items) {
                try {
                    $relativePath = $item.FullName.Substring($Source.Length + 1)
                    $destPath = Join-Path $targetFull $relativePath
                    
                    if ($item.PSIsContainer) {
                        New-DirectoryIfMissing $destPath | Out-Null
                    } else {
                        $destDir = Split-Path $destPath -Parent
                        if ($destDir -and -not (Test-Path $destDir)) {
                            New-DirectoryIfMissing $destDir | Out-Null
                        }
                        Copy-Item -LiteralPath $item.FullName -Destination $destPath -Force
                        $processed++
                        
                        if ($processed % 10 -eq 0) {
                            Write-Host "  Progress: $processed/$totalFiles files" -ForegroundColor Gray
                        }
                    }
                } catch {
                    $errors++
                    Write-Log "Error copying $($item.FullName): $($_.Exception.Message)" 'ERROR'
                }
            }
            
            Write-Log "Folder backup completed: $processed files, $errors errors"
            Write-Host "✓ Folder backup completed: $finalTarget" -ForegroundColor Green
            Write-Host "  Files: $processed, Errors: $errors" -ForegroundColor Gray
        }
        
        return $finalTarget
        
    } catch {
        Write-Log "Backup failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#endregion

#region Terminal Mode

function Start-TerminalMode {
    Write-Host "=== BackupTool - Terminal Mode ===" -ForegroundColor Cyan
    Write-Log "BackupTool started in terminal mode"
    
    # Load configuration
    $cfg = Get-Configuration
    
    # Override with command line parameters
    if ($SourceFolder) { $cfg.SourceFolder = $SourceFolder }
    if ($TargetFolder) { $cfg.TargetFolder = $TargetFolder }
    if ($ZipBackup) { $cfg.ZipBackup = $ZipBackup }
    
    do {
        Write-Host "`n--- Main Menu ---" -ForegroundColor Yellow
        Write-Host "1) Set Source Folder    (current: $($cfg.SourceFolder))"
        Write-Host "2) Set Target Folder    (current: $($cfg.TargetFolder))"
        Write-Host "3) Toggle ZIP Backup    (current: $($cfg.ZipBackup))"
        Write-Host "4) Run Backup"
        Write-Host "5) View Log"
        Write-Host "6) Exit"
        
        $choice = Read-Host "`nSelect option (1-6)"
        
        switch ($choice) {
            '1' {
                $newSource = Read-Host "Enter source folder path"
                if ($newSource -and (Test-Path -LiteralPath $newSource)) {
                    $cfg.SourceFolder = $newSource
                    Write-Host "✓ Source folder set" -ForegroundColor Green
                } elseif ($newSource) {
                    Write-Host "✗ Path does not exist: $newSource" -ForegroundColor Red
                }
            }
            '2' {
                $newTarget = Read-Host "Enter target folder/file path"
                if ($newTarget) {
                    $cfg.TargetFolder = $newTarget
                    Write-Host "✓ Target folder set" -ForegroundColor Green
                }
            }
            '3' {
                $cfg.ZipBackup = -not $cfg.ZipBackup
                Write-Host "✓ ZIP backup: $($cfg.ZipBackup)" -ForegroundColor Green
            }
            '4' {
                if (-not $cfg.SourceFolder -or -not $cfg.TargetFolder) {
                    Write-Host "✗ Please set both source and target folders first" -ForegroundColor Red
                    continue
                }
                
                try {
                    Write-Host "`nStarting backup..." -ForegroundColor Cyan
                    $result = Start-BackupProcess -Source $cfg.SourceFolder -Target $cfg.TargetFolder -CreateZip:$cfg.ZipBackup
                    Write-Host "✓ Backup completed successfully!" -ForegroundColor Green
                    Write-Host "  Location: $result" -ForegroundColor Gray
                } catch {
                    Write-Host "✗ Backup failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            '5' {
                if (Test-Path $Script:LogFile) {
                    Write-Host "`n--- Recent Log Entries ---" -ForegroundColor Yellow
                    Get-Content $Script:LogFile | Select-Object -Last 20 | ForEach-Object {
                        if ($_ -match '\[ERROR\]') {
                            Write-Host $_ -ForegroundColor Red
                        } elseif ($_ -match '\[WARN\]') {
                            Write-Host $_ -ForegroundColor Yellow
                        } else {
                            Write-Host $_ -ForegroundColor Gray
                        }
                    }
                } else {
                    Write-Host "No log file found" -ForegroundColor Gray
                }
            }
            '6' {
                Set-Configuration $cfg
                Write-Host "Goodbye!" -ForegroundColor Green
                Write-Log "BackupTool terminated by user"
                break
            }
            default {
                Write-Host "Invalid option. Please select 1-6." -ForegroundColor Red
            }
        }
    } while ($true)
}

#endregion

#region GUI Mode (Windows only)

function Start-GuiMode {
    Write-Log "BackupTool started in GUI mode"
    
    # Load Windows Forms
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $cfg = Get-Configuration
    
    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'BackupTool - Simple Backup with Versioning'
    $form.Size = New-Object System.Drawing.Size(600, 400)
    $form.StartPosition = 'CenterScreen'
    
    # Source folder
    $lblSource = New-Object System.Windows.Forms.Label
    $lblSource.Text = 'Source Folder:'
    $lblSource.Location = New-Object System.Drawing.Point(20, 20)
    $lblSource.Size = New-Object System.Drawing.Size(100, 20)
    
    $txtSource = New-Object System.Windows.Forms.TextBox
    $txtSource.Location = New-Object System.Drawing.Point(20, 45)
    $txtSource.Size = New-Object System.Drawing.Size(400, 25)
    $txtSource.Text = $cfg.SourceFolder
    
    $btnBrowseSource = New-Object System.Windows.Forms.Button
    $btnBrowseSource.Text = 'Browse...'
    $btnBrowseSource.Location = New-Object System.Drawing.Point(430, 43)
    $btnBrowseSource.Size = New-Object System.Drawing.Size(80, 28)
    
    # Target folder
    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = 'Target Folder:'
    $lblTarget.Location = New-Object System.Drawing.Point(20, 90)
    $lblTarget.Size = New-Object System.Drawing.Size(100, 20)
    
    $txtTarget = New-Object System.Windows.Forms.TextBox
    $txtTarget.Location = New-Object System.Drawing.Point(20, 115)
    $txtTarget.Size = New-Object System.Drawing.Size(400, 25)
    $txtTarget.Text = $cfg.TargetFolder
    
    $btnBrowseTarget = New-Object System.Windows.Forms.Button
    $btnBrowseTarget.Text = 'Browse...'
    $btnBrowseTarget.Location = New-Object System.Drawing.Point(430, 113)
    $btnBrowseTarget.Size = New-Object System.Drawing.Size(80, 28)
    
    # ZIP option
    $chkZip = New-Object System.Windows.Forms.CheckBox
    $chkZip.Text = 'Create ZIP archive instead of folder copy'
    $chkZip.Location = New-Object System.Drawing.Point(20, 160)
    $chkZip.Size = New-Object System.Drawing.Size(350, 20)
    $chkZip.Checked = $cfg.ZipBackup
    
    # Buttons
    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = 'Run Backup'
    $btnBackup.Location = New-Object System.Drawing.Point(20, 200)
    $btnBackup.Size = New-Object System.Drawing.Size(100, 35)
    $btnBackup.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 9, [System.Drawing.FontStyle]::Bold)
    
    $btnViewLog = New-Object System.Windows.Forms.Button
    $btnViewLog.Text = 'View Log'
    $btnViewLog.Location = New-Object System.Drawing.Point(140, 200)
    $btnViewLog.Size = New-Object System.Drawing.Size(80, 35)
    
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = 'Exit'
    $btnExit.Location = New-Object System.Drawing.Point(240, 200)
    $btnExit.Size = New-Object System.Drawing.Size(80, 35)
    
    # Status label
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = 'Ready'
    $lblStatus.Location = New-Object System.Drawing.Point(20, 260)
    $lblStatus.Size = New-Object System.Drawing.Size(500, 20)
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    
    # Event handlers
    $btnBrowseSource.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select source folder to backup"
        if ($txtSource.Text) { $fbd.SelectedPath = $txtSource.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtSource.Text = $fbd.SelectedPath
        }
    })
    
    $btnBrowseTarget.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select target folder for backup"
        if ($txtTarget.Text) { $fbd.SelectedPath = $txtTarget.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtTarget.Text = $fbd.SelectedPath
        }
    })
    
    $btnBackup.Add_Click({
        $source = $txtSource.Text.Trim()
        $target = $txtTarget.Text.Trim()
        
        if (-not $source -or -not $target) {
            [System.Windows.Forms.MessageBox]::Show("Please specify both source and target folders.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        try {
            $lblStatus.Text = "Backup in progress..."
            $lblStatus.ForeColor = [System.Drawing.Color]::Blue
            [System.Windows.Forms.Application]::DoEvents()
            
            $result = Start-BackupProcess -Source $source -Target $target -CreateZip:$chkZip.Checked
            
            $lblStatus.Text = "Backup completed successfully!"
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            
            [System.Windows.Forms.MessageBox]::Show("Backup completed successfully!`n`nLocation: $result", "Backup Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            
        } catch {
            $lblStatus.Text = "Backup failed!"
            $lblStatus.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.MessageBox]::Show("Backup failed: $($_.Exception.Message)", "Backup Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    
    $btnViewLog.Add_Click({
        if (Test-Path $Script:LogFile) {
            Start-Process -FilePath "notepad.exe" -ArgumentList $Script:LogFile -ErrorAction SilentlyContinue
        } else {
            [System.Windows.Forms.MessageBox]::Show("No log file found.", "Log File", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    
    $btnExit.Add_Click({
        # Save configuration
        $cfg.SourceFolder = $txtSource.Text.Trim()
        $cfg.TargetFolder = $txtTarget.Text.Trim()
        $cfg.ZipBackup = $chkZip.Checked
        Set-Configuration $cfg
        
        $form.Close()
    })
    
    # Add controls to form
    $form.Controls.AddRange(@($lblSource, $txtSource, $btnBrowseSource, $lblTarget, $txtTarget, $btnBrowseTarget, $chkZip, $btnBackup, $btnViewLog, $btnExit, $lblStatus))
    
    # Show form
    Write-Log "GUI initialized successfully"
    [System.Windows.Forms.Application]::Run($form)
    Write-Log "GUI closed"
}

#endregion

#region Main Entry Point

# Initialize logging
Write-Log "BackupTool started (Terminal: $Terminal, IsWindows: $IsWindows)"

try {
    if ($Terminal -or -not $IsWindows) {
        Start-TerminalMode
    } else {
        try {
            Start-GuiMode
        } catch {
            Write-Host "GUI mode failed, falling back to terminal mode" -ForegroundColor Yellow
            Write-Log "GUI mode failed: $($_.Exception.Message), falling back to terminal" 'WARN'
            Start-TerminalMode
        }
    }
} catch {
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
    exit 1
} finally {
    Write-Log "BackupTool session ended"
}

#endregion