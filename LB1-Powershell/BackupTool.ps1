<#
=========================================
BackupTool.ps1 
Einfaches Backup-Skript mit optionaler ZIP-Erstellung
=========================================

Hinweise:
- Unterstützt Windows-GUI und Terminal-Modus für Linux/macOS
- Konfiguration wird in config.json gespeichert
- Logs werden in backup.log geschrieben
#>

param(
    [switch]$Terminal  # Erzwinge Terminal-Modus auch unter Windows
)

$ErrorActionPreference = 'Stop'

# Konfiguration & Log – im Skriptordner  
$Script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'config.json'
$Script:LogFile    = Join-Path -Path $PSScriptRoot -ChildPath 'backup.log'

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
            $cfg = Get-Content -Raw -LiteralPath $Script:ConfigPath | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $cfg) { return Get-DefaultConfig }
            return $cfg
        } else {
            $def = Get-DefaultConfig
            $def | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $Script:ConfigPath
            return $def
        }
    } catch {
        return Get-DefaultConfig
    }
}

function Set-Configuration([object]$cfg) {
    try { 
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $Script:ConfigPath 
        Write-Log "Konfiguration gespeichert"
    } catch { 
        Write-Log "Fehler beim Speichern der Konfiguration: $($_.Exception.Message)" 'ERROR'
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
        Write-Host "LOGFEHLER: $Message" -ForegroundColor Yellow
    }
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            [void](New-Item -ItemType Directory -Path $Path -Force)
            Write-Log "Verzeichnis erstellt: $Path"
        } catch {
            Write-Log "Fehler beim Erstellen des Verzeichnisses '$Path': $($_.Exception.Message)" 'ERROR'
            throw
        }
    }
}

function Start-Backup {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [bool]$CreateZip = $false
    )
    
    Write-Log "Backup gestartet - Quelle: '$Source' Ziel: '$Target' ZIP: $CreateZip"
    
    # Validierung
    if (-not (Test-Path -LiteralPath $Source)) {
        $msg = "Quellordner existiert nicht: '$Source'"
        Write-Log $msg 'ERROR'
        throw $msg
    }
    
    # Zielverzeichnis erstellen falls nötig
    New-DirectoryIfMissing $Target
    
    # Backup-Namen mit Zeitstempel generieren
    $sourceName = Split-Path -Path $Source -Leaf
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    
    try {
        if ($CreateZip) {
            # ZIP-Backup erstellen
            $zipName = "${sourceName}_backup_${timestamp}.zip"
            $zipPath = Join-Path -Path $Target -ChildPath $zipName
            
            Write-Log "Erstelle ZIP-Backup: $zipPath"
            Compress-Archive -Path $Source -DestinationPath $zipPath -Force
            Write-Log "ZIP-Backup erfolgreich erstellt: $zipPath"
            
            return $zipPath
        } else {
            # Ordner-Backup erstellen
            $backupName = "${sourceName}_backup_${timestamp}"
            $backupPath = Join-Path -Path $Target -ChildPath $backupName
            
            Write-Log "Erstelle Ordner-Backup: $backupPath"
            Copy-Item -Path $Source -Destination $backupPath -Recurse -Force
            Write-Log "Ordner-Backup erfolgreich erstellt: $backupPath"
            
            return $backupPath
        }
    } catch {
        $msg = "Backup-Fehler: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        throw $msg
    }
}

