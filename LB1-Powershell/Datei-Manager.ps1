<#
 =========================================
 FileManager.ps1 (GUI)
 Dateien nach Endungen suchen und verwalten – mit einfacher GUI
 =========================================

 Hinweise:
 - Das Skript startet eine Windows-Forms-GUI.
 - Logs werden in "FileManager.log" im Skriptordner geschrieben.
#>

$ErrorActionPreference = 'Stop'

# Konfiguration & Log – im Skriptordner (separate Configs für unterschiedliche Tools)
$Script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'datei-manager-config.json'
$Script:LogFile    = Join-Path -Path $PSScriptRoot -ChildPath 'DateiManager.log'

function Get-DefaultConfig {
    return [pscustomobject]@{
        # Keep existing fields for backward compatibility
        DefaultFolder      = (Get-Location).Path
        DefaultExtension   = 'txt'
        DefaultTarget      = ''
        DefaultBackupFolder= (Join-Path $PSScriptRoot 'Backup')
        DefaultZipPath     = (Join-Path $PSScriptRoot 'Archiv.zip')
        LogFile            = (Join-Path $PSScriptRoot 'DateiManager.log')
        Window             = @{ Width = 980; Height = 700 }
        
        # Add fields from config.json format (README)
        SourceFolder       = ''
        TargetFolder       = ''
        ZipBackup          = $false
    }
}

function Get-Configuration {
    try {
        $mainConfig = $null
        $legacyConfig = $null
        
        # Try to load the main config.json (README format)
        $mainConfigPath = Join-Path $PSScriptRoot 'config.json'
        if (Test-Path -LiteralPath $mainConfigPath) {
            try {
                $mainConfig = Get-Content -Raw -LiteralPath $mainConfigPath | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Log "Error reading config.json: $($_.Exception.Message)" 'WARN'
            }
        }
        
        # Try to load the legacy datei-manager-config.json
        if (Test-Path -LiteralPath $Script:ConfigPath) {
            try {
                $legacyConfig = Get-Content -Raw -LiteralPath $Script:ConfigPath | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Log "Error reading datei-manager-config.json: $($_.Exception.Message)" 'WARN'
            }
        }
        
        # Merge configurations, prioritizing main config.json
        $cfg = Get-DefaultConfig
        
        # Apply legacy config first
        if ($legacyConfig) {
            if ($legacyConfig.DefaultFolder) { $cfg.DefaultFolder = $legacyConfig.DefaultFolder }
            if ($legacyConfig.DefaultExtension) { $cfg.DefaultExtension = $legacyConfig.DefaultExtension }
            if ($legacyConfig.DefaultTarget) { $cfg.DefaultTarget = $legacyConfig.DefaultTarget }
            if ($legacyConfig.DefaultBackupFolder) { $cfg.DefaultBackupFolder = $legacyConfig.DefaultBackupFolder }
            if ($legacyConfig.DefaultZipPath) { $cfg.DefaultZipPath = $legacyConfig.DefaultZipPath }
            if ($legacyConfig.LogFile) { $cfg.LogFile = $legacyConfig.LogFile }
            if ($legacyConfig.Window) { $cfg.Window = $legacyConfig.Window }
        }
        
        # Apply main config.json, mapping fields appropriately
        if ($mainConfig) {
            if ($mainConfig.PSObject.Properties['SourceFolder'] -and $mainConfig.SourceFolder -and $mainConfig.SourceFolder.Trim()) { 
                $cfg.DefaultFolder = $mainConfig.SourceFolder
                $cfg.SourceFolder = $mainConfig.SourceFolder 
            }
            if ($mainConfig.PSObject.Properties['TargetFolder'] -and $mainConfig.TargetFolder -and $mainConfig.TargetFolder.Trim()) { 
                $cfg.DefaultTarget = $mainConfig.TargetFolder
                $cfg.TargetFolder = $mainConfig.TargetFolder
                $cfg.DefaultBackupFolder = $mainConfig.TargetFolder 
            }
            if ($mainConfig.PSObject.Properties['ZipBackup'] -and $null -ne $mainConfig.ZipBackup) { 
                $cfg.ZipBackup = [bool]$mainConfig.ZipBackup 
            }
            if ($mainConfig.PSObject.Properties['LogFile'] -and $mainConfig.LogFile -and $mainConfig.LogFile.Trim()) { 
                try {
                    $cfg.LogFile = Resolve-ConfigPath -Path $mainConfig.LogFile.Trim()
                } catch {
                    Write-Log "Error resolving LogFile path '$($mainConfig.LogFile)': $($_.Exception.Message)" 'WARN'
                }
            }
        }
        
        return $cfg
    } catch {
        Write-Log "Error in Get-Configuration: $($_.Exception.Message)" 'ERROR'
        return Get-DefaultConfig
    }
}

