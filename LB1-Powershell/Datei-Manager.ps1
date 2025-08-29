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

# Logdatei im Skriptordner
$Script:LogFile = Join-Path -Path $PSScriptRoot -ChildPath 'FileManager.log'

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
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

# Sicherstellen: GUI in STA – erforderlich für Dialoge
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    try {
        if ($PSCommandPath) {
            Write-Log "Starte neu im STA-Modus über Windows PowerShell: $PSCommandPath"
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-File',"$PSCommandPath") | Out-Null
            return
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

    # Form
    $form                = New-Object System.Windows.Forms.Form
    $form.Text           = 'Datei-Manager'
    $form.StartPosition  = 'CenterScreen'
    $form.Size           = New-Object System.Drawing.Size(980,700)
    $form.MinimumSize    = New-Object System.Drawing.Size(940,620)

    # Controls – Suche
    $lblFolder = New-Object System.Windows.Forms.Label
    $lblFolder.Text = 'Ordner:'
    $lblFolder.AutoSize = $true
    $lblFolder.Location = New-Object System.Drawing.Point(12,15)

    $tbFolder = New-Object System.Windows.Forms.TextBox
    $tbFolder.Location = New-Object System.Drawing.Point(80,12)
    $tbFolder.Width = 720
    $tbFolder.Text = (Get-Location).Path

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
    $tbExt.Text = 'txt'

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
    $gbActions.Text = 'Aktionen'
    $gbActions.Location = New-Object System.Drawing.Point(12,470)
    $gbActions.Size = New-Object System.Drawing.Size(930,150)

    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = 'Zielordner:'
    $lblTarget.AutoSize = $true
    $lblTarget.Location = New-Object System.Drawing.Point(12,25)

    $tbTarget = New-Object System.Windows.Forms.TextBox
    $tbTarget.Location = New-Object System.Drawing.Point(90,22)
    $tbTarget.Width = 640

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
    $tbZip.Text = (Join-Path $PSScriptRoot 'Archiv.zip')

    $btnZip = New-Object System.Windows.Forms.Button
    $btnZip.Text = 'ZIP erstellen'
    $btnZip.Location = New-Object System.Drawing.Point(740,55)
    $btnZip.Width = 30

    $lblBackup = New-Object System.Windows.Forms.Label
    $lblBackup.Text = 'Backup-Ordner:'
    $lblBackup.AutoSize = $true
    $lblBackup.Location = New-Object System.Drawing.Point(12,95)

    $tbBackup = New-Object System.Windows.Forms.TextBox
    $tbBackup.Location = New-Object System.Drawing.Point(110,92)
    $tbBackup.Width = 620
    $tbBackup.Text = (Join-Path $PSScriptRoot 'Backup')

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
    New-DirectoryIfMissing $dest
        $ok = 0; $fail = 0
        foreach ($p in $paths) {
            try { Copy-Item -LiteralPath $p -Destination $dest -Force; $ok++; Write-Log "Kopiert: $p -> $dest" } catch { $fail++; Write-Log "Fehler Kopieren: $p -> $dest :: $($_.Exception.Message)" 'ERROR' }
        }
        $lblStatus.Text = "Kopieren beendet – OK:$ok FEHLER:$fail"
    })

    $btnMove.Add_Click({
        $paths = Get-SelectedFilePaths
        $dest  = $tbTarget.Text.Trim()
        if (-not $paths) { [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt.','Hinweis') | Out-Null; return }
        if ([string]::IsNullOrWhiteSpace($dest)) { [System.Windows.Forms.MessageBox]::Show('Zielordner angeben.','Hinweis') | Out-Null; return }
    New-DirectoryIfMissing $dest
        $ok = 0; $fail = 0
        foreach ($p in $paths) {
            try { Move-Item -LiteralPath $p -Destination $dest -Force; $ok++; Write-Log "Verschoben: $p -> $dest" } catch { $fail++; Write-Log "Fehler Verschieben: $p -> $dest :: $($_.Exception.Message)" 'ERROR' }
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

    $btnZip.Add_Click({
        $paths = Get-SelectedFilePaths
        if (-not $paths) { [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt.','Hinweis') | Out-Null; return }
        $zipPath = $tbZip.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($zipPath)) { [System.Windows.Forms.MessageBox]::Show('Bitte Pfad für ZIP-Datei angeben.','Hinweis') | Out-Null; return }
        $zipDir = Split-Path -Path $zipPath -Parent
        if (-not $zipDir) { $zipDir = $PSScriptRoot }
        New-DirectoryIfMissing $zipDir
        try {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            Compress-Archive -Path $paths -DestinationPath $zipPath -Force
            Write-Log "ZIP erstellt: $zipPath mit $($paths.Count) Dateien"
            $lblStatus.Text = 'ZIP erstellt'
        } catch {
            Write-Log "Fehler ZIP: $($_.Exception.Message)" 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("Fehler: $($_.Exception.Message)",'Fehler') | Out-Null
        }
    })

    $btnBackup.Add_Click({
        $paths = Get-SelectedFilePaths
        $dest  = $tbBackup.Text.Trim()
        if (-not $paths) { [System.Windows.Forms.MessageBox]::Show('Keine Dateien ausgewählt.','Hinweis') | Out-Null; return }
    if ([string]::IsNullOrWhiteSpace($dest)) { [System.Windows.Forms.MessageBox]::Show('Backup-Ordner angeben.','Hinweis') | Out-Null; return }
    New-DirectoryIfMissing $dest
        $ok=0; $fail=0
        foreach ($p in $paths) {
            try { Copy-Item -LiteralPath $p -Destination $dest -Force; $ok++; Write-Log "Backup: $p -> $dest" } catch { $fail++; Write-Log "Fehler Backup: $p -> $dest :: $($_.Exception.Message)" 'ERROR' }
        }
        $lblStatus.Text = "Backup beendet – OK:$ok FEHLER:$fail"
    })

    $btnClearSel.Add_Click({ foreach ($it in $lvFiles.Items) { $it.Checked = $false }; $lvFiles.SelectedItems.Clear(); $lblStatus.Text = 'Auswahl aufgehoben' })

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
        $lblZip,$tbZip,$btnZip,
        $lblBackup,$tbBackup,$btnBrowseBackup,$btnBackup,$btnClearSel
    ))

    # Startstatus
    Write-Log 'GUI gestartet'
    [System.Windows.Forms.Application]::Run($form)
    Write-Log 'GUI beendet'
}

# Starte GUI
Start-FileManagerGUI
