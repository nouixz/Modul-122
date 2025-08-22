# PowerShell Backup Tool - GUI Only (English, folder selector for backup, optional zip)

# Config file path
$configDir = Join-Path $env:LOCALAPPDATA "BackupTool"
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }
$configPath = Join-Path $configDir "config.json"

# Backup history path
$historyPath = Join-Path $configDir "backups.json"

function Get-BackupHistory {
    if (Test-Path $historyPath) {
        try { (Get-Content $historyPath -Raw | ConvertFrom-Json) } catch { @() }
    } else { @() }
}

function Save-BackupHistory($list) {
    ($list | ConvertTo-Json -Depth 5) | Set-Content $historyPath
}

function Add-BackupHistoryEntry([pscustomobject]$entry) {
    $hist = @(Get-BackupHistory)
    $hist += $entry
    Save-BackupHistory $hist
}

function Remove-BackupHistoryEntry([string]$outputPath) {
    $hist = @(Get-BackupHistory)
    $newHist = $hist | Where-Object { $_.Path -ne $outputPath }
    Save-BackupHistory $newHist
}

function Get-Config {
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw
        $obj = $raw | ConvertFrom-Json
        return [PSCustomObject]@{
            SourceFolder     = if ($obj -and $obj.SourceFolder) { $obj.SourceFolder } else { "" }
            TargetFolder     = if ($obj -and $obj.TargetFolder) { $obj.TargetFolder } else { "" }
            LogFile          = if ($obj -and $obj.LogFile)      { $obj.LogFile }      else { (Join-Path $configDir "backup.log") }
            Exclude          = if ($obj -and $obj.Exclude)      { $obj.Exclude }      else { @(".tmp", ".log") }
            ZipBackup        = if ($obj -and $obj.ZipBackup)    { $obj.ZipBackup }    else { $false }
            DeletePrevSame   = if ($obj -and ($obj.PSObject.Properties.Name -contains 'DeletePrevSame')) { [bool]$obj.DeletePrevSame } else { $false }
        }
    } else {
        $default = [PSCustomObject]@{
            SourceFolder   = ""
            TargetFolder   = ""
            LogFile        = (Join-Path $configDir "backup.log")
            Exclude        = @(".tmp", ".log")
            ZipBackup      = $false
            DeletePrevSame = $false
        }
        $default | ConvertTo-Json | Set-Content $configPath
        return $default
    }
}

function Save-Config($config) {
    $config | ConvertTo-Json | Set-Content $configPath
}

function Write-Log($message, $logFile) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $message" | Add-Content $logFile
}