function Show-TerminalMenu {
    $cfg = Get-Configuration
    
    do {
        Clear-Host
        Write-Host "=== BackupTool ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Aktuelle Konfiguration:"
        Write-Host "  Quelle:    $($cfg.SourceFolder)" -ForegroundColor Gray
        Write-Host "  Ziel:      $($cfg.TargetFolder)" -ForegroundColor Gray  
        Write-Host "  ZIP-Modus: $($cfg.ZipBackup)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "1) Quellordner setzen"
        Write-Host "2) Zielordner setzen"
        Write-Host "3) ZIP-Modus umschalten (aktuell: $($cfg.ZipBackup))"
        Write-Host "4) Backup ausführen"
        Write-Host "5) Log anzeigen"
        Write-Host "6) Beenden"
        Write-Host ""
        
        $choice = Read-Host "Auswahl (1-6)"
        
        switch ($choice) {
            '1' {
                $newSource = Read-Host "Quellordner eingeben"
                if ($newSource -and (Test-Path -LiteralPath $newSource)) {
                    $cfg.SourceFolder = $newSource
                    Set-Configuration $cfg
                    Write-Host "Quellordner gesetzt: $newSource" -ForegroundColor Green
                } else {
                    Write-Host "Ungültiger Pfad oder Ordner existiert nicht!" -ForegroundColor Red
                }
                Read-Host "Weiter mit Enter"
            }
            
            '2' {
                $newTarget = Read-Host "Zielordner eingeben"
                if ($newTarget) {
                    $cfg.TargetFolder = $newTarget
                    Set-Configuration $cfg
                    Write-Host "Zielordner gesetzt: $newTarget" -ForegroundColor Green
                } else {
                    Write-Host "Ungültiger Pfad!" -ForegroundColor Red
                }
                Read-Host "Weiter mit Enter"
            }
            
            '3' {
                $cfg.ZipBackup = -not $cfg.ZipBackup
                Set-Configuration $cfg
                Write-Host "ZIP-Modus: $($cfg.ZipBackup)" -ForegroundColor Green
                Read-Host "Weiter mit Enter"
            }
            
            '4' {
                if (-not $cfg.SourceFolder -or -not $cfg.TargetFolder) {
                    Write-Host "Bitte erst Quelle und Ziel setzen!" -ForegroundColor Red
                    Read-Host "Weiter mit Enter"
                    continue
                }
                
                try {
                    Write-Host "Starte Backup..." -ForegroundColor Yellow
                    $result = Start-Backup -Source $cfg.SourceFolder -Target $cfg.TargetFolder -CreateZip $cfg.ZipBackup
                    Write-Host "Backup erfolgreich erstellt: $result" -ForegroundColor Green
                } catch {
                    Write-Host "Backup fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
                }
                Read-Host "Weiter mit Enter"
            }
            
            '5' {
                if (Test-Path -LiteralPath $Script:LogFile) {
                    Write-Host "=== Log-Inhalt ===" -ForegroundColor Cyan
                    Get-Content -LiteralPath $Script:LogFile | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
                } else {
                    Write-Host "Log-Datei nicht gefunden." -ForegroundColor Yellow
                }
                Read-Host "Weiter mit Enter"
            }
            
            '6' {
                Write-Host "Auf Wiedersehen!" -ForegroundColor Green
                return
            }
            
            default {
                Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Start-GUI {
    # Prüfe ob Windows Forms verfügbar ist
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        Write-Log "Windows Forms nicht verfügbar, wechsle zu Terminal-Modus" 'WARN'
        return $false
    }
    
    # STA-Modus für GUI erforderlich
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        try {
            Write-Log "Starte neu im STA-Modus"
            Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile','-STA','-File',$PSCommandPath) -Wait
            return $true
        } catch {
            Write-Log "STA-Modus nicht verfügbar" 'WARN'
            return $false
        }
    }
    
    $cfg = Get-Configuration
    
    # GUI erstellen
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'BackupTool'
    $form.Size = New-Object System.Drawing.Size(500,300)
    $form.StartPosition = 'CenterScreen'
    
    # Quelle-Gruppe
    $lblSource = New-Object System.Windows.Forms.Label
    $lblSource.Text = 'Quellordner:'
    $lblSource.Location = New-Object System.Drawing.Point(10,20)
    $lblSource.AutoSize = $true
    
    $tbSource = New-Object System.Windows.Forms.TextBox
    $tbSource.Location = New-Object System.Drawing.Point(10,40)
    $tbSource.Width = 350
    $tbSource.Text = $cfg.SourceFolder
    
    $btnBrowseSource = New-Object System.Windows.Forms.Button
    $btnBrowseSource.Text = '...'
    $btnBrowseSource.Location = New-Object System.Drawing.Point(370,38)
    $btnBrowseSource.Width = 30
    
    # Ziel-Gruppe
    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = 'Zielordner:'
    $lblTarget.Location = New-Object System.Drawing.Point(10,80)
    $lblTarget.AutoSize = $true
    
    $tbTarget = New-Object System.Windows.Forms.TextBox
    $tbTarget.Location = New-Object System.Drawing.Point(10,100)
    $tbTarget.Width = 350
    $tbTarget.Text = $cfg.TargetFolder
    
    $btnBrowseTarget = New-Object System.Windows.Forms.Button
    $btnBrowseTarget.Text = '...'
    $btnBrowseTarget.Location = New-Object System.Drawing.Point(370,98)
    $btnBrowseTarget.Width = 30
    
    # ZIP-Option
    $cbZip = New-Object System.Windows.Forms.CheckBox
    $cbZip.Text = 'Als ZIP-Archiv erstellen'
    $cbZip.Location = New-Object System.Drawing.Point(10,140)
    $cbZip.AutoSize = $true
    $cbZip.Checked = $cfg.ZipBackup
    
    # Buttons
    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = 'Backup ausführen'
    $btnBackup.Location = New-Object System.Drawing.Point(10,180)
    $btnBackup.Width = 120
    
    $btnViewLog = New-Object System.Windows.Forms.Button
    $btnViewLog.Text = 'Log anzeigen'
    $btnViewLog.Location = New-Object System.Drawing.Point(140,180)
    $btnViewLog.Width = 120
    
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = 'Beenden'
    $btnExit.Location = New-Object System.Drawing.Point(270,180)
    $btnExit.Width = 120
    
    # Status
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = 'Bereit'
    $lblStatus.Location = New-Object System.Drawing.Point(10,220)
    $lblStatus.AutoSize = $true
    
    # Event-Handler
    $btnBrowseSource.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Quellordner auswählen'
        if ($fbd.ShowDialog() -eq 'OK') { $tbSource.Text = $fbd.SelectedPath }
    })
    
    $btnBrowseTarget.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog  
        $fbd.Description = 'Zielordner auswählen'
        if ($fbd.ShowDialog() -eq 'OK') { $tbTarget.Text = $fbd.SelectedPath }
    })
    
    $btnBackup.Add_Click({
        $source = $tbSource.Text.Trim()
        $target = $tbTarget.Text.Trim()
        $useZip = $cbZip.Checked
        
        if (-not $source -or -not $target) {
            [System.Windows.Forms.MessageBox]::Show('Bitte Quelle und Ziel angeben!','Fehler')
            return
        }
        
        try {
            $lblStatus.Text = 'Backup läuft...'
            $form.Refresh()
            
            $result = Start-Backup -Source $source -Target $target -CreateZip $useZip
            $lblStatus.Text = 'Backup erfolgreich'
            [System.Windows.Forms.MessageBox]::Show("Backup erfolgreich erstellt:`n$result",'Erfolg')
        } catch {
            $lblStatus.Text = 'Backup fehlgeschlagen'
            [System.Windows.Forms.MessageBox]::Show("Backup fehlgeschlagen:`n$($_.Exception.Message)",'Fehler')
        }
    })
    
    $btnViewLog.Add_Click({
        if (Test-Path -LiteralPath $Script:LogFile) {
            try {
                Start-Process -FilePath 'notepad.exe' -ArgumentList $Script:LogFile -ErrorAction Stop
            } catch {
                # Fallback für nicht-Windows Systeme
                $logContent = Get-Content -LiteralPath $Script:LogFile | Select-Object -Last 20 | Out-String
                [System.Windows.Forms.MessageBox]::Show($logContent,'Log (letzte 20 Zeilen)')
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show('Log-Datei nicht gefunden.','Hinweis')
        }
    })
    
    $btnExit.Add_Click({ $form.Close() })
    
    # Beim Schließen Konfiguration speichern
    $form.Add_FormClosing({
        $cfg.SourceFolder = $tbSource.Text.Trim()
        $cfg.TargetFolder = $tbTarget.Text.Trim()
        $cfg.ZipBackup = $cbZip.Checked
        Set-Configuration $cfg
    })
    
    # Controls hinzufügen
    $form.Controls.AddRange(@(
        $lblSource, $tbSource, $btnBrowseSource,
        $lblTarget, $tbTarget, $btnBrowseTarget,
        $cbZip, $btnBackup, $btnViewLog, $btnExit, $lblStatus
    ))
    
    Write-Log "GUI gestartet"
    [void]$form.ShowDialog()
    Write-Log "GUI beendet"
    
    return $true
}

# Hauptprogramm - nur wenn direkt ausgeführt
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.') {
    Write-Log "BackupTool gestartet"

    # Bestimme ob GUI oder Terminal-Modus
    $useGUI = $false

    if (-not $Terminal) {
        # Windows: Versuche GUI
        if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
            $useGUI = Start-GUI
        }
    }

    # Fallback zu Terminal-Modus
    if (-not $useGUI) {
        Write-Host "Terminal-Modus wird verwendet" -ForegroundColor Yellow
        Show-TerminalMenu  
    }

    Write-Log "BackupTool beendet"
}