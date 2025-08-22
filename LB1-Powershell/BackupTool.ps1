# PowerShell Backup Tool - GUI Only (English, folder selector for backup, optional zip)

# Config file path
$configDir = Join-Path $env:LOCALAPPDATA "BackupTool"
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }
$configPath = Join-Path $configDir "config.json"

function Get-Config {
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw
        $obj = $raw | ConvertFrom-Json
        return [PSCustomObject]@{
            SourceFolder = if ($obj -and $obj.SourceFolder) { $obj.SourceFolder } else { "" }
            TargetFolder = if ($obj -and $obj.TargetFolder) { $obj.TargetFolder } else { "" }
            LogFile      = if ($obj -and $obj.LogFile)      { $obj.LogFile }      else { (Join-Path $configDir "backup.log") }
            Exclude      = if ($obj -and $obj.Exclude)      { $obj.Exclude }      else { @(".tmp", ".log") }
            ZipBackup    = if ($obj -and $obj.ZipBackup)    { $obj.ZipBackup }    else { $false }
        }
    } else {
        $default = [PSCustomObject]@{
            SourceFolder = ""
            TargetFolder = ""
            LogFile      = (Join-Path $configDir "backup.log")
            Exclude      = @(".tmp", ".log")
            ZipBackup    = $false
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
    $zip = $false
    if ($config.ZipBackup) { $zip = [bool]$config.ZipBackup }

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

    # If zip option chosen, create timestamped zip of the source folder into the destination
    if ($zip) {
        try {
            $srcFull = (Resolve-Path $src).ProviderPath
            $sourceName = Split-Path $srcFull -Leaf
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $zipName = "$($sourceName)_backup_$timestamp.zip"
            $zipPath = Join-Path $dst $zipName

            # ensure any existing zip is overwritten
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

            [System.IO.Compression.ZipFile]::CreateFromDirectory($srcFull, $zipPath)
            Write-Log "Zipped: $srcFull -> $zipPath" $log
            Write-Log "Backup (zip) completed from '$src' to '$zipPath'." $log
            return "Backup completed. ZIP created: $zipPath"
        } catch {
            Write-Log "Error creating zip: $_" $log
            return "Error creating zip: $($_.Exception.Message)"
        }
    }

    # Resolve full source path and ensure trailing slash for substring calculations
    $srcFull = (Resolve-Path $src).ProviderPath
    if (-not $srcFull.EndsWith('\')) { $srcFull += '\' }

    $files = Get-ChildItem -Path $srcFull -Recurse -File | Where-Object {
        $ext = $_.Extension
        -not ($exclude -contains $ext)
    }

    foreach ($file in $files) {
        $rel = $file.FullName.Substring($srcFull.Length).TrimStart('\','/')
        $target = Join-Path $dst $rel
        $targetDir = Split-Path $target
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -Path $file.FullName -Destination $target -Force
        Write-Log "Copied: $($file.FullName) -> $target" $log
    }

    Write-Log "Backup completed from '$src' to '$dst'." $log
    return "Backup completed. Folder saved to: $dst"
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

# Row 3: Zip option
$lblZip = New-Object Windows.Forms.Label
$lblZip.Text = "Create ZIP:"
$lblZip.TextAlign = "MiddleLeft"
$lblZip.Dock = 'Fill'
$table.Controls.Add($lblZip, 0, 3)

$chkZip = New-Object Windows.Forms.CheckBox
$chkZip.Dock = 'Left'
$chkZip.Checked = [bool]$config.ZipBackup
$chkZip.Text = "Create a timestamped .zip in destination"
$chkZip.AutoSize = $true
$table.Controls.Add($chkZip, 1, 3)
# leave column 3 empty for alignment

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
        SourceFolder = $txtSource.Text
        TargetFolder = $txtTarget.Text
        LogFile      = (Join-Path $configDir "backup.log")
        Exclude      = $config.Exclude
        ZipBackup    = $chkZip.Checked
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

[void]$form.ShowDialog()