function Start-Backup($config) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $src = $config.SourceFolder
    $dst = $config.TargetFolder
    $log = $config.LogFile
    $exclude = @()
    if ($config.Exclude) { $exclude = $config.Exclude }
    $zip = [bool]$config.ZipBackup
    $deletePrevSame = [bool]($config.PSObject.Properties.Name -contains 'DeletePrevSame' -and $config.DeletePrevSame)

    if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($dst)) {
        return "Source folder and target folder must not be empty."
    }
    if (-not (Test-Path $src)) {
        Write-Log "Source folder '$src' does not exist." $log
        return "Source folder does not exist."
    }
    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }

    $srcFull = (Resolve-Path $src).ProviderPath
    $sourceName = Split-Path $srcFull -Leaf
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $outputPath = $null
    $type = $null

    if ($zip) {
        try {
            $zipName = "$($sourceName)_backup_$timestamp.zip"
            $zipPath = Join-Path $dst $zipName
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($srcFull, $zipPath)
            $outputPath = $zipPath
            $type = "Zip"
            Write-Log "Zipped: $srcFull -> $zipPath" $log
        } catch {
            Write-Log "Error creating zip: $_" $log
            return "Error creating zip: $($_.Exception.Message)"
        }
    } else {
        # Create a versioned folder so past backups are discrete and can be deleted
        $versionFolder = "$($sourceName)_backup_$timestamp"
        $targetRoot = Join-Path $dst $versionFolder
        try {
            if (-not (Test-Path $targetRoot)) { New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null }
            # Ensure trailing slash for substring calculations
            $srcNorm = $srcFull; if (-not $srcNorm.EndsWith('\')) { $srcNorm += '\' }
            $files = Get-ChildItem -Path $srcNorm -Recurse -File | Where-Object {
                $ext = $_.Extension
                -not ($exclude -contains $ext)
            }
            foreach ($file in $files) {
                $rel = $file.FullName.Substring($srcNorm.Length).TrimStart('\','/')
                $target = Join-Path $targetRoot $rel
                $targetDir = Split-Path $target
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                Copy-Item -Path $file.FullName -Destination $target -Force
                Write-Log "Copied: $($file.FullName) -> $target" $log
            }
            $outputPath = $targetRoot
            $type = "Folder"
        } catch {
            Write-Log "Error copying files: $_" $log
            return "Error copying files: $($_.Exception.Message)"
        }
    }

    # Record history
    try {
        $sizeBytes = 0
        if ($type -eq "Zip" -and (Test-Path $outputPath)) {
            $sizeBytes = (Get-Item -LiteralPath $outputPath).Length
        } elseif ($type -eq "Folder" -and (Test-Path $outputPath)) {
            $sizeBytes = (Get-ChildItem -LiteralPath $outputPath -Recurse -File | Measure-Object -Sum Length).Sum
        }

        # avoid ?: - make a safe int64 value
        $sizeInt64 = if ($null -ne $sizeBytes) { [int64]$sizeBytes } else { 0L }

        $entry = [pscustomobject]@{
            Timestamp   = (Get-Date).ToString("s")
            Source      = $srcFull
            Destination = $dst
            Type        = $type
            Path        = $outputPath
            SizeBytes   = $sizeInt64
        }
        Add-BackupHistoryEntry $entry
    } catch {
        Write-Log "Failed to write backup history: $($_.Exception.Message)" $log
    }

    # Optionally delete the previous backup with same source+destination
    if ($deletePrevSame) {
        try {
            $hist = @(Get-BackupHistory)
            $prev = $hist |
                Where-Object { $_.Source -eq $srcFull -and $_.Destination -eq $dst -and $_.Path -ne $outputPath } |
                Sort-Object Timestamp -Descending |
                Select-Object -First 1
            if ($prev) {
                if (Test-Path $prev.Path) {
                    if ($prev.Type -eq "Zip") {
                        Remove-Item -LiteralPath $prev.Path -Force
                    } else {
                        Remove-Item -LiteralPath $prev.Path -Recurse -Force
                    }
                    Write-Log "Deleted previous backup: $($prev.Path)" $log
                }
                Remove-BackupHistoryEntry -outputPath $prev.Path
            }
        } catch {
            Write-Log "Failed to delete previous backup: $($_.Exception.Message)" $log
        }
    }

    if ($type -eq "Zip") {
        Write-Log "Backup (zip) completed from '$src' to '$outputPath'." $log
        return "Backup completed. ZIP created: $outputPath"
    } else {
        Write-Log "Backup completed from '$src' to '$outputPath'." $log
        return "Backup completed. Folder saved to: $outputPath"
    }
}

# --- Modernized and Organized GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$config = Get-Config

$form = New-Object Windows.Forms.Form
$form.Text = "PowerShell Backup Tool"
$form.Size = New-Object Drawing.Size(1000, 640)
$form.MinimumSize = New-Object Drawing.Size(900, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.BackColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 11)

# Use a TableLayoutPanel so controls stay visible and aligned
$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = 'Fill'
$table.Padding = '12,12,12,12'
$table.AutoSize = $false
$table.ColumnCount = 3
# increased row count to accommodate zip checkbox
$table.RowCount = 7
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,160)))
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,120)))
for ($i = 0; $i -lt $table.RowCount; $i++) {
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,50)))
}
$form.Controls.Add($table)

# Title (spans all columns)
$lblTitle = New-Object Windows.Forms.Label
$lblTitle.Text = "PowerShell Backup Tool"
$lblTitle.Font = New-Object Drawing.Font("Segoe UI", 18, [Drawing.FontStyle]::Bold)
$lblTitle.TextAlign = "MiddleCenter"
$lblTitle.Dock = 'Fill'
$table.Controls.Add($lblTitle, 0, 0)
$table.SetColumnSpan($lblTitle, 3)

