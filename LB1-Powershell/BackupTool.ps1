# PowerShell Backup Tool - Simple

# Minimal, reliable backup with optional ZIP.
# - Windows: simple GUI (Windows Forms)
# - macOS/Linux: simple terminal menu

param()

# Locations (store next to script for portability)
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
$logPath    = Join-Path -Path $PSScriptRoot -ChildPath "backup.log"

function Load-Config {
    if (Test-Path $configPath) {
        try { Get-Content $configPath -Raw | ConvertFrom-Json } catch { $null }
    }
    if (-not $?) { return [pscustomobject]@{ SourceFolder=""; TargetFolder=""; ZipBackup=$false; LogFile=$logPath } }
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 $configPath
}

function Write-Log($msg, $file) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $msg" | Add-Content -Encoding UTF8 $file
}

function Start-Backup($cfg) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $src = $cfg.SourceFolder
    $dst = $cfg.TargetFolder
    $log = if ($cfg.LogFile) { $cfg.LogFile } else { $logPath }

    if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($dst)) { return "Please set source and destination." }
    if (-not (Test-Path $src)) { Write-Log "Source not found: $src" $log; return "Source not found." }
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

    $srcFull = (Resolve-Path $src).ProviderPath
    $sourceName = Split-Path $srcFull -Leaf
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"

    if ($cfg.ZipBackup) {
        try {
            $zipPath = Join-Path $dst ($sourceName + "_backup_" + $stamp + ".zip")
            if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($srcFull, $zipPath)
            Write-Log "ZIP created: $zipPath from $srcFull" $log
            return "ZIP created: $zipPath"
        } catch {
            Write-Log "ZIP error: $($_.Exception.Message)" $log
            return "ZIP error: $($_.Exception.Message)"
        }
    } else {
        try {
            $targetRoot = Join-Path $dst ($sourceName + "_backup_" + $stamp)
            if (-not (Test-Path $targetRoot)) { New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null }

            $sep1 = [IO.Path]::DirectorySeparatorChar
            $sep2 = [IO.Path]::AltDirectorySeparatorChar
            $prefix = if ($srcFull.EndsWith($sep1) -or $srcFull.EndsWith($sep2)) { $srcFull } else { $srcFull + $sep1 }

            $files = Get-ChildItem -Path $srcFull -Recurse -File -Force
            foreach ($f in $files) {
                $rel = $f.FullName.Substring($prefix.Length).TrimStart($sep1,$sep2)
                $dest = Join-Path $targetRoot $rel
                $destDir = Split-Path $dest
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            }
            Write-Log "Copied folder to $targetRoot" $log
            return "Backup completed: $targetRoot"
        } catch {
            Write-Log "Copy error: $($_.Exception.Message)" $log
            return "Copy error: $($_.Exception.Message)"
        }
    }
}

$cfg = Load-Config
if (-not $cfg) { $cfg = [pscustomobject]@{ SourceFolder=""; TargetFolder=""; ZipBackup=$false; LogFile=$logPath } }