function Set-Configuration([object]$cfg) {
    try {
        # Save to legacy format for backward compatibility
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $Script:ConfigPath
        
        # Also save/update the main config.json in README format
        $mainConfigPath = Join-Path $PSScriptRoot 'config.json'
        $mainConfig = @{
            SourceFolder = if ($cfg.SourceFolder) { $cfg.SourceFolder } else { $cfg.DefaultFolder }
            TargetFolder = if ($cfg.TargetFolder) { $cfg.TargetFolder } else { $cfg.DefaultTarget }
            ZipBackup = if ($null -ne $cfg.ZipBackup) { $cfg.ZipBackup } else { $false }
            LogFile = if ($cfg.LogFile) { 
                # Make relative path for portability
                $relativePath = [System.IO.Path]::GetRelativePath($PSScriptRoot, $cfg.LogFile)
                if ($relativePath.StartsWith('..')) { $cfg.LogFile } else { "./$relativePath" }
            } else { "./DateiManager.log" }
        }
        $mainConfig | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $mainConfigPath
        Write-Log "Configuration saved to both config.json and datei-manager-config.json"
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
        # Fallback – still avoid throwing from logger
        Write-Host "LOGFEHLER: $Message" -ForegroundColor Yellow
    }
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        [void][System.IO.Directory]::CreateDirectory($full)
    } catch {
        throw
    }
}

function Resolve-ConfigPath {
    param([Parameter(Mandatory)][string]$Path)
    
    # Handle empty or whitespace-only paths
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path cannot be empty or whitespace"
    }
    
    $Path = $Path.Trim()
    
    # Already absolute
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    # Handle relative paths starting with ./
    if ($Path -match '^[.][\\/]') {
        $parent = Split-Path -Path $PSScriptRoot -Parent
        $trimmed = $Path -replace '^[.][\\/]', ''
        return (Join-Path $parent $trimmed)
    }
    # Otherwise relative to the script folder
    return (Join-Path $PSScriptRoot $Path)
}

function Get-NextVersionedPath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        # Suffix pattern: date + "_v" + version (e.g., _24-08-2025_v1)
        [string]$VersionFormat = '_{DATE}_v{0}'
    )

    $directory = Split-Path -Path $BasePath -Parent
    $filename  = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
    $extension = [System.IO.Path]::GetExtension($BasePath)

    # If the original path doesn't exist, return it unchanged
    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $BasePath
    }

    # Build requested date pattern, then sanitize for file-system safety
    $now = Get-Date
    $vf  = $VersionFormat
    # Build requested date pattern, then sanitize for file-system safety
    $now = Get-Date
    $vf  = $VersionFormat
    # New token - replace {DATE} with actual date (fix regex pattern)
    $vf  = $vf -replace '{DATE}', $now.ToString('dd-MM-yyyy')
    # Backward compatibility with previous tokens - but only if they haven't been replaced yet
    if ($vf -notmatch '\d{2}-\d{2}-\d{4}') {
        $vf  = $vf -replace 'DD',   $now.ToString('dd')
        $vf  = $vf -replace 'MM',   $now.ToString('MM')
        $vf  = $vf -replace 'YEAR', $now.ToString('yyyy')
    }

    $version = 1
    do {
        $suffixRaw  = $vf -f $version
        $suffixSafe = $suffixRaw -replace '[\\\/:*?"<>|]', '-'  # sanitize invalid filename chars
        $versionedName = "$filename$suffixSafe$extension"
        $versionedPath = if ([string]::IsNullOrWhiteSpace($directory)) { $versionedName } else { Join-Path $directory $versionedName }
        $version++
    } while (Test-Path -LiteralPath $versionedPath)

    Write-Log "Created versioned path: $versionedPath (version $($version-1))"
    return $versionedPath
}