# Row 1: Source folder (folder picker)
$lblSource = New-Object Windows.Forms.Label
$lblSource.Text = "Folder to backup:"
$lblSource.TextAlign = "MiddleLeft"
$lblSource.Dock = 'Fill'
$table.Controls.Add($lblSource, 0, 1)

$txtSource = New-Object Windows.Forms.TextBox
$txtSource.Dock = 'Fill'
$txtSource.Text = $config.SourceFolder
$table.Controls.Add($txtSource, 1, 1)

$btnBrowseSource = New-Object Windows.Forms.Button
$btnBrowseSource.Text = "Select Folder"
$btnBrowseSource.Dock = 'Fill'
$btnBrowseSource.BackColor = [Drawing.Color]::FromArgb(220,230,250)
$btnBrowseSource.FlatStyle = 'Flat'
$btnBrowseSource.Add_Click({
    $fbd = New-Object Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select folder to backup"
    if ($txtSource.Text -and (Test-Path $txtSource.Text)) { $fbd.SelectedPath = $txtSource.Text }
    if ($fbd.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $txtSource.Text = $fbd.SelectedPath }
})
$table.Controls.Add($btnBrowseSource, 2, 1)

# Row 2: Target folder
$lblTarget = New-Object Windows.Forms.Label
$lblTarget.Text = "Backup destination:"
$lblTarget.TextAlign = "MiddleLeft"
$lblTarget.Dock = 'Fill'
$table.Controls.Add($lblTarget, 0, 2)

$txtTarget = New-Object Windows.Forms.TextBox
$txtTarget.Dock = 'Fill'
$txtTarget.Text = $config.TargetFolder
$table.Controls.Add($txtTarget, 1, 2)

$btnBrowseTarget = New-Object Windows.Forms.Button
$btnBrowseTarget.Text = "Select Folder"
$btnBrowseTarget.Dock = 'Fill'
$btnBrowseTarget.BackColor = [Drawing.Color]::FromArgb(220,230,250)
$btnBrowseTarget.FlatStyle = 'Flat'
$btnBrowseTarget.Add_Click({
    $fbd = New-Object Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select backup destination folder"
    if ($txtTarget.Text -and (Test-Path $txtTarget.Text)) { $fbd.SelectedPath = $txtTarget.Text }
    if ($fbd.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $txtTarget.Text = $fbd.SelectedPath }
})
$table.Controls.Add($btnBrowseTarget, 2, 2)

# Row 3: Options (ZIP + Delete previous same)
$lblZip = New-Object Windows.Forms.Label
$lblZip.Text = "Options:"
$lblZip.TextAlign = "MiddleLeft"
$lblZip.Dock = 'Fill'
$table.Controls.Add($lblZip, 0, 3)

$optPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$optPanel.Dock = 'Fill'
$optPanel.FlowDirection = 'LeftToRight'
$optPanel.WrapContents = $false

$chkZip = New-Object Windows.Forms.CheckBox
$chkZip.Text = "Create a timestamped .zip in destination"
$chkZip.AutoSize = $true
$chkZip.Checked = [bool]$config.ZipBackup
$optPanel.Controls.Add($chkZip)

$chkDeletePrev = New-Object Windows.Forms.CheckBox
$chkDeletePrev.Text = "Delete previous backup with same source & destination"
$chkDeletePrev.AutoSize = $true
$chkDeletePrev.Margin = '18,3,3,3'
$chkDeletePrev.Checked = [bool]($config.PSObject.Properties.Name -contains 'DeletePrevSame' -and $config.DeletePrevSame)
$optPanel.Controls.Add($chkDeletePrev)

$table.Controls.Add($optPanel, 1, 3)

# Row 4: Info (spans all columns)
$lblInfo = New-Object Windows.Forms.Label
$lblInfo.Text = "Select a folder to backup and a destination folder. All files/subfolders will be copied (excluded extensions can be set in config). If 'Create ZIP' is checked the source folder will be zipped into the destination instead of copying files individually."
$lblInfo.TextAlign = "MiddleLeft"
$lblInfo.Dock = 'Fill'
$lblInfo.ForeColor = [Drawing.Color]::FromArgb(100,100,120)
$table.Controls.Add($lblInfo, 0, 4)
$table.SetColumnSpan($lblInfo, 3)

