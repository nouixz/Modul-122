<#
Einfacher Datei-Manager mit GUI
Unterstützt: Suchen, Kopieren, Verschieben, Umbenennen, ZIP, Backup
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic

$logPath    = Join-Path $PSScriptRoot 'DateiManager.log'
$configPath = Join-Path $PSScriptRoot 'config.json'

function Write-Log([string]$msg) {
    $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $logPath -Value "$time $msg"
}

function Get-Config {
    if (Test-Path $configPath) {
        try { return Get-Content -Raw $configPath | ConvertFrom-Json } catch {}
    }
    [pscustomobject]@{
        SourceFolder = (Get-Location).Path
        TargetFolder = (Get-Location).Path
        BackupFolder = (Get-Location).Path
        ZipPath      = (Join-Path $PSScriptRoot 'Archiv.zip')
        Width        = 900
        Height       = 600
    }
}
function Set-Config($cfg) { $cfg | ConvertTo-Json | Set-Content -LiteralPath $configPath }

$cfg = Get-Config


# Modern look and feel
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Datei-Manager'
$form.Width = $cfg.Width
$form.Height = $cfg.Height
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$form.MinimumSize = '800,500'


$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = 'Ordner:'
$lblFolder.Location = '20,18'
$lblFolder.AutoSize = $true
$lblFolder.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)


$tbFolder = New-Object System.Windows.Forms.TextBox
$tbFolder.Text = $cfg.SourceFolder
$tbFolder.Location = '90,15'
$tbFolder.Width = 500
$tbFolder.Anchor = 'Top,Left,Right'
$tbFolder.BackColor = [System.Drawing.Color]::White



$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '...'
$btnBrowse.Location = '600,13'
$btnBrowse.Width = 35
$btnBrowse.Anchor = 'Top,Right'
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(220, 230, 241)


$lblExt = New-Object System.Windows.Forms.Label
$lblExt.Text = 'Endung:'
$lblExt.Location = '650,18'
$lblExt.AutoSize = $true
$lblExt.Anchor = 'Top,Right'
$lblExt.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)


$tbExt = New-Object System.Windows.Forms.TextBox
$tbExt.Location = '720,15'
$tbExt.Width = 70
$tbExt.Anchor = 'Top,Right'
$tbExt.BackColor = [System.Drawing.Color]::White


$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = 'Suchen'
$btnSearch.Location = '800,13'
$btnSearch.Width = 80
$btnSearch.Anchor = 'Top,Right'
$btnSearch.FlatStyle = 'Flat'
$btnSearch.BackColor = [System.Drawing.Color]::FromArgb(220, 241, 220)


$lvFiles = New-Object System.Windows.Forms.ListView
$lvFiles.Location = '10,50'
$lvFiles.Width = 860
$lvFiles.Height = 370
$lvFiles.View = 'Details'
$lvFiles.CheckBoxes = $true
$lvFiles.FullRowSelect = $true
$lvFiles.GridLines = $true
$lvFiles.Columns.Add('Datei',400) | Out-Null
$lvFiles.Columns.Add('Ordner',440) | Out-Null
$lvFiles.Anchor = 'Top,Bottom,Left,Right'


$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = 'Ziel:'
$lblTarget.Location = '10,430'
$lblTarget.AutoSize = $true
$lblTarget.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)


$tbTarget = New-Object System.Windows.Forms.TextBox
$tbTarget.Text = $cfg.TargetFolder
$tbTarget.Location = '70,427'
$tbTarget.Width = 400
$tbTarget.Anchor = 'Bottom,Left,Right'
$tbTarget.BackColor = [System.Drawing.Color]::White


$btnTarget = New-Object System.Windows.Forms.Button
$btnTarget.Text = '...'
$btnTarget.Location = '480,425'
$btnTarget.Width = 35
$btnTarget.Anchor = 'Bottom,Right'
$btnTarget.FlatStyle = 'Flat'
$btnTarget.BackColor = [System.Drawing.Color]::FromArgb(220, 230, 241)


$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'Kopieren'
$btnCopy.Location = '520,425'
$btnCopy.Width = 90
$btnCopy.Anchor = 'Bottom,Right'
$btnCopy.FlatStyle = 'Flat'
$btnCopy.BackColor = [System.Drawing.Color]::FromArgb(220, 241, 220)


$btnMove = New-Object System.Windows.Forms.Button
$btnMove.Text = 'Verschieben'
$btnMove.Location = '620,425'
$btnMove.Width = 110
$btnMove.Anchor = 'Bottom,Right'
$btnMove.FlatStyle = 'Flat'
$btnMove.BackColor = [System.Drawing.Color]::FromArgb(241, 241, 220)


