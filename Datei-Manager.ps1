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

function Load-Config {
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
function Save-Config($cfg) { $cfg | ConvertTo-Json | Set-Content -LiteralPath $configPath }

$cfg = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Datei-Manager'
$form.Width = $cfg.Width
$form.Height = $cfg.Height
$form.StartPosition = 'CenterScreen'

$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = 'Ordner:'
$lblFolder.Location = '10,15'
$lblFolder.AutoSize = $true

$tbFolder = New-Object System.Windows.Forms.TextBox
$tbFolder.Text = $cfg.SourceFolder
$tbFolder.Location = '70,12'
$tbFolder.Width = 500

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '...'
$btnBrowse.Location = '580,10'
$btnBrowse.Width = 30

$lblExt = New-Object System.Windows.Forms.Label
$lblExt.Text = 'Endung:'
$lblExt.Location = '620,15'
$lblExt.AutoSize = $true

$tbExt = New-Object System.Windows.Forms.TextBox
$tbExt.Location = '680,12'
$tbExt.Width = 80

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = 'Suchen'
$btnSearch.Location = '770,10'

$lvFiles = New-Object System.Windows.Forms.ListView
$lvFiles.Location = '10,40'
$lvFiles.Width = 860
$lvFiles.Height = 400
$lvFiles.View = 'Details'
$lvFiles.CheckBoxes = $true
$lvFiles.FullRowSelect = $true
$lvFiles.Columns.Add('Datei',400) | Out-Null
$lvFiles.Columns.Add('Ordner',440) | Out-Null

$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = 'Ziel:'
$lblTarget.Location = '10,450'
$lblTarget.AutoSize = $true

$tbTarget = New-Object System.Windows.Forms.TextBox
$tbTarget.Text = $cfg.TargetFolder
$tbTarget.Location = '70,447'
$tbTarget.Width = 400

$btnTarget = New-Object System.Windows.Forms.Button
$btnTarget.Text = '...'
$btnTarget.Location = '480,445'
$btnTarget.Width = 30

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'Kopieren'
$btnCopy.Location = '520,445'

$btnMove = New-Object System.Windows.Forms.Button
$btnMove.Text = 'Verschieben'
$btnMove.Location = '600,445'

$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Text = 'Umbenennen'
$btnRename.Location = '700,445'

$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = 'Alle'
$btnSelectAll.Location = '10,480'

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = 'Keine'
$btnClear.Location = '80,480'

$btnZip = New-Object System.Windows.Forms.Button
$btnZip.Text = 'ZIP'
$btnZip.Location = '150,480'

$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = 'Backup'
$btnBackup.Location = '220,480'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = '10,520'

$form.Controls.AddRange(@(
    $lblFolder,$tbFolder,$btnBrowse,$lblExt,$tbExt,$btnSearch,$lvFiles,
    $lblTarget,$tbTarget,$btnTarget,$btnCopy,$btnMove,$btnRename,
    $btnSelectAll,$btnClear,$btnZip,$btnBackup,$lblStatus))

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq 'OK') { $tbFolder.Text = $fbd.SelectedPath }
})
$btnTarget.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq 'OK') { $tbTarget.Text = $fbd.SelectedPath }
})

$btnSearch.Add_Click({
    $lvFiles.Items.Clear()
    $folder = $tbFolder.Text
    if (-not (Test-Path $folder)) { $lblStatus.Text = 'Ordner nicht gefunden'; return }
    $ext = $tbExt.Text.Trim().TrimStart('.')
    $pattern = $ext ? "*.$ext" : '*'
    Get-ChildItem -LiteralPath $folder -Filter $pattern -File | ForEach-Object {
        $item = New-Object System.Windows.Forms.ListViewItem($_.Name)
        $item.SubItems.Add($_.DirectoryName) | Out-Null
        $item.Tag = $_.FullName
        $lvFiles.Items.Add($item) | Out-Null
    }
    $lblStatus.Text = "$($lvFiles.Items.Count) Dateien gefunden"
})

function Get-SelectedPaths {
    $lvFiles.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }
}

$btnSelectAll.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $true } })
$btnClear.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $false } })

$btnCopy.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungültig'; return }
    foreach ($p in Get-SelectedPaths) {
        try { Copy-Item -LiteralPath $p -Destination $dest -Force; Write-Log "COPY $p -> $dest" } catch { Write-Log "ERROR copy $p : $($_.Exception.Message)" }
    }
    $lblStatus.Text = 'Kopieren fertig'
})

$btnMove.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path $dest)) { $lblStatus.Text = 'Ziel ungültig'; return }
    foreach ($p in Get-SelectedPaths) {
        try { Move-Item -LiteralPath $p -Destination $dest -Force; Write-Log "MOVE $p -> $dest" } catch { Write-Log "ERROR move $p : $($_.Exception.Message)" }
    }
    $btnSearch.PerformClick()
    $lblStatus.Text = 'Verschieben fertig'
})

$btnRename.Add_Click({
    foreach ($p in Get-SelectedPaths) {
        $name = [System.IO.Path]::GetFileName($p)
        $input = [Microsoft.VisualBasic.Interaction]::InputBox('Neuer Name:', 'Umbenennen', $name)
        if ($input -and $input -ne $name) {
            $newPath = Join-Path ([System.IO.Path]::GetDirectoryName($p)) $input
            try { Rename-Item -LiteralPath $p -NewName $input; Write-Log "RENAME $p -> $newPath" } catch { Write-Log "ERROR rename $p : $($_.Exception.Message)" }
        }
    }
    $btnSearch.PerformClick()
})

$btnZip.Add_Click({
    $paths = Get-SelectedPaths
    if (-not $paths) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'ZIP files (*.zip)|*.zip'
    $sfd.FileName = [IO.Path]::GetFileName($cfg.ZipPath)
    if ($sfd.ShowDialog() -ne 'OK') { return }
    $zip = $sfd.FileName
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
    $zipStream = [System.IO.File]::Open($zip,[System.IO.FileMode]::CreateNew)
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream,[System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($p in $paths) {
        $entry = $archive.CreateEntry([IO.Path]::GetFileName($p))
        $entryStream = $entry.Open()
        $fileStream = [System.IO.File]::OpenRead($p)
        $fileStream.CopyTo($entryStream)
        $fileStream.Dispose(); $entryStream.Dispose()
    }
    $archive.Dispose(); $zipStream.Dispose()
    Write-Log "ZIP -> $zip"
})

$btnBackup.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $cfg.BackupFolder
    if ($fbd.ShowDialog() -ne 'OK') { return }
    $dest = $fbd.SelectedPath
    foreach ($p in Get-SelectedPaths) {
        try { Copy-Item -LiteralPath $p -Destination $dest -Force; Write-Log "BACKUP $p -> $dest" } catch { Write-Log "ERROR backup $p : $($_.Exception.Message)" }
    }
    $cfg.BackupFolder = $dest
    $lblStatus.Text = 'Backup fertig'
})

$form.Add_FormClosing({
    $cfg.SourceFolder = $tbFolder.Text
    $cfg.TargetFolder = $tbTarget.Text
    $cfg.ZipPath     = $cfg.ZipPath
    $cfg.Width       = $form.Width
    $cfg.Height      = $form.Height
    Save-Config $cfg
})

[System.Windows.Forms.Application]::Run($form)
