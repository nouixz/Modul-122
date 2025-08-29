# PowerShell Backup Tool - Simple

# Minimal, reliable backup with optional ZIP.
# - Windows: simple GUI (Windows Forms)
# - macOS/Linux: simple terminal menu

param(
    [switch]$Terminal
)

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

if ($IsWindows -and -not $Terminal) {
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
    # Simple terminal menu (macOS/Linux or forced with -Terminal)
    function Prompt-YesNo($message) {
        $ans = Read-Host "$message (y/n)"
        return ($ans -match '^(?i)y')
    }

    function Read-Indices($max) {
        $raw = Read-Host "Select indexes (e.g. 1,3-5 or 'all')"
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        if ($raw.Trim().ToLower() -eq 'all') { return 1..$max }
        $result = @()
        foreach ($token in $raw.Split(',')) {
            $token = $token.Trim()
            if ($token -match '^(\d+)-(\d+)$') {
                $a = [int]$Matches[1]; $b = [int]$Matches[2]
                if ($a -le $b) { $result += $a..$b } else { $result += $b..$a }
            } elseif ($token -match '^\d+$') {
                $i = [int]$token; if ($i -ge 1 -and $i -le $max) { $result += $i }
            }
        }
        return ($result | Sort-Object -Unique)
    }

    function Find-FilesByExtension($basePath, $extension) {
        if (-not (Test-Path $basePath)) { return @() }
        $ext = $extension.Trim()
        if ($ext -and -not $ext.StartsWith('.')) { $ext = '.' + $ext }
        if ([string]::IsNullOrWhiteSpace($ext)) { return @() }
        return Get-ChildItem -Path $basePath -Recurse -File -Force | Where-Object { $_.Extension -ieq $ext }
    }

    function Zip-SelectedFiles($basePath, $files, $zipPath) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $staging = Join-Path -Path $PSScriptRoot -ChildPath ("staging_" + (Get-Date -Format 'yyyyMMddHHmmssfff'))
        try {
            New-Item -ItemType Directory -Path $staging -Force | Out-Null
            $sep1 = [IO.Path]::DirectorySeparatorChar; $sep2 = [IO.Path]::AltDirectorySeparatorChar
            $baseFull = (Resolve-Path $basePath).ProviderPath
            if (-not ($baseFull.EndsWith($sep1) -or $baseFull.EndsWith($sep2))) { $baseFull += $sep1 }
            foreach ($f in $files) {
                $rel = $f.FullName.Substring($baseFull.Length).TrimStart($sep1,$sep2)
                $dest = Join-Path $staging $rel
                $destDir = Split-Path $dest
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            }
            if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath)
            return $true
        } catch {
            Write-Log "Zip-SelectedFiles error: $($_.Exception.Message)" $logPath
            return $false
        } finally {
            if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        }
    }

    function File-Tools-ByExtension {
        Write-Host "\nFile tools by extension"
        $base = Read-Host "Base path [$($cfg.SourceFolder)]"; if (-not $base) { $base = $cfg.SourceFolder }
        if (-not (Test-Path $base)) { Write-Host "Path not found."; return }
        $ext = Read-Host "Extension (e.g. .txt)"
        $list = @(Find-FilesByExtension -basePath $base -extension $ext)
        if ($list.Count -eq 0) { Write-Host "No files found."; return }
        for ($i=0; $i -lt $list.Count; $i++) { Write-Host "[$($i+1)] $($list[$i].FullName)" }
        $sel = Read-Indices -max $list.Count; if ($sel.Count -eq 0) { Write-Host "Nothing selected."; return }
        $picked = $sel | ForEach-Object { $list[$_-1] }

        Write-Host "Actions: 1) Copy  2) Move  3) Rename (suffix)  4) Zip to archive  5) Cancel"
        $act = Read-Host "Choose"
        switch ($act) {
            '1' {
                $dest = Read-Host "Copy to destination path [$($cfg.TargetFolder)]"; if (-not $dest) { $dest = $cfg.TargetFolder }
                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                foreach ($f in $picked) {
                    try { Copy-Item -LiteralPath $f.FullName -Destination $dest -Force; Write-Log "Copied $($f.FullName) -> $dest" $logPath } catch { Write-Log "Copy error: $($_.Exception.Message)" $logPath }
                }
            }
            '2' {
                $dest = Read-Host "Move to destination path"
                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                foreach ($f in $picked) {
                    try { Move-Item -LiteralPath $f.FullName -Destination $dest -Force; Write-Log "Moved $($f.FullName) -> $dest" $logPath } catch { Write-Log "Move error: $($_.Exception.Message)" $logPath }
                }
            }
            '3' {
                $suffix = Read-Host "Suffix to append before extension (e.g. -old)"
                foreach ($f in $picked) {
                    try {
                        $dir = Split-Path $f.FullName; $name=$f.BaseName; $extn=$f.Extension
                        $new = Join-Path $dir ("$name$suffix$extn")
                        Rename-Item -LiteralPath $f.FullName -NewName $new -Force
                        Write-Log "Renamed $($f.FullName) -> $new" $logPath
                    } catch { Write-Log "Rename error: $($_.Exception.Message)" $logPath }
                }
            }
            '4' {
                $zipOut = Read-Host "Zip output file (full path)"
                if (-not $zipOut) { Write-Host "Canceled."; return }
                if (Zip-SelectedFiles -basePath $base -files $picked -zipPath $zipOut) {
                    Write-Host "Created archive: $zipOut"; Write-Log "Created archive: $zipOut" $logPath
                } else { Write-Host "Failed to create archive." }
            }
            default { Write-Host "Canceled." }
        }
    }

    function Process-Manager {
        while ($true) {
            Write-Host "\nProcess Manager"
            Write-Host "1) List processes (top 20 by CPU)"
            Write-Host "2) Find by name"
            Write-Host "3) Kill by Id"
            Write-Host "4) Start process"
            Write-Host "5) Back"
            $c = Read-Host "Choose"
            switch ($c) {
                '1' { Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 | Format-Table Id,ProcessName,CPU,PM -Auto }
                '2' { $n = Read-Host 'Name contains'; Get-Process | Where-Object { $_.ProcessName -like "*${n}*" } | Format-Table Id,ProcessName,CPU,PM -Auto }
                '3' { $id = Read-Host 'PID'; try { Stop-Process -Id ([int]$id) -Force; Write-Log "Stopped PID $id" $logPath } catch { Write-Log "Stop error: $($_.Exception.Message)" $logPath } }
                '4' { $cmd = Read-Host 'Command or path'; if ($cmd) { try { Start-Process -FilePath $cmd; Write-Log "Started: $cmd" $logPath } catch { Write-Log "Start error: $($_.Exception.Message)" $logPath } } }
                '5' { break }
                default { Write-Host 'Invalid.' }
            }
        }
    }

    while ($true) {
        Write-Host "\nBackup Tool"
        Write-Host "1) Set Source (current: $($cfg.SourceFolder))"
        Write-Host "2) Set Destination (current: $($cfg.TargetFolder))"
        Write-Host "3) Toggle ZIP (current: $([bool]$cfg.ZipBackup))"
        Write-Host "4) Run Backup"
        Write-Host "5) View Log"
        Write-Host "6) File tools by extension"
        Write-Host "7) Process manager"
        Write-Host "8) Save & Exit"
        $c = Read-Host "Choose"
        switch ($c) {
            '1' { $inp = Read-Host "Source path"; if ($inp) { $cfg.SourceFolder = $inp } }
            '2' { $inp = Read-Host "Destination path"; if ($inp) { $cfg.TargetFolder = $inp } }
            '3' { $cfg.ZipBackup = -not [bool]$cfg.ZipBackup; Write-Host "ZIP now: $($cfg.ZipBackup)" }
            '4' { $cfg.LogFile = $logPath; Save-Config $cfg; $res = Start-Backup $cfg; Write-Host $res }
            '5' { if (Test-Path $logPath) { Get-Content $logPath | Out-Host } else { Write-Host 'No log yet.' } }
            '6' { File-Tools-ByExtension }
            '7' { Process-Manager }
            '8' { Save-Config $cfg; break }
            default { Write-Host 'Invalid.' }
        }
    }
}