$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Text = 'Umbenennen'
$btnRename.Location = '740,425'
$btnRename.Width = 110
$btnRename.Anchor = 'Bottom,Right'
$btnRename.FlatStyle = 'Flat'
$btnRename.BackColor = [System.Drawing.Color]::FromArgb(220, 241, 241)


$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = 'Loeschen'
$btnSelectAll.Text = 'Alle'
$btnClear.Text = 'Keine'
$lblFolder.Text = 'Ordner:'
$lblExt.Text = 'Endung:'
$lblTarget.Text = 'Ziel:'
$lvFiles.Columns.Add('Datei',400) | Out-Null
$lvFiles.Columns.Add('Ordner',440) | Out-Null
$lblStatus.Text = "$($lvFiles.Items.Count) Dateien gefunden"
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungueltig'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewaehlt'; return }
$lblStatus.Text = 'Kopieren fertig'
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungueltig'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewaehlt'; return }
$lblStatus.Text = 'Verschieben fertig'
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewaehlt'; return }
$lblStatus.Text = 'Loeschen fertig'
    if (-not $paths) { $lblStatus.Text = 'Keine Datei ausgewaehlt'; return }
$lblStatus.Text = 'ZIP fertig'
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewaehlt'; return }
$lblStatus.Text = 'Backup fertig'
    if (-not (Test-Path $folder)) { $lblStatus.Text = 'Ordner nicht gefunden'; return }
$btnDelete.Location = '860,425'
$btnDelete.Width = 90
$btnDelete.Anchor = 'Bottom,Right'
$btnDelete.FlatStyle = 'Flat'
$btnDelete.BackColor = [System.Drawing.Color]::FromArgb(241, 220, 220)


$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = 'Alle'
$btnSelectAll.Location = '10,470'
$btnSelectAll.Anchor = 'Bottom,Left'
$btnSelectAll.FlatStyle = 'Flat'


$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = 'Keine'
$btnClear.Location = '80,470'
$btnClear.Anchor = 'Bottom,Left'
$btnClear.FlatStyle = 'Flat'


$btnZip = New-Object System.Windows.Forms.Button
$btnZip.Text = 'ZIP'
$btnZip.Location = '150,470'
$btnZip.Anchor = 'Bottom,Left'
$btnZip.FlatStyle = 'Flat'


$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = 'Backup'
$btnBackup.Location = '220,470'
$btnBackup.Anchor = 'Bottom,Left'
$btnBackup.FlatStyle = 'Flat'


# Status bar and progress bar
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Height = 30
$statusPanel.Dock = 'Bottom'
$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = '10,7'
$lblStatus.Anchor = 'Left'
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Width = 200
$progressBar.Height = 18
$progressBar.Location = '700,6'
$progressBar.Anchor = 'Right'
$progressBar.Style = 'Continuous'
$progressBar.Visible = $false

$statusPanel.Controls.Add($lblStatus)
$statusPanel.Controls.Add($progressBar)


$form.Controls.AddRange(@(
    $lblFolder,$tbFolder,$btnBrowse,$lblExt,$tbExt,$btnSearch,$lvFiles,
    $lblTarget,$tbTarget,$btnTarget,$btnCopy,$btnMove,$btnRename,
    $btnDelete,$btnSelectAll,$btnClear,$btnZip,$btnBackup,$statusPanel))

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq 'OK') { $tbFolder.Text = $fbd.SelectedPath }
})
$btnTarget.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq 'OK') { $tbTarget.Text = $fbd.SelectedPath }
})



# Dynamic file list refresh function (use approved verb: Get-FileList)
function Get-FileList {
    $lvFiles.Items.Clear()
    $folder = $tbFolder.Text
    if (-not (Test-Path $folder)) { $lblStatus.Text = 'Ordner nicht gefunden'; return }
    $ext = $tbExt.Text.Trim().TrimStart('.')
    $pattern = if ($ext) { "*.$ext" } else { '*' }
    Get-ChildItem -LiteralPath $folder -Filter $pattern -File | ForEach-Object {
        $item = New-Object System.Windows.Forms.ListViewItem($_.Name)
        $item.SubItems.Add($_.DirectoryName) | Out-Null
        $item.Tag = $_.FullName
        $lvFiles.Items.Add($item) | Out-Null
    }
    $lblStatus.Text = "$($lvFiles.Items.Count) Dateien gefunden"
}