# Sicherstellen: GUI in STA – erforderlich für Dialoge
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    try {
        if ($PSCommandPath -and $IsWindows) {
            Write-Log "Starte neu im STA-Modus über Windows PowerShell: $PSCommandPath"
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-File',"$PSCommandPath") | Out-Null
            return
        } elseif (-not $IsWindows) {
            Write-Log "Skipping STA mode restart on non-Windows platform" 'INFO'
        }
    } catch {
        Write-Log "Konnte nicht im STA-Modus neustarten: $($_.Exception.Message)" 'WARN'
    }
}

# Assemblies für WinForms laden
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName Microsoft.VisualBasic } catch { }

function Start-FileManagerGUI {
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Konfiguration laden
    $cfg = Get-Configuration
    if ($cfg.LogFile) {
        $lf = [string]$cfg.LogFile
        if ([string]::IsNullOrWhiteSpace($lf)) { $lf = 'DateiManager.log' }
        $Script:LogFile = Resolve-ConfigPath -Path $lf
    }
    New-DirectoryIfMissing (Split-Path -Path $Script:LogFile -Parent)

    # Form
    $form                = New-Object System.Windows.Forms.Form
    $form.Text           = 'Datei-Manager'
    $form.StartPosition  = 'CenterScreen'
    $form.Size           = New-Object System.Drawing.Size([int]$cfg.Window.Width,[int]$cfg.Window.Height)
    $form.MinimumSize    = New-Object System.Drawing.Size(940,620)

    # Controls – Suche
    $lblFolder = New-Object System.Windows.Forms.Label
    $lblFolder.Text = 'Ordner:'
    $lblFolder.AutoSize = $true
    $lblFolder.Location = New-Object System.Drawing.Point(12,15)

    $tbFolder = New-Object System.Windows.Forms.TextBox
    $tbFolder.Location = New-Object System.Drawing.Point(80,12)
    $tbFolder.Width = 720
    $tbFolder.Text = if ($cfg.DefaultFolder -and (Test-Path -LiteralPath $cfg.DefaultFolder)) { $cfg.DefaultFolder } else { (Get-Location).Path }

    $btnBrowseFolder = New-Object System.Windows.Forms.Button
    $btnBrowseFolder.Text = 'Durchsuchen…'
    $btnBrowseFolder.Location = New-Object System.Drawing.Point(810,10)
    $btnBrowseFolder.Width = 130

    $lblExt = New-Object System.Windows.Forms.Label
    $lblExt.Text = 'Erweiterung:'
    $lblExt.AutoSize = $true
    $lblExt.Location = New-Object System.Drawing.Point(12,48)

    $tbExt = New-Object System.Windows.Forms.TextBox
    $tbExt.Location = New-Object System.Drawing.Point(100,45)
    $tbExt.Width = 120
    $tbExt.Text = if ($cfg.DefaultExtension) { $cfg.DefaultExtension } else { 'txt' }

    $btnSearch = New-Object System.Windows.Forms.Button
    $btnSearch.Text = 'Suchen'
    $btnSearch.Location = New-Object System.Drawing.Point(240,43)
    $btnSearch.Width = 90

    # ListView – Ergebnisse
    $lvFiles = New-Object System.Windows.Forms.ListView
    $lvFiles.Location = New-Object System.Drawing.Point(12,80)
    $lvFiles.Size = New-Object System.Drawing.Size(930,380)
    $lvFiles.View = 'Details'
    $lvFiles.CheckBoxes = $true
    $lvFiles.FullRowSelect = $true
    $lvFiles.GridLines = $true

    [void]$lvFiles.Columns.Add('Name',250)
    [void]$lvFiles.Columns.Add('Ordner',350)
    [void]$lvFiles.Columns.Add('Größe',80)
    [void]$lvFiles.Columns.Add('Geändert',150)

    # Aktionen
    $gbActions = New-Object System.Windows.Forms.GroupBox
    $gbActions.Text = 'Aktionen – Schritte: 1) Dateien wählen  2) Ziel/ZIP/Backup setzen  3) Button drücken'
    $gbActions.Location = New-Object System.Drawing.Point(12,470)
    $gbActions.Size = New-Object System.Drawing.Size(930,150)

    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = 'Zielordner:'
    $lblTarget.AutoSize = $true
    $lblTarget.Location = New-Object System.Drawing.Point(12,25)

    $tbTarget = New-Object System.Windows.Forms.TextBox
    $tbTarget.Location = New-Object System.Drawing.Point(90,22)
    $tbTarget.Width = 640
    if ($cfg.DefaultTarget) { $tbTarget.Text = [string]$cfg.DefaultTarget }

    $btnBrowseTarget = New-Object System.Windows.Forms.Button
    $btnBrowseTarget.Text = '…'
    $btnBrowseTarget.Location = New-Object System.Drawing.Point(740,20)
    $btnBrowseTarget.Width = 30

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = 'Kopieren'
    $btnCopy.Location = New-Object System.Drawing.Point(780,20)
    $btnCopy.Width = 130

    $btnMove = New-Object System.Windows.Forms.Button
    $btnMove.Text = 'Verschieben'
    $btnMove.Location = New-Object System.Drawing.Point(780,55)
    $btnMove.Width = 130

    $btnRename = New-Object System.Windows.Forms.Button
    $btnRename.Text = 'Umbenennen'
    $btnRename.Location = New-Object System.Drawing.Point(780,90)
    $btnRename.Width = 130

    $lblZip = New-Object System.Windows.Forms.Label
    $lblZip.Text = 'ZIP-Datei:'
    $lblZip.AutoSize = $true
    $lblZip.Location = New-Object System.Drawing.Point(12,60)

    $tbZip = New-Object System.Windows.Forms.TextBox
    $tbZip.Location = New-Object System.Drawing.Point(90,57)
    $tbZip.Width = 640
    $tbZip.Text = if ($cfg.DefaultZipPath) { [string]$cfg.DefaultZipPath } else { (Join-Path $PSScriptRoot 'Archiv.zip') }

    $btnZipBrowse = New-Object System.Windows.Forms.Button
    $btnZipBrowse.Text = '…'
    $btnZipBrowse.Location = New-Object System.Drawing.Point(740,55)
    $btnZipBrowse.Width = 30

    $btnCreateZip = New-Object System.Windows.Forms.Button
    $btnCreateZip.Text = 'ZIP erstellen'
    $btnCreateZip.Location = New-Object System.Drawing.Point(470,120)
    $btnCreateZip.Width = 140

    $lblBackup = New-Object System.Windows.Forms.Label
    $lblBackup.Text = 'Backup-Ordner:'
    $lblBackup.AutoSize = $true
    $lblBackup.Location = New-Object System.Drawing.Point(12,95)

    $tbBackup = New-Object System.Windows.Forms.TextBox
    $tbBackup.Location = New-Object System.Drawing.Point(110,92)
    $tbBackup.Width = 620
    $tbBackup.Text = if ($cfg.DefaultBackupFolder) { [string]$cfg.DefaultBackupFolder } else { (Join-Path $PSScriptRoot 'Backup') }

    $btnBrowseBackup = New-Object System.Windows.Forms.Button
    $btnBrowseBackup.Text = '…'
    $btnBrowseBackup.Location = New-Object System.Drawing.Point(740,90)
    $btnBrowseBackup.Width = 30

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = 'Backup erstellen'
    $btnBackup.Location = New-Object System.Drawing.Point(12,120)
    $btnBackup.Width = 160

    $btnClearSel = New-Object System.Windows.Forms.Button
    $btnClearSel.Text = 'Auswahl aufheben'
    $btnClearSel.Location = New-Object System.Drawing.Point(180,120)
    $btnClearSel.Width = 150

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = 'Alle auswählen'
    $btnSelectAll.Location = New-Object System.Drawing.Point(340,120)
    $btnSelectAll.Width = 120

    # Statusleiste
    $status = New-Object System.Windows.Forms.StatusStrip
    $lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
    $lblStatus.Text = 'Bereit'
    [void]$status.Items.Add($lblStatus)

    # Helper: Item-Erzeugung
    function New-FileItem([IO.FileInfo]$fi) {
        $item = New-Object System.Windows.Forms.ListViewItem($fi.Name)
        [void]$item.SubItems.Add($fi.DirectoryName)
        [void]$item.SubItems.Add([Math]::Round($fi.Length/1KB,2).ToString() + ' KB')
        [void]$item.SubItems.Add($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        $item.Tag = $fi.FullName
        return $item
    }

    # Suche ausführen
    $doSearch = {
        $path = $tbFolder.Text.Trim()
        $ext  = $tbExt.Text.Trim().TrimStart('.')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            [System.Windows.Forms.MessageBox]::Show('Bitte gültigen Ordner wählen.','Hinweis') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '*' }
        $lblStatus.Text = 'Suche läuft…'
        $form.Cursor = 'WaitCursor'
        $lvFiles.Items.Clear()
        try {
            $files = Get-ChildItem -Path $path -Recurse -Filter "*.$ext" -File -ErrorAction Stop
            foreach ($f in $files) { [void]$lvFiles.Items.Add((New-FileItem $f)) }
            $lblStatus.Text = "Gefunden: $($files.Count) Datei(en)"
            Write-Log "Suche abgeschlossen: Pfad='$path' Ext='.$ext' Treffer=$($files.Count)"
        } catch {
            $lblStatus.Text = 'Fehler bei der Suche'
            Write-Log "Fehler bei Suche: $($_.Exception.Message)" 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("Fehler: $($_.Exception.Message)",'Fehler') | Out-Null
        } finally {
            $form.Cursor = 'Default'
        }
    }

    # Allgemeiner Auswahlsammler
    function Get-SelectedFilePaths {
        $sel = @()
        foreach ($it in $lvFiles.Items) { if ($it.Checked) { $sel += [string]$it.Tag } }
        if (-not $sel -and $lvFiles.SelectedItems.Count -gt 0) {
            foreach ($it in $lvFiles.SelectedItems) { $sel += [string]$it.Tag }
        }
        return $sel
    }

    # Aktionen
    $btnCopy.Add_Click({
        $paths = Get-SelectedFilePaths
        $dest  = $tbTarget.Text.Trim()
    if (-not $paths) { [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt.','Hinweis') | Out-Null; return }
        if ([string]::IsNullOrWhiteSpace($dest)) { [System.Windows.Forms.MessageBox]::Show('Zielordner angeben.','Hinweis') | Out-Null; return }
        $destFull = [System.IO.Path]::GetFullPath($dest)
        New-DirectoryIfMissing $destFull
        $ok = 0; $fail = 0
        foreach ($p in $paths) {
            try { Copy-Item -LiteralPath $p -Destination $destFull -Force; $ok++; Write-Log "Kopiert: $p -> $destFull" } catch { $fail++; Write-Log "Fehler Kopieren: $p -> $destFull :: $($_.Exception.Message)" 'ERROR' }
        }
        $lblStatus.Text = "Kopieren beendet – OK:$ok FEHLER:$fail"
    })

    $btnMove.Add_Click({
        $paths = Get-SelectedFilePaths
        $dest  = $tbTarget.Text.Trim()
        if (-not $paths) { [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt.','Hinweis') | Out-Null; return }
        if ([string]::IsNullOrWhiteSpace($dest)) { [System.Windows.Forms.MessageBox]::Show('Zielordner angeben.','Hinweis') | Out-Null; return }
        $destFull = [System.IO.Path]::GetFullPath($dest)
        New-DirectoryIfMissing $destFull
        $ok = 0; $fail = 0
        foreach ($p in $paths) {
            try { Move-Item -LiteralPath $p -Destination $destFull -Force; $ok++; Write-Log "Verschoben: $p -> $destFull" } catch { $fail++; Write-Log "Fehler Verschieben: $p -> $destFull :: $($_.Exception.Message)" 'ERROR' }
        }
        $lblStatus.Text = "Verschieben beendet – OK:$ok FEHLER:$fail"
    })

    $btnRename.Add_Click({
        $sel = $lvFiles.SelectedItems
        if ($sel.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Bitte eine Datei in der Liste markieren (nicht Checkbox).','Hinweis') | Out-Null; return }
        foreach ($it in $sel) {
            $full = [string]$it.Tag
            $dir  = Split-Path -Path $full -Parent
            $name = Split-Path -Path $full -Leaf
            $new  = $null
            try {
                $new = [Microsoft.VisualBasic.Interaction]::InputBox("Neuer Name für:`n$name",'Umbenennen',$name)
            } catch { }
            if ([string]::IsNullOrWhiteSpace($new) -or $new -eq $name) { continue }
            try {
                Rename-Item -LiteralPath $full -NewName $new -Force
                Write-Log "Umbenannt: $name -> $new in $dir"
                # UI aktualisieren
                $fi = Get-Item -LiteralPath (Join-Path $dir $new)
                $it.Text = $fi.Name
                $it.SubItems[0].Text = $fi.Name
                $it.SubItems[1].Text = $fi.DirectoryName
                $it.SubItems[2].Text = ([Math]::Round($fi.Length/1KB,2).ToString() + ' KB')
                $it.SubItems[3].Text = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                $it.Tag = $fi.FullName
            } catch {
                Write-Log "Fehler Umbenennen: $full -> $new :: $($_.Exception.Message)" 'ERROR'
                [System.Windows.Forms.MessageBox]::Show("Fehler: $($_.Exception.Message)",'Fehler') | Out-Null
            }
        }
        $lblStatus.Text = 'Umbenennen abgeschlossen'
    })

    $btnCreateZip.Add_Click({
        $paths = Get-SelectedFilePaths
        if (-not $paths) { 
            [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt. Bitte markieren Sie Dateien mit den Checkboxen in der Liste.','ZIP-Erstellung - Hinweis') | Out-Null
            return 
        }
        $zipPath = $tbZip.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($zipPath)) { 
            [System.Windows.Forms.MessageBox]::Show('Bitte geben Sie einen Pfad für die ZIP-Datei an. Verwenden Sie den "..." Button zum Auswählen.','ZIP-Erstellung - Pfad erforderlich') | Out-Null
            return 
        }
        
        # Stelle sicher, dass Endung .zip vorhanden ist
        if ([System.IO.Path]::GetExtension($zipPath) -ne '.zip') { $zipPath = "$zipPath.zip" }
        $zipPath = [System.IO.Path]::GetFullPath($zipPath)
        
        $zipDir = Split-Path -Path $zipPath -Parent
        if (-not $zipDir) { $zipDir = $PSScriptRoot }
        New-DirectoryIfMissing $zipDir
        
        try {
            $lblStatus.Text = 'ZIP wird erstellt...'
            
            # Use versioning instead of overwriting
            $finalZipPath = Get-NextVersionedPath -BasePath $zipPath
            
            Compress-Archive -LiteralPath $paths -DestinationPath $finalZipPath -Force
            Write-Log "ZIP erstellt: $finalZipPath mit $($paths.Count) Dateien"
            $lblStatus.Text = "ZIP erfolgreich erstellt: $($paths.Count) Dateien"
            [System.Windows.Forms.MessageBox]::Show("ZIP-Datei erfolgreich erstellt:`n$finalZipPath`n`nAnzahl Dateien: $($paths.Count)", 'ZIP-Erstellung - Erfolgreich', 'OK', 'Information') | Out-Null
        } catch {
            $errorMsg = "Fehler bei ZIP-Erstellung: $($_.Exception.Message)"
            Write-Log $errorMsg 'ERROR'
            $lblStatus.Text = 'ZIP-Erstellung fehlgeschlagen'
            [System.Windows.Forms.MessageBox]::Show($errorMsg, 'ZIP-Erstellung - Fehler', 'OK', 'Error') | Out-Null
        }
    })

    $btnBackup.Add_Click({
        $paths = Get-SelectedFilePaths
    $dest  = $tbBackup.Text.Trim()
        if (-not $paths) { 
            [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt. Bitte markieren Sie Dateien mit den Checkboxen in der Liste.','Backup - Hinweis') | Out-Null
            return 
        }
        if ([string]::IsNullOrWhiteSpace($dest)) { 
            [System.Windows.Forms.MessageBox]::Show('Bitte geben Sie einen Backup-Ordner an. Verwenden Sie den "..." Button zum Auswählen.','Backup - Ordner erforderlich') | Out-Null
            return 
        }
        
        try {
            # Use versioning for backup folder
            $finalDestPath = Get-NextVersionedPath -BasePath $dest
            $destFull = [System.IO.Path]::GetFullPath($finalDestPath)
            New-DirectoryIfMissing $destFull
            
            $lblStatus.Text = 'Backup läuft...'
            $ok=0; $fail=0
            
            foreach ($p in $paths) {
                try { 
                    Copy-Item -LiteralPath $p -Destination $destFull -Force
                    $ok++
                    Write-Log "Backup: $p -> $destFull" 
                } catch { 
                    $fail++
                    Write-Log "Fehler Backup: $p -> $destFull :: $($_.Exception.Message)" 'ERROR' 
                }
            }
            
            $lblStatus.Text = "Backup abgeschlossen – $ok erfolgreich, $fail Fehler"
            
            if ($fail -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Backup erfolgreich abgeschlossen!`n`nDateien kopiert: $ok`nZiel: $finalDestPath", 'Backup - Erfolgreich', 'OK', 'Information') | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show("Backup abgeschlossen mit Fehlern.`n`nErfolgreich: $ok`nFehler: $fail`nZiel: $finalDestPath`n`nDetails im Log verfügbar.", 'Backup - Mit Fehlern', 'OK', 'Warning') | Out-Null
            }
        } catch {
            $errorMsg = "Fehler beim Backup: $($_.Exception.Message)"
            Write-Log $errorMsg 'ERROR'
            $lblStatus.Text = 'Backup fehlgeschlagen'
            [System.Windows.Forms.MessageBox]::Show($errorMsg, 'Backup - Fehler', 'OK', 'Error') | Out-Null
        }
    })

    $btnClearSel.Add_Click({ foreach ($it in $lvFiles.Items) { $it.Checked = $false }; $lvFiles.SelectedItems.Clear(); $lblStatus.Text = 'Auswahl aufgehoben' })
    $btnSelectAll.Add_Click({ foreach ($it in $lvFiles.Items) { $it.Checked = $true } ; $lblStatus.Text = 'Alle markiert' })

    # ZIP Pfad auswählen
    $btnZipBrowse.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Title = 'ZIP-Datei speichern'
        $sfd.Filter = 'ZIP-Archiv (*.zip)|*.zip|Alle Dateien (*.*)|*.*'
        $sfd.FileName = if ($tbZip.Text) { [System.IO.Path]::GetFileName($tbZip.Text) } else { 'Archiv.zip' }
        $sfd.InitialDirectory = if ($tbZip.Text) { (Split-Path -Path $tbZip.Text -Parent) } else { $PSScriptRoot }
        if ($sfd.ShowDialog() -eq 'OK') { $tbZip.Text = $sfd.FileName }
        $sfd.Dispose()
    })

    # Folder/Target/Backup Dialoge
    $btnBrowseFolder.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = if (Test-Path $tbFolder.Text) { $tbFolder.Text } else { (Get-Location).Path }
        if ($fbd.ShowDialog() -eq 'OK') { $tbFolder.Text = $fbd.SelectedPath }
        $fbd.Dispose()
    })
    $btnBrowseTarget.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = if (Test-Path $tbTarget.Text) { $tbTarget.Text } else { (Get-Location).Path }
        if ($fbd.ShowDialog() -eq 'OK') { $tbTarget.Text = $fbd.SelectedPath }
        $fbd.Dispose()
    })
    $btnBrowseBackup.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = if (Test-Path $tbBackup.Text) { $tbBackup.Text } else { (Get-Location).Path }
        if ($fbd.ShowDialog() -eq 'OK') { $tbBackup.Text = $fbd.SelectedPath }
        $fbd.Dispose()
    })
    $btnSearch.Add_Click($doSearch)

    # Enter im Erweiterungsfeld startet Suche
    $tbExt.Add_KeyDown({ param($s,$e) if ($e.KeyCode -eq 'Enter') { & $doSearch; $e.Handled = $true } })

    # Add controls to containers
    $form.Controls.AddRange(@($lblFolder,$tbFolder,$btnBrowseFolder,$lblExt,$tbExt,$btnSearch,$lvFiles,$gbActions,$status))
    $gbActions.Controls.AddRange(@(
        $lblTarget,$tbTarget,$btnBrowseTarget,$btnCopy,$btnMove,$btnRename,
        $lblZip,$tbZip,$btnZipBrowse,
        $lblBackup,$tbBackup,$btnBrowseBackup,$btnBackup,$btnClearSel,$btnSelectAll,$btnCreateZip
    ))

    # Tooltips
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.AutoPopDelay = 8000
    $toolTip.InitialDelay = 500
    $toolTip.ReshowDelay  = 200
    $toolTip.ShowAlways   = $true
    $toolTip.SetToolTip($tbExt,'Dateierweiterung ohne Punkt (z.B. txt, jpg). Leer lassen für alle Dateien.')
    $toolTip.SetToolTip($btnSearch,'1) Ordner wählen, 2) Erweiterung eingeben, 3) Suchen klicken')
    $toolTip.SetToolTip($lvFiles,'Aktivieren Sie die Checkboxen für Dateien, die verarbeitet werden sollen.')
    $toolTip.SetToolTip($tbTarget,'Zielordner für Kopieren/Verschieben')
    $toolTip.SetToolTip($btnCopy,'Ausgewählte Dateien in Zielordner kopieren')
    $toolTip.SetToolTip($btnMove,'Ausgewählte Dateien in Zielordner verschieben')
    $toolTip.SetToolTip($btnRename,'Markierte Datei in der Liste umbenennen (eine oder mehrere)')
    $toolTip.SetToolTip($tbZip,'Pfad zur zu erstellenden ZIP-Datei')
    $toolTip.SetToolTip($btnZipBrowse,'Speicherort/Dateinamen der ZIP-Datei wählen')
    $toolTip.SetToolTip($btnCreateZip,'Ausgewählte Dateien zu ZIP-Archiv zusammenfassen')
    $toolTip.SetToolTip($tbBackup,'Ordner, in den die Sicherungskopien erstellt werden')
    $toolTip.SetToolTip($btnBackup,'Ausgewählte Dateien in den Backup-Ordner kopieren')
    $toolTip.SetToolTip($btnClearSel,'Alle Häkchen entfernen')
    $toolTip.SetToolTip($btnSelectAll,'Alle Dateien anhaken')

    # Startstatus
    Write-Log 'GUI gestartet'
    # Beim Schließen die aktuellen Werte zurück in die Konfiguration schreiben
    $form.Add_FormClosing({
        $save = [pscustomobject]@{
            DefaultFolder       = $tbFolder.Text
            DefaultExtension    = ($tbExt.Text.Trim().TrimStart('.'))
            DefaultTarget       = $tbTarget.Text
            DefaultBackupFolder = $tbBackup.Text
            DefaultZipPath      = $tbZip.Text
            LogFile             = $Script:LogFile
            Window              = @{ Width = $form.Width; Height = $form.Height }
            # Add fields for config.json compatibility
            SourceFolder        = $tbFolder.Text
            TargetFolder        = $tbTarget.Text
            ZipBackup           = $false  # This could be enhanced to track ZIP preference
        }
        Set-Configuration $save
        Write-Log 'Konfiguration gespeichert'
    })
    [System.Windows.Forms.Application]::Run($form)
    Write-Log 'GUI beendet'
}

# Starte GUI
Start-FileManagerGUI
