# Cross-platform PowerShell Backup Tool

# Config file path
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"

function Load-Config {
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    } else {
        $default = @{
            SourcePath = ""
            TargetPath = ""
            LogFile = "./backup.log"
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

function Run-Backup($config) {
    $src = $config.SourcePath
    $dst = $config.TargetPath
    $log = $config.LogFile
    $exclude = $config.Exclude

    if (-not (Test-Path $src)) {
        Write-Log "Source path '$src' does not exist." $log
        return "Source path does not exist."
    }
    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst | Out-Null
    }
    $files = Get-ChildItem -Path $src -Recurse -File | Where-Object {
        $ext = $_.Extension
        -not ($exclude -contains $ext)
    }
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($src.Length)
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

# Platform check
if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $config = Load-Config

    $form = New-Object Windows.Forms.Form
    $form.Text = "PowerShell Backup Tool"
    $form.Size = New-Object Drawing.Size(500, 400)
    $form.StartPosition = "CenterScreen"

    $lblSource = New-Object Windows.Forms.Label
    $lblSource.Text = "Source Path:"
    $lblSource.Location = '10,20'
    $lblSource.Size = '100,20'
    $form.Controls.Add($lblSource)

    $txtSource = New-Object Windows.Forms.TextBox
    $txtSource.Location = '120,20'
    $txtSource.Size = '250,20'
    $txtSource.Text = $config.SourcePath
    $form.Controls.Add($txtSource)

    $btnBrowseSource = New-Object Windows.Forms.Button
    $btnBrowseSource.Text = "Browse"
    $btnBrowseSource.Location = '380,20'
    $btnBrowseSource.Size = '80,20'
    $btnBrowseSource.Add_Click({
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        if ($fbd.ShowDialog() -eq "OK") {
            $txtSource.Text = $fbd.SelectedPath
        }
    })
    $form.Controls.Add($btnBrowseSource)

    $lblTarget = New-Object Windows.Forms.Label
    $lblTarget.Text = "Target Path:"
    $lblTarget.Location = '10,60'
    $lblTarget.Size = '100,20'
    $form.Controls.Add($lblTarget)

    $txtTarget = New-Object Windows.Forms.TextBox
    $txtTarget.Location = '120,60'
    $txtTarget.Size = '250,20'
    $txtTarget.Text = $config.TargetPath
    $form.Controls.Add($txtTarget)

    $btnBrowseTarget = New-Object Windows.Forms.Button
    $btnBrowseTarget.Text = "Browse"
    $btnBrowseTarget.Location = '380,60'
    $btnBrowseTarget.Size = '80,20'
    $btnBrowseTarget.Add_Click({
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        if ($fbd.ShowDialog() -eq "OK") {
            $txtTarget.Text = $fbd.SelectedPath
        }
    })
    $form.Controls.Add($btnBrowseTarget)

    $lblLog = New-Object Windows.Forms.Label
    $lblLog.Text = "Log File:"
    $lblLog.Location = '10,100'
    $lblLog.Size = '100,20'
    $form.Controls.Add($lblLog)

    $txtLog = New-Object Windows.Forms.TextBox
    $txtLog.Location = '120,100'
    $txtLog.Size = '250,20'
    $txtLog.Text = $config.LogFile
    $form.Controls.Add($txtLog)

    $lblExclude = New-Object Windows.Forms.Label
    $lblExclude.Text = "Exclude Extensions (comma separated):"
    $lblExclude.Location = '10,140'
    $lblExclude.Size = '250,20'
    $form.Controls.Add($lblExclude)

    $txtExclude = New-Object Windows.Forms.TextBox
    $txtExclude.Location = '10,170'
    $txtExclude.Size = '450,20'
    $txtExclude.Text = ($config.Exclude -join ", ")
    $form.Controls.Add($txtExclude)

    $btnSave = New-Object Windows.Forms.Button
    $btnSave.Text = "Save Config"
    $btnSave.Location = '10,210'
    $btnSave.Size = '120,30'
    $btnSave.Add_Click({
        $config.SourcePath = $txtSource.Text
        $config.TargetPath = $txtTarget.Text
        $config.LogFile = $txtLog.Text
        $config.Exclude = $txtExclude.Text -split ',' | ForEach-Object { $_.Trim() }
        Save-Config $config
        [Windows.Forms.MessageBox]::Show("Config saved.")
    })
    $form.Controls.Add($btnSave)

    $btnBackup = New-Object Windows.Forms.Button
    $btnBackup.Text = "Run Backup"
    $btnBackup.Location = '140,210'
    $btnBackup.Size = '120,30'
    $btnBackup.Add_Click({
        $config.SourcePath = $txtSource.Text
        $config.TargetPath = $txtTarget.Text
        $config.LogFile = $txtLog.Text
        $config.Exclude = $txtExclude.Text -split ',' | ForEach-Object { $_.Trim() }
        Save-Config $config
        $result = Run-Backup $config
        [Windows.Forms.MessageBox]::Show($result)
    })
    $form.Controls.Add($btnBackup)

    $btnViewLog = New-Object Windows.Forms.Button
    $btnViewLog.Text = "View Log"
    $btnViewLog.Location = '270,210'
    $btnViewLog.Size = '120,30'
    $btnViewLog.Add_Click({
        if (Test-Path $txtLog.Text) {
            $logContent = Get-Content $txtLog.Text -Raw
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
    $form.Controls.Add($btnViewLog)

    [void]$form.ShowDialog()
}
else {
    # Terminal menu for macOS/Linux
    function Show-Menu {
        Write-Host "PowerShell Backup Tool (Terminal Mode)"
        Write-Host "1. Edit Config"
        Write-Host "2. Run Backup"
        Write-Host "3. View Log"
        Write-Host "4. Exit"
        $choice = Read-Host "Choose an option"
        return $choice
    }

    $config = Load-Config

    while ($true) {
        $choice = Show-Menu
        switch ($choice) {
            "1" {
                $config.SourcePath = Read-Host "Source Path [$($config.SourcePath)]"
                if (-not $config.SourcePath) { $config.SourcePath = $config.SourcePath }
                $config.TargetPath = Read-Host "Target Path [$($config.TargetPath)]"
                if (-not $config.TargetPath) { $config.TargetPath = $config.TargetPath }
                $config.LogFile = Read-Host "Log File [$($config.LogFile)]"
                if (-not $config.LogFile) { $config.LogFile = $config.LogFile }
                $excludeInput = Read-Host "Exclude Extensions (comma separated) [$($config.Exclude -join ', ')]"
                if ($excludeInput) {
                    $config.Exclude = $excludeInput -split ',' | ForEach-Object { $_.Trim() }
                }
                Save-Config $config
                Write-Host "Config saved.`n"
            }
            "2" {
                $result = Run-Backup $config
                Write-Host "$result`n"
            }
            "3" {
                if (Test-Path $config.LogFile) {
                    Write-Host "`n--- Log File ---"
                    Get-Content $config.LogFile
                    Write-Host "----------------`n"
                } else {
                    Write-Host "Log file not found.`n"
                }
            }
            "4" { break }
            default { Write-Host "Invalid choice.`n" }
        }
    }
}