$btnSearch.Add_Click({ Get-FileList })
$tbFolder.Add_TextChanged({ Get-FileList })
$tbExt.Add_TextChanged({ Get-FileList })

function Get-SelectedPaths {
    $lvFiles.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }
}

$btnSelectAll.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $true } })
$btnClear.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $false } })


$btnCopy.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungültig'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    $progressBar.Visible = $true
    $progressBar.Maximum = $sel.Count
    $progressBar.Value = 0
    foreach ($p in $sel) {
        try { Copy-Item -LiteralPath $p -Destination $dest -Force; Write-Log "COPY $p -> $dest" } catch { Write-Log "ERROR copy $p : $($_.Exception.Message)" }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $lblStatus.Text = 'Kopieren fertig'
    Get-FileList
})


$btnMove.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungültig'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    $progressBar.Visible = $true
    $progressBar.Maximum = $sel.Count
    $progressBar.Value = 0
    foreach ($p in $sel) {
        try { Move-Item -LiteralPath $p -Destination $dest -Force; Write-Log "MOVE $p -> $dest" } catch { Write-Log "ERROR move $p : $($_.Exception.Message)" }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $lblStatus.Text = 'Verschieben fertig'
    Get-FileList
})


$btnRename.Add_Click({
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    foreach ($p in $sel) {
        $name = [System.IO.Path]::GetFileName($p)
        $enteredName = [Microsoft.VisualBasic.Interaction]::InputBox('Neuer Name:', 'Umbenennen', $name)
        if ($enteredName -and $enteredName -ne $name) {
            $newPath = Join-Path ([System.IO.Path]::GetDirectoryName($p)) $enteredName
            try { Rename-Item -LiteralPath $p -NewName $enteredName; Write-Log "RENAME $p -> $newPath" } catch { Write-Log "ERROR rename $p : $($_.Exception.Message)" }
        }
    }
    Get-FileList
})


$btnDelete.Add_Click({
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    $progressBar.Visible = $true
    $progressBar.Maximum = $sel.Count
    $progressBar.Value = 0
    foreach ($p in $sel) {
        try { Remove-Item -LiteralPath $p -Force; Write-Log "DELETE $p" } catch { Write-Log "ERROR delete $p : $($_.Exception.Message)" }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $lblStatus.Text = 'Löschen fertig'
    Get-FileList
})


$btnZip.Add_Click({
    $paths = @(Get-SelectedPaths)
    if (-not $paths) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'ZIP files (*.zip)|*.zip'
    $sfd.FileName = [IO.Path]::GetFileName($cfg.ZipPath)
    if ($sfd.ShowDialog() -ne 'OK') { return }
    $zip = $sfd.FileName
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
    $zipStream = [System.IO.File]::Open($zip,[System.IO.FileMode]::CreateNew)
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream,[System.IO.Compression.ZipArchiveMode]::Create)
    $progressBar.Visible = $true
    $progressBar.Maximum = $paths.Count
    $progressBar.Value = 0
    foreach ($p in $paths) {
        $entry = $archive.CreateEntry([IO.Path]::GetFileName($p))
        $entryStream = $entry.Open()
        $fileStream = [System.IO.File]::OpenRead($p)
        $fileStream.CopyTo($entryStream)
        $fileStream.Dispose(); $entryStream.Dispose()
        $progressBar.Value++
    }
    $archive.Dispose(); $zipStream.Dispose()
    $progressBar.Visible = $false
    Write-Log "ZIP -> $zip"
    $lblStatus.Text = 'ZIP fertig'
})


$btnBackup.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $cfg.BackupFolder
    if ($fbd.ShowDialog() -ne 'OK') { return }
    $dest = $fbd.SelectedPath
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { $lblStatus.Text = 'Keine Datei ausgewählt'; return }
    $progressBar.Visible = $true
    $progressBar.Maximum = $sel.Count
    $progressBar.Value = 0
    foreach ($p in $sel) {
        try { Copy-Item -LiteralPath $p -Destination $dest -Force; Write-Log "BACKUP $p -> $dest" } catch { Write-Log "ERROR backup $p : $($_.Exception.Message)" }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $cfg.BackupFolder = $dest
    $lblStatus.Text = 'Backup fertig'
})

$form.Add_FormClosing({
    $cfg.SourceFolder = $tbFolder.Text
    $cfg.TargetFolder = $tbTarget.Text
    $cfg.ZipPath     = $cfg.ZipPath
    $cfg.Width       = $form.Width
    $cfg.Height      = $form.Height
    Set-Config $cfg
})


# Initial file list load
Get-FileList

[System.Windows.Forms.Application]::Run($form)