if ($IsWindows) {
    # Simple Windows GUI
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object Windows.Forms.Form
    $form.Text = "Backup Tool"
    $form.Size = New-Object Drawing.Size(560, 240)
    $form.StartPosition = "CenterScreen"

    $lblSrc = New-Object Windows.Forms.Label; $lblSrc.Text = "Source:"; $lblSrc.Location = '12,20'; $lblSrc.AutoSize = $true
    $txtSrc = New-Object Windows.Forms.TextBox; $txtSrc.Location='80,18'; $txtSrc.Size='360,24'; $txtSrc.Text=$cfg.SourceFolder
    $btnSrc = New-Object Windows.Forms.Button; $btnSrc.Text='...'; $btnSrc.Location='450,17'; $btnSrc.Size='30,26'
    $btnSrc.Add_Click({ $dlg = New-Object Windows.Forms.FolderBrowserDialog; if ($txtSrc.Text -and (Test-Path $txtSrc.Text)) { $dlg.SelectedPath=$txtSrc.Text }; if ($dlg.ShowDialog() -eq 'OK') { $txtSrc.Text=$dlg.SelectedPath } })

    $lblDst = New-Object Windows.Forms.Label; $lblDst.Text = "Destination:"; $lblDst.Location = '12,60'; $lblDst.AutoSize = $true
    $txtDst = New-Object Windows.Forms.TextBox; $txtDst.Location='80,58'; $txtDst.Size='360,24'; $txtDst.Text=$cfg.TargetFolder
    $btnDst = New-Object Windows.Forms.Button; $btnDst.Text='...'; $btnDst.Location='450,57'; $btnDst.Size='30,26'
    $btnDst.Add_Click({ $dlg = New-Object Windows.Forms.FolderBrowserDialog; if ($txtDst.Text -and (Test-Path $txtDst.Text)) { $dlg.SelectedPath=$txtDst.Text }; if ($dlg.ShowDialog() -eq 'OK') { $txtDst.Text=$dlg.SelectedPath } })

    $chkZip = New-Object Windows.Forms.CheckBox; $chkZip.Text='Create ZIP instead of copy'; $chkZip.Location='80,95'; $chkZip.AutoSize=$true; $chkZip.Checked=[bool]$cfg.ZipBackup

    $btnRun = New-Object Windows.Forms.Button; $btnRun.Text='Run Backup'; $btnRun.Location='80,130'; $btnRun.Size='120,30'
    $btnRun.Add_Click({
        $cfg.SourceFolder = $txtSrc.Text
        $cfg.TargetFolder = $txtDst.Text
        $cfg.ZipBackup = $chkZip.Checked
        $cfg.LogFile = $logPath
        Save-Config $cfg
        $res = Start-Backup $cfg
        [Windows.Forms.MessageBox]::Show($res) | Out-Null
    })

    $btnLog = New-Object Windows.Forms.Button; $btnLog.Text='View Log'; $btnLog.Location='210,130'; $btnLog.Size='100,30'
    $btnLog.Add_Click({ if (Test-Path $logPath) { $f = New-Object Windows.Forms.Form; $f.Text='Log'; $f.Size='520,360'; $t=New-Object Windows.Forms.TextBox; $t.Multiline=$true; $t.ReadOnly=$true; $t.ScrollBars='Vertical'; $t.Dock='Fill'; $t.Text=(Get-Content $logPath -Raw); $f.Controls.Add($t); $f.ShowDialog() | Out-Null } else { [Windows.Forms.MessageBox]::Show('No log yet.') | Out-Null } })

    $btnExit = New-Object Windows.Forms.Button; $btnExit.Text='Exit'; $btnExit.Location='320,130'; $btnExit.Size='100,30'; $btnExit.Add_Click({ $form.Close() })

    $form.Controls.AddRange(@($lblSrc,$txtSrc,$btnSrc,$lblDst,$txtDst,$btnDst,$chkZip,$btnRun,$btnLog,$btnExit))
    [void]$form.ShowDialog()
}
else {
    # Simple terminal menu for macOS/Linux
    while ($true) {
        Write-Host "\nBackup Tool"
        Write-Host "1) Set Source (current: $($cfg.SourceFolder))"
        Write-Host "2) Set Destination (current: $($cfg.TargetFolder))"
        Write-Host "3) Toggle ZIP (current: $([bool]$cfg.ZipBackup))"
        Write-Host "4) Run Backup"
        Write-Host "5) View Log"
        Write-Host "6) Save & Exit"
        $c = Read-Host "Choose"
        switch ($c) {
            '1' { $inp = Read-Host "Source path"; if ($inp) { $cfg.SourceFolder = $inp } }
            '2' { $inp = Read-Host "Destination path"; if ($inp) { $cfg.TargetFolder = $inp } }
            '3' { $cfg.ZipBackup = -not [bool]$cfg.ZipBackup; Write-Host "ZIP now: $($cfg.ZipBackup)" }
            '4' { $cfg.LogFile = $logPath; Save-Config $cfg; $res = Start-Backup $cfg; Write-Host $res }
            '5' { if (Test-Path $logPath) { Get-Content $logPath | Out-Host } else { Write-Host 'No log yet.' } }
            '6' { Save-Config $cfg; break }
            default { Write-Host 'Invalid.' }
        }
    }
}