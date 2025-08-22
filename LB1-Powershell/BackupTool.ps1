# PowerShell Backup Tool - GUI Only

# Config file path
$configDir = Join-Path $env:LOCALAPPDATA "BackupTool"
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }
$configPath = Join-Path $configDir "config.json"

function Get-Config {
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    } else {
        $default = @{
            SourcePath = ""
            TargetPath = ""
            LogFile = (Join-Path $configDir "backup.log")
            Exclude = @(".tmp", ".log")
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
    $src = $config.SourcePath
    $dst = $config.TargetPath
    $log = $config.LogFile
    $exclude = $config.Exclude

    if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($dst)) {
        return "Source and Target paths must not be empty."
    }
    if (-not (Test-Path $src)) {
        Write-Log "Source path '$src' does not exist." $log
        return "Source path does not exist."
    }
    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    $files = Get-ChildItem -Path $src -Recurse -File | Where-Object {
        $ext = $_.Extension
        -not ($exclude -contains $ext)
    }
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($src.Length)
        if ($rel.StartsWith('\') -or $rel.StartsWith('/')) {
            $rel = $rel.Substring(1)
        }
        $target = Join-Path $dst $rel
        $targetDir = Split-Path $target
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item $file.FullName $target -Force
        Write-Log "Copied: $($file.FullName) -> $target" $log
    }
    Write-Log "Backup completed." $log
    return "Backup completed."
}

# --- Modernized and Organized GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$config = Get-Config

$form = New-Object Windows.Forms.Form
$form.Text = "PowerShell Backup Tool"
$form.Size = New-Object Drawing.Size(600, 320)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(245,245,245)

$font = New-Object Drawing.Font("Segoe UI", 10)
$form.Font = $font