# Row 5: Spacer
$spacer = New-Object Windows.Forms.Label
$spacer.Text = ""
$table.Controls.Add($spacer, 0, 5)
$table.SetColumnSpan($spacer, 3)

# Row 6: Buttons (Run, View Log, Exit)
$btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$btnPanel.Dock = 'Fill'
$btnPanel.FlowDirection = 'LeftToRight'
$btnPanel.WrapContents = $false
$btnPanel.Padding = '0,6,0,0'
$btnPanel.AutoSize = $false

$btnBackup = New-Object Windows.Forms.Button
$btnBackup.Text = "Run Backup"
$btnBackup.Size = New-Object Drawing.Size(160,42)
$btnBackup.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$btnBackup.BackColor = [Drawing.Color]::FromArgb(180,230,180)
$btnBackup.FlatStyle = 'Flat'
$btnBackup.Add_Click({
    $newConfig = [PSCustomObject]@{
        SourceFolder   = $txtSource.Text
        TargetFolder   = $txtTarget.Text
        LogFile        = (Join-Path $configDir "backup.log")
        Exclude        = $config.Exclude
        ZipBackup      = $chkZip.Checked
        DeletePrevSame = $chkDeletePrev.Checked
    }
    Save-Config $newConfig

    if ([string]::IsNullOrWhiteSpace($newConfig.SourceFolder) -or [string]::IsNullOrWhiteSpace($newConfig.TargetFolder)) {
        [Windows.Forms.MessageBox]::Show("Please select a source folder and a destination folder.")
        return
    }

    $result = Start-Backup $newConfig
    [Windows.Forms.MessageBox]::Show($result)

    # keep in-memory config in sync
    $script:config = $newConfig
})
$btnPanel.Controls.Add($btnBackup)

$btnViewLog = New-Object Windows.Forms.Button
$btnViewLog.Text = "View Log"
$btnViewLog.Size = New-Object Drawing.Size(140,42)
$btnViewLog.Font = New-Object Drawing.Font("Segoe UI", 11)
$btnViewLog.BackColor = [Drawing.Color]::FromArgb(200,210,240)
$btnViewLog.FlatStyle = 'Flat'
$btnViewLog.Add_Click({
    $logFile = (Join-Path $configDir "backup.log")
    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile -Raw
        $logForm = New-Object Windows.Forms.Form
        $logForm.Text = "Backup Log"
        $logForm.Size = New-Object Drawing.Size(800,420)
        $txtLogView = New-Object Windows.Forms.TextBox
        $txtLogView.Multiline = $true
        $txtLogView.ScrollBars = "Vertical"
        $txtLogView.ReadOnly = $true
        $txtLogView.Dock = "Fill"
        $txtLogView.Text = $logContent
        $logForm.Controls.Add($txtLogView)
        $logForm.ShowDialog()
    } else {
        [Windows.Forms.MessageBox]::Show("Log file not found.")
    }
})
$btnPanel.Controls.Add($btnViewLog)

# New: Manage Backups button
$btnManage = New-Object Windows.Forms.Button
$btnManage.Text = "Manage Backups"
$btnManage.Size = New-Object Drawing.Size(160,42)
$btnManage.Font = New-Object Drawing.Font("Segoe UI", 11)
$btnManage.BackColor = [Drawing.Color]::FromArgb(210,230,210)
$btnManage.FlatStyle = 'Flat'
$btnManage.Add_Click({ Open-BackupManager })   # renamed to an approved verb
$btnPanel.Controls.Add($btnManage)

$btnExit = New-Object Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Size = New-Object Drawing.Size(140,42)
$btnExit.Font = New-Object Drawing.Font("Segoe UI", 11)
$btnExit.BackColor = [Drawing.Color]::FromArgb(240,200,200)
$btnExit.FlatStyle = 'Flat'
$btnExit.Add_Click({ $form.Close() })
$btnPanel.Controls.Add($btnExit)

$table.Controls.Add($btnPanel, 0, 6)
$table.SetColumnSpan($btnPanel, 3)