$lblTitle = New-Object Windows.Forms.Label
$lblTitle.Text = "Backup Tool"
$lblTitle.Font = New-Object Drawing.Font("Segoe UI", 16, [Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [Drawing.Color]::FromArgb(60,60,60)
$lblTitle.AutoSize = $false
$lblTitle.TextAlign = "MiddleCenter"
$lblTitle.Dock = "Top"
$lblTitle.Height = 40
$form.Controls.Add($lblTitle)

$panel = New-Object Windows.Forms.Panel
$panel.Dock = "Fill"
$panel.Padding = '10,10,10,10'
$panel.BackColor = [Drawing.Color]::FromArgb(235,235,235)
$form.Controls.Add($panel)

# Source selector
$lblSource = New-Object Windows.Forms.Label
$lblSource.Text = "Quelle (zu sichernder Ordner):"
$lblSource.Location = '10,10'
$lblSource.Size = '200,25'
$panel.Controls.Add($lblSource)

$txtSource = New-Object Windows.Forms.TextBox
$txtSource.Location = '220,10'
$txtSource.Size = '250,25'
$txtSource.Text = $config.SourcePath
$panel.Controls.Add($txtSource)

$btnBrowseSource = New-Object Windows.Forms.Button
$btnBrowseSource.Text = "Ordner wählen"
$btnBrowseSource.Location = '480,10'
$btnBrowseSource.Size = '90,25'
$btnBrowseSource.Add_Click({
    $fbd = New-Object Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Quellordner auswählen"
    if ($txtSource.Text -and (Test-Path $txtSource.Text)) {
        $fbd.SelectedPath = $txtSource.Text
    }
    if ($fbd.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $fbd.SelectedPath
    }
})
$panel.Controls.Add($btnBrowseSource)

$lblSourceInfo = New-Object Windows.Forms.Label
$lblSourceInfo.Text = "Alle Dateien und Unterordner aus diesem Ordner werden gesichert (außer ausgeschlossene Dateitypen)."
$lblSourceInfo.Location = '220,35'
$lblSourceInfo.Size = '350,20'
$lblSourceInfo.ForeColor = [Drawing.Color]::FromArgb(100,100,100)
$panel.Controls.Add($lblSourceInfo)

# Target selector
$lblTarget = New-Object Windows.Forms.Label
$lblTarget.Text = "Ziel (Backup-Ordner):"
$lblTarget.Location = '10,70'
$lblTarget.Size = '200,25'
$panel.Controls.Add($lblTarget)

$txtTarget = New-Object Windows.Forms.TextBox
$txtTarget.Location = '220,70'
$txtTarget.Size = '250,25'
$txtTarget.Text = $config.TargetPath
$panel.Controls.Add($txtTarget)

$btnBrowseTarget = New-Object Windows.Forms.Button
$btnBrowseTarget.Text = "Ordner wählen"
$btnBrowseTarget.Location = '480,70'
$btnBrowseTarget.Size = '90,25'
$btnBrowseTarget.Add_Click({
    $fbd = New-Object Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Zielordner auswählen"
    if ($txtTarget.Text -and (Test-Path $txtTarget.Text)) {
        $fbd.SelectedPath = $txtTarget.Text
    }
    if ($fbd.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $txtTarget.Text = $fbd.SelectedPath
    }
})
$panel.Controls.Add($btnBrowseTarget)

$lblTargetInfo = New-Object Windows.Forms.Label
$lblTargetInfo.Text = "Backups werden in diesem Zielordner gespeichert."
$lblTargetInfo.Location = '220,95'
$lblTargetInfo.Size = '350,20'
$lblTargetInfo.ForeColor = [Drawing.Color]::FromArgb(100,100,100)
$panel.Controls.Add($lblTargetInfo)

$lblExclude = New-Object Windows.Forms.Label
$lblExclude.Text = "Exclude Extensions (comma separated):"
$lblExclude.Location = '10,130'
$lblExclude.Size = '250,25'
$panel.Controls.Add($lblExclude)

$txtExclude = New-Object Windows.Forms.TextBox
$txtExclude.Location = '10,160'
$txtExclude.Size = '560,25'
$txtExclude.Text = ($config.Exclude -join ", ")
$panel.Controls.Add($txtExclude)

$btnSave = New-Object Windows.Forms.Button
$btnSave.Text = "Save Config"
$btnSave.Location = '10,200'
$btnSave.Size = '120,35'
$btnSave.BackColor = [Drawing.Color]::FromArgb(220,220,220)
$btnSave.Add_Click({
    $config.SourcePath = $txtSource.Text
    $config.TargetPath = $txtTarget.Text
    $config.LogFile = (Join-Path $configDir "backup.log")
    $config.Exclude = $txtExclude.Text -split ',' | ForEach-Object { $_.Trim() }
    Save-Config $config
    [Windows.Forms.MessageBox]::Show("Config saved.")
})
$panel.Controls.Add($btnSave)

$btnBackup = New-Object Windows.Forms.Button
$btnBackup.Text = "Run Backup"
$btnBackup.Location = '140,200'
$btnBackup.Size = '120,35'
$btnBackup.BackColor = [Drawing.Color]::FromArgb(200,220,200)
$btnBackup.Add_Click({
    $config.SourcePath = $txtSource.Text
    $config.TargetPath = $txtTarget.Text
    $config.LogFile = (Join-Path $configDir "backup.log")
    $config.Exclude = $txtExclude.Text -split ',' | ForEach-Object { $_.Trim() }
    Save-Config $config
    if ([string]::IsNullOrWhiteSpace($config.SourcePath) -or [string]::IsNullOrWhiteSpace($config.TargetPath)) {
        [Windows.Forms.MessageBox]::Show("Source and Target paths must not be empty.")
    } else {
        $result = Start-Backup $config
        [Windows.Forms.MessageBox]::Show($result)
    }
})
$panel.Controls.Add($btnBackup)

$btnViewLog = New-Object Windows.Forms.Button
$btnViewLog.Text = "View Log"
$btnViewLog.Location = '270,200'
$btnViewLog.Size = '120,35'
$btnViewLog.BackColor = [Drawing.Color]::FromArgb(220,220,240)
$btnViewLog.Add_Click({
    $logFile = (Join-Path $configDir "backup.log")
    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile -Raw
        $logForm = New-Object Windows.Forms.Form
        $logForm.Text = "Backup Log"
        $logForm.Size = '500,400'
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
$panel.Controls.Add($btnViewLog)

$btnExit = New-Object Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Location = '410,200'
$btnExit.Size = '120,35'
$btnExit.BackColor = [Drawing.Color]::FromArgb(240,200,200)
$btnExit.Add_Click({ $form.Close() })
$panel.Controls.Add($btnExit)

[void]$form.ShowDialog()