function Open-BackupManager {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = "Backup Manager"
    $dlg.Size = New-Object Drawing.Size(900, 520)
    $dlg.StartPosition = "CenterParent"

    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.MultiSelect = $true
    $lv.Dock = 'Top'
    $lv.Height = 400
    [void]$lv.Columns.Add("Date", 140)
    [void]$lv.Columns.Add("Type", 70)
    [void]$lv.Columns.Add("Size (MB)", 90, [System.Windows.Forms.HorizontalAlignment]::Right)
    [void]$lv.Columns.Add("Path", 260)
    [void]$lv.Columns.Add("Source", 160)
    [void]$lv.Columns.Add("Destination", 160)

    $btnPanel = New-Object Windows.Forms.FlowLayoutPanel
    $btnPanel.Dock = 'Bottom'
    $btnPanel.Height = 60
    $btnPanel.FlowDirection = 'LeftToRight'
    $btnPanel.WrapContents = $false
    $btnPanel.Padding = '8,8,8,8'

    $btnRefresh = New-Object Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Width = 120
    $btnRefresh.Add_Click({ Update-BackupListView -ListView $lv })
    $btnPanel.Controls.Add($btnRefresh)

    $btnOpen = New-Object Windows.Forms.Button
    $btnOpen.Text = "Open Location"
    $btnOpen.Width = 140
    $btnOpen.Add_Click({
        if ($lv.SelectedItems.Count -gt 0) {
            $path = $lv.SelectedItems[0].Tag.Path
            if (Test-Path $path) {
                if ((Get-Item $path) -is [System.IO.FileInfo]) {
                    Start-Process explorer.exe "/select,`"$path`""
                } else {
                    Start-Process explorer.exe "`"$path`""
                }
            } else {
                [Windows.Forms.MessageBox]::Show("Path not found: $path")
            }
        }
    })
    $btnPanel.Controls.Add($btnOpen)

    $btnDelete = New-Object Windows.Forms.Button
    $btnDelete.Text = "Delete Selected"
    $btnDelete.Width = 140
    $btnDelete.BackColor = [Drawing.Color]::FromArgb(240,200,200)
    $btnDelete.FlatStyle = 'Flat'
    $btnDelete.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) { return }
        $res = [Windows.Forms.MessageBox]::Show("Delete selected backup(s)?", "Confirm", [Windows.Forms.MessageBoxButtons]::YesNo)
        if ($res -ne [Windows.Forms.DialogResult]::Yes) { return }
        foreach ($sel in @($lv.SelectedItems)) {
            $e = $sel.Tag
            try {
                if (Test-Path $e.Path) {
                    if ($e.Type -eq "Zip") {
                        Remove-Item -LiteralPath $e.Path -Force
                    } else {
                        Remove-Item -LiteralPath $e.Path -Recurse -Force
                    }
                }
                Remove-BackupHistoryEntry -outputPath $e.Path
                $lv.Items.Remove($sel)
            } catch {
                [Windows.Forms.MessageBox]::Show("Failed to delete: $($e.Path)`r`n$($_.Exception.Message)")
            }
        }
    })
    $btnPanel.Controls.Add($btnDelete)

    $btnClose = New-Object Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 120
    $btnClose.Add_Click({ $dlg.Close() })
    $btnPanel.Controls.Add($btnClose)

    $dlg.Controls.Add($lv)
    $dlg.Controls.Add($btnPanel)

    Update-BackupListView -ListView $lv
    [void]$dlg.ShowDialog($form)
}

function Update-BackupListView {
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.ListView] $ListView
    )
    $ListView.Items.Clear()
    $history = @(Get-BackupHistory)

    foreach ($e in $history) {
        $sizeMB = 0
        if ($e.PSObject.Properties.Name -contains 'SizeBytes' -and $e.SizeBytes) {
            $sizeMB = [math]::Round(($e.SizeBytes/1MB), 2)
        }

        $subitems = @(
            [string]$e.Timestamp,
            [string]$e.Type,
            ("{0:0.##}" -f $sizeMB),
            [string]$e.Path,
            [string]$e.Source,
            [string]$e.Destination
        )

        # Pass a single string[] so the correct ctor is selected
        $item = New-Object Windows.Forms.ListViewItem -ArgumentList (,$subitems)
        $item.Tag = $e
        [void]$ListView.Items.Add($item)
    }
}

[void]$form.ShowDialog()