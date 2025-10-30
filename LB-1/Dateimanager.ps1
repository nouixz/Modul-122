#Requires -Version 7.0
<#
    Dateimanager.ps1
    PowerShell-Dateimanager mit Windows Forms GUI und HTML-Logging.
#>

###############################################################################
# Admin-Rechte und STA erzwingen (WinForms benötigt STA)
###############################################################################
if ($IsWindows) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    $isAdmin = $false
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        $isAdmin = $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch {}
    $isSTA = ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA')

    if ($scriptPath) {
        if (-not $isAdmin) {
            # Neu starten als Admin und STA
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"$scriptPath") -WindowStyle Normal | Out-Null
            return
        } elseif (-not $isSTA) {
            # Bereits Admin, aber nicht STA -> neu starten mit STA
            Start-Process -FilePath "powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"$scriptPath") -WindowStyle Normal | Out-Null
            return
        }
    }
}

###############################################################################
# Required assemblies
###############################################################################
Add-Type -AssemblyName System.Windows.Forms, System.Drawing | Out-Null
Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

###############################################################################
# Constants & Globals
###############################################################################
$Script:AppName = 'Dateimanager'
$Script:Version = '2.0.0'
$Script:ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Script:ScriptRoot -PathType Container)) { $Script:ScriptRoot = (Get-Location).Path }
$Script:ActionStamp = $null
$Script:LogLock = New-Object object
$LogHtmlPath = Join-Path $Script:ScriptRoot 'log.html'

###############################################################################
# HTML Logging (reichhaltig – „altes“ Logging)
###############################################################################
function Initialize-LogHtml {
    $dir = Split-Path -Parent $LogHtmlPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path -LiteralPath $LogHtmlPath) { return }
    $app = $Script:AppName
    $ver = $Script:Version
    $lines = @(
        '<!DOCTYPE html>'
        '<html lang="de">'
        '<head>'
        '<meta charset="utf-8"/>'
        '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
        ("<title>{0} – Log</title>" -f $app)
        '<style>'
        ':root { color-scheme:dark; --bg:#090909; --card:#181818; --text:#e5e7eb; --muted:#8a8a8a; --accent:#3a82f7; --danger:#f87171; --warn:#fbbf24; --ok:#34d399; --mono:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; }'
        '* { box-sizing:border-box; }'
        'body { margin:0; background:#090909; color:var(--text); font:15px/1.5 system-ui; padding:32px; }'
        'header { display:flex; align-items:center; justify-content:space-between; margin-bottom:20px; }'
        'h1 { font-size:22px; margin:0; letter-spacing:.3px; }'
        '.meta { color:var(--muted); font-size:13px; }'
        '.card { background:#181818; border:1px solid #232323; border-radius:0; padding:18px; }'
        'table { width:100%; border-collapse:collapse; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:13px; }'
        'thead th { text-align:left; color:var(--muted); font-weight:600; padding:10px 8px; border-bottom:1px solid #232323; position:sticky; top:0; background:#181818; }'
        'tbody td { padding:10px 8px; border-bottom:1px solid #232323; vertical-align:top; }'
        'tr:hover { background:#222; }'
        '.tag { display:inline-block; padding:2px 8px; border-radius:0; font-size:13px; border:1px solid #232323; }'
        '.level-info { color:#60a5fa; }'
        '.level-ok { color:#34d399; }'
        '.level-warn { color:#fbbf24; }'
        '.level-error { color:#f87171; }'
        '.icon { font-size:15px; margin-right:6px; vertical-align:middle; }'
        '.path { color:#d1d5db }'
        '.time { color:#9ca3af }'
        '</style>'
        '</head>'
        '<body>'
        '<header>'
        ("<h1>{0} – Aktivitätslog</h1>" -f $app)
        ("<div class='meta'>Version {0}</div>" -f $ver)
        '</header>'
        '<div class="card">'
        '<table id="log">'
        '<thead>'
        '<tr><th>Zeit</th><th>Aktion</th><th>Details</th><th>Status</th></tr>'
        '</thead>'
        '<tbody>'
        '</tbody>'
        '</table>'
        '</div>'
        '</body>'
        '</html>'
    )
    try {
        Set-Content -Path $LogHtmlPath -Value ($lines -join "`n") -Encoding UTF8 -ErrorAction Stop
    } catch {
        $fallbackDir = Join-Path $env:TEMP 'DateimanagerLogs'
        try { if (-not (Test-Path -LiteralPath $fallbackDir)) { New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null } } catch {}
        $script:LogHtmlPath = Join-Path $fallbackDir 'log.html'
        try { Set-Content -Path $script:LogHtmlPath -Value ($lines -join "`n") -Encoding UTF8 -ErrorAction Stop } catch {}
    }
}

function Write-LogHtml {
    param(
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO',
        [string]$Action,
        [string]$Details
    )
    Initialize-LogHtml
    if (-not (Test-Path -LiteralPath $LogHtmlPath)) { return }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $safe = $Details
    try { $safe = [System.Net.WebUtility]::HtmlEncode($Details) } catch {}
    $icon = switch ($Level) { 'OK' { '✅' } 'WARN' { '⚠️' } 'ERROR' { '❌' } default { 'ℹ️' } }
    $cls  = switch ($Level) { 'OK' { 'level-ok' } 'WARN' { 'level-warn' } 'ERROR' { 'level-error' } default { 'level-info' } }
    $row = "<tr><td class='time'>$ts</td><td>$Action</td><td class='path'>$safe</td><td><span class='tag $cls'><span class='icon'>$icon</span>$Level</span></td></tr>"
    $null = [System.Threading.Monitor]::Enter($Script:LogLock)
    try {
        $html = Get-Content -LiteralPath $LogHtmlPath -Raw -Encoding UTF8
        $out  = $html -replace '</tbody>', "$row`n      </tbody>"
        Set-Content -Path $LogHtmlPath -Value $out -Encoding UTF8
    } catch {}
    finally { [System.Threading.Monitor]::Exit($Script:LogLock) }
}

###############################################################################
# Helpers
###############################################################################
function Get-ActionStamp { if (-not $Script:ActionStamp) { $Script:ActionStamp = Get-Date -Format 'yyyyMMdd_HHmmss' }; return $Script:ActionStamp }
function Reset-ActionStamp { $Script:ActionStamp = $null }

function Get-SafeExistingDirectory {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        try {
            $full = [System.IO.Path]::GetFullPath($Path)
            if (Test-Path -LiteralPath $full -PathType Container) { return $full }
        } catch {}
    }
    if ($env:USERPROFILE -and (Test-Path -LiteralPath $env:USERPROFILE -PathType Container)) { return $env:USERPROFILE }
    return (Get-Location).Path
}

function Select-Folder {
    param([string]$InitialPath)
    $sel = $null
    $attempt = 0
    while ($attempt -lt 2) {
        $attempt++
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $dlg.ShowNewFolderButton = $true
            $safe = Get-SafeExistingDirectory -Path $InitialPath
            if ($safe) { $dlg.SelectedPath = $safe }
            $res = $dlg.ShowDialog()
            if ($res -eq [System.Windows.Forms.DialogResult]::OK) { $sel = $dlg.SelectedPath; break }
            else { break } # Bei Abbruch nicht erneut öffnen
        } catch {
            if ($attempt -ge 2) { throw }
            # bei Ausnahme einmalig erneut versuchen
        } finally { $dlg.Dispose() }
    }
    return $sel
}

function Get-SelectedFiles {
    # Erst Checkboxen, dann markierte, sonst alle
    $checked = @($lvFiles.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($checked.Count -gt 0) { return $checked }
    $sel = @($lvFiles.SelectedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -gt 0) { return $sel }
    return @($lvFiles.Items | ForEach-Object { $_.Tag })
}

###############################################################################
# Build Windows Forms UI
###############################################################################
$form = New-Object System.Windows.Forms.Form
$form.Text = "$($Script:AppName) $($Script:Version)"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1100, 700)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)

$lblRoot = New-Object System.Windows.Forms.Label;   $lblRoot.Text = 'Wurzelpfad'; $lblRoot.Location = '12,12'; $lblRoot.AutoSize = $true
$tbRoot  = New-Object System.Windows.Forms.TextBox; $tbRoot.Location = '12,32'; $tbRoot.Width = 320; $tbRoot.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowseRoot = New-Object System.Windows.Forms.Button; $btnBrowseRoot.Text = 'Durchsuchen…'; $btnBrowseRoot.Location = '340,30'

$lblPattern = New-Object System.Windows.Forms.Label; $lblPattern.Text = 'Muster (z.B. *.pdf)'; $lblPattern.Location = '12,64'; $lblPattern.AutoSize = $true
$tbPattern = New-Object System.Windows.Forms.TextBox; $tbPattern.Location = '12,84'; $tbPattern.Width = 320; $tbPattern.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblDest = New-Object System.Windows.Forms.Label; $lblDest.Text = 'Zielordner (Kopieren/Verschieben)'; $lblDest.Location = '12,150'; $lblDest.AutoSize = $true
$tbDest  = New-Object System.Windows.Forms.TextBox; $tbDest.Location = '12,170'; $tbDest.Width = 320; $tbDest.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowseDest = New-Object System.Windows.Forms.Button; $btnBrowseDest.Text = 'Durchsuchen…'; $btnBrowseDest.Location = '340,168'

$lblBackup = New-Object System.Windows.Forms.Label; $lblBackup.Text = 'Backup Basisordner'; $lblBackup.Location = '12,202'; $lblBackup.AutoSize = $true
$tbBackup = New-Object System.Windows.Forms.TextBox; $tbBackup.Location = '12,222'; $tbBackup.Width = 320; $tbBackup.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowseBackup = New-Object System.Windows.Forms.Button; $btnBrowseBackup.Text = 'Durchsuchen…'; $btnBrowseBackup.Location = '340,220'

$lblArchive = New-Object System.Windows.Forms.Label; $lblArchive.Text = 'Archiv-Ziel (ZIP)'; $lblArchive.Location = '12,254'; $lblArchive.AutoSize = $true
$tbArchive = New-Object System.Windows.Forms.TextBox; $tbArchive.Location = '12,274'; $tbArchive.Width = 320; $tbArchive.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowseArchive = New-Object System.Windows.Forms.Button; $btnBrowseArchive.Text = '…'; $btnBrowseArchive.Location = '340,272'

$btnSearch  = New-Object System.Windows.Forms.Button; $btnSearch.Text = 'Suchen'; $btnSearch.Width = 140
$btnCopy    = New-Object System.Windows.Forms.Button; $btnCopy.Text = 'Kopieren'; $btnCopy.Width = 140
$btnMove    = New-Object System.Windows.Forms.Button; $btnMove.Text = 'Verschieben'; $btnMove.Width = 140
$btnArchive = New-Object System.Windows.Forms.Button; $btnArchive.Text = 'Archiv (ZIP)'; $btnArchive.Width = 140
$btnBackup  = New-Object System.Windows.Forms.Button; $btnBackup.Text = 'Backup'; $btnBackup.Width = 140

# Button-Styles (Farben) und Layout innerhalb eines Panels
foreach ($btn in @($btnSearch,$btnCopy,$btnMove,$btnArchive,$btnBackup)) {
    $btn.UseVisualStyleBackColor = $false
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.Height = 34
}
$btnSearch.BackColor  = [System.Drawing.Color]::SteelBlue;   $btnSearch.ForeColor  = [System.Drawing.Color]::White
$btnCopy.BackColor    = [System.Drawing.Color]::SeaGreen;    $btnCopy.ForeColor    = [System.Drawing.Color]::White
$btnMove.BackColor    = [System.Drawing.Color]::DarkOrange;  $btnMove.ForeColor    = [System.Drawing.Color]::White
$btnArchive.BackColor = [System.Drawing.Color]::MediumPurple; $btnArchive.ForeColor = [System.Drawing.Color]::White
$btnBackup.BackColor  = [System.Drawing.Color]::Teal;        $btnBackup.ForeColor  = [System.Drawing.Color]::White

# Panel für Buttons oben rechts
$pnlActions = New-Object System.Windows.Forms.Panel
$pnlActions.Width = 160
$pnlActions.Height = 220
$pnlActions.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlActions.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - $pnlActions.Width - 12), 12)

# Buttons im Panel anordnen (vertikal)
$btnSearch.Location  = '10,0'
$btnCopy.Location    = '10,44'
$btnMove.Location    = '10,88'
$btnArchive.Location = '10,132'
$btnBackup.Location  = '10,176'

$pnlActions.Controls.AddRange(@($btnSearch,$btnCopy,$btnMove,$btnArchive,$btnBackup))

$lvFiles = New-Object System.Windows.Forms.ListView
$lvFiles.Location = '12,320'
$lvFiles.Size = New-Object System.Drawing.Size(1060, 300)
$lvFiles.View = [System.Windows.Forms.View]::Details
$lvFiles.FullRowSelect = $true
$lvFiles.CheckBoxes = $true
$lvFiles.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$lvFiles.Columns.Add('Name',220)   | Out-Null
$lvFiles.Columns.Add('Pfad',520)   | Out-Null
$lvFiles.Columns.Add('Ordner',200) | Out-Null
$lvFiles.Columns.Add('Groesse',100)| Out-Null
$lvFiles.Columns.Add('Geaendert',160)| Out-Null

$status = New-Object System.Windows.Forms.StatusStrip
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel; $lblStatus.Text = 'Bereit.'
$lnkLog = New-Object System.Windows.Forms.ToolStripStatusLabel; $lnkLog.IsLink = $true; $lnkLog.Text = 'Log öffnen'
$status.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pbSearch = New-Object System.Windows.Forms.ToolStripProgressBar
$pbSearch.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$pbSearch.MarqueeAnimationSpeed = 30
$pbSearch.Visible = $false
$status.Items.Add($lblStatus) | Out-Null
$status.Items.Add($lnkLog) | Out-Null
$status.Items.Add($pbSearch) | Out-Null

$form.Controls.AddRange(@(
    $lblRoot,$tbRoot,$btnBrowseRoot,
    $lblPattern,$tbPattern,
    $lblDest,$tbDest,$btnBrowseDest,
    $lblBackup,$tbBackup,$btnBrowseBackup,
    $lblArchive,$tbArchive,$btnBrowseArchive,
    $pnlActions,
    $lvFiles,$status
))

###############################################################################
# Defaults & status
###############################################################################
$tbRoot.Text    = "$HOME"
$tbPattern.Text = '*'
$tbDest.Text    = Join-Path $HOME 'Desktop'
$tbBackup.Text  = Join-Path $HOME 'Backups'
$tbArchive.Text = Join-Path (Join-Path $HOME 'Desktop') 'Archiv.zip'

function Set-Status([string]$msg) { $lblStatus.Text = $msg }

###############################################################################
# Events
###############################################################################
$btnBrowseRoot.Add_Click({ $sel = Select-Folder -InitialPath $tbRoot.Text; if ($sel) { $tbRoot.Text = $sel } })
$btnBrowseDest.Add_Click({ $sel = Select-Folder -InitialPath $tbDest.Text; if ($sel) { $tbDest.Text = $sel } })
$btnBrowseBackup.Add_Click({ $sel = Select-Folder -InitialPath $tbBackup.Text; if ($sel) { $tbBackup.Text = $sel } })
$btnBrowseArchive.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = 'Archiv speichern unter'; $sfd.Filter = 'ZIP-Archiv (*.zip)|*.zip|Alle Dateien (*.*)|*.*'
    $initDir = Get-SafeExistingDirectory -Path (Split-Path -Parent $tbArchive.Text)
    if ($initDir) { $sfd.InitialDirectory = $initDir }
    $sfd.FileName = if ([string]::IsNullOrWhiteSpace($tbArchive.Text)) { 'Archiv.zip' } else { Split-Path -Leaf $tbArchive.Text }
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $tbArchive.Text = $sfd.FileName }
    $sfd.Dispose()
})

$btnSearch.Add_Click({
    Reset-ActionStamp
    $lvFiles.BeginUpdate(); $lvFiles.Items.Clear(); $lvFiles.EndUpdate()
    try {
        $btnSearch.Enabled = $false; $pbSearch.Visible = $true; Set-Status 'Suche läuft…'
    if (-not (Test-Path -LiteralPath $tbRoot.Text)) { Set-Status "Pfad nicht gefunden"; Write-LogHtml -Level 'ERROR' -Action 'Suche' -Details "Pfad nicht gefunden: $($tbRoot.Text)"; return }
    $root = $tbRoot.Text
    $pattern = if ([string]::IsNullOrWhiteSpace($tbPattern.Text)) { '*' } else { $tbPattern.Text }
    # Robuste Suche: -Include benötigt Wildcard im Pfad; Fehler (Zugriff) werden unterdrückt
    $searchPath = (Join-Path $root '*')
    $files = Get-ChildItem -Path $searchPath -Recurse -File -Include $pattern -ErrorAction SilentlyContinue
        $count = 0
        $lvFiles.BeginUpdate()
        foreach ($f in $files) {
            $item = New-Object System.Windows.Forms.ListViewItem($f.Name)
            [void]$item.SubItems.Add($f.FullName)
            [void]$item.SubItems.Add($f.DirectoryName)
            [void]$item.SubItems.Add($f.Length)
            [void]$item.SubItems.Add($f.LastWriteTime)
            $item.Tag = $f
            $lvFiles.Items.Add($item) | Out-Null
            $count++
        }
        $lvFiles.EndUpdate()
        try { $lvFiles.AutoResizeColumns([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::HeaderSize) } catch {}
        Set-Status ("Treffer: {0}" -f $count)
        Write-LogHtml -Level 'OK' -Action 'Suche' -Details ("Gefunden: {0} – '{1}' in {2}" -f $count, $tbPattern.Text, $tbRoot.Text)
    } catch {
        $msg = $_.Exception.Message; Set-Status "Fehler: $msg"; Write-LogHtml -Level 'ERROR' -Action 'Suche' -Details $msg
    }
    finally { $pbSearch.Visible = $false; $btnSearch.Enabled = $true }
})

$btnCopy.Add_Click({
    $sel = Get-SelectedFiles
    if (-not $sel -or $sel.Count -eq 0) { Set-Status 'Keine Dateien ausgewählt.'; return }
    if (-not (Test-Path -LiteralPath $tbDest.Text)) { New-Item -ItemType Directory -Path $tbDest.Text -Force | Out-Null }
    $ok=0;$err=0
    foreach ($f in $sel) {
        try { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $tbDest.Text $f.Name) -Force; $ok++ }
        catch { $err++ }
    }
    Set-Status ("Kopiert: {0}, Fehler: {1}" -f $ok,$err)
    Write-LogHtml -Level ($err -gt 0 ? 'WARN' : 'OK') -Action 'Kopieren' -Details ("{0} Dateien -> {1}" -f $sel.Count, $tbDest.Text)
})

$btnMove.Add_Click({
    $sel = Get-SelectedFiles
    if (-not $sel -or $sel.Count -eq 0) { Set-Status 'Keine Dateien ausgewählt.'; return }
    if (-not (Test-Path -LiteralPath $tbDest.Text)) { New-Item -ItemType Directory -Path $tbDest.Text -Force | Out-Null }
    $ok=0;$err=0
    foreach ($f in $sel) {
        try { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $tbDest.Text $f.Name) -Force; $ok++ }
        catch { $err++ }
    }
    Set-Status ("Verschoben: {0}, Fehler: {1}" -f $ok,$err)
    Write-LogHtml -Level ($err -gt 0 ? 'WARN' : 'OK') -Action 'Verschieben' -Details ("{0} Dateien -> {1}" -f $sel.Count, $tbDest.Text)
})

$btnArchive.Add_Click({
    $sel = Get-SelectedFiles
    if (-not $sel -or $sel.Count -eq 0) { Set-Status 'Keine Dateien ausgewählt.'; return }
    $stamp = Get-ActionStamp
    $raw = $tbArchive.Text
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = Join-Path $HOME ("Archiv_{0}.zip" -f $stamp) }
    $outPath = $null
    if (Test-Path -LiteralPath $raw -PathType Container) {
        $outPath = Join-Path $raw ("Archiv_{0}.zip" -f $stamp)
    } else {
        $dir = Split-Path -Parent $raw; if (-not $dir) { $dir = (Get-Location).Path }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $name = Split-Path -Leaf $raw; if (-not $name.ToLower().EndsWith('.zip')) { $name = "$name.zip" }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $outPath = Join-Path $dir ("{0}_{1}.zip" -f $base,$stamp)
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        foreach ($f in $sel) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $tmp $f.Name) -Force }
        if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $outPath -Force
        Set-Status ("Archiv erstellt: {0}" -f $outPath)
        Write-LogHtml -Level 'OK' -Action 'Archiv' -Details $outPath
    } catch { Set-Status ("Fehler beim Archivieren: {0}" -f $_.Exception.Message); Write-LogHtml -Level 'ERROR' -Action 'Archiv' -Details $_.Exception.Message }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force } }
})

$btnBackup.Add_Click({
    $sel = Get-SelectedFiles
    if (-not $sel -or $sel.Count -eq 0) { Set-Status 'Keine Dateien ausgewählt.'; return }
    $root = if ([string]::IsNullOrWhiteSpace($tbBackup.Text)) { Join-Path $HOME 'Backups' } else { $tbBackup.Text }
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $dest = Join-Path $root ("Backup_{0}" -f (Get-ActionStamp))
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $ok=0;$err=0
    foreach ($f in $sel) {
        try { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -Force; $ok++ }
        catch { $err++ }
    }
    Set-Status ("Backup: {0} Dateien -> {1}" -f $ok,$dest)
    Write-LogHtml -Level ($err -gt 0 ? 'WARN' : 'OK') -Action 'Backup' -Details ("{0} Dateien -> {1}" -f $ok,$dest)
})

$lnkLog.Add_Click({ Initialize-LogHtml; if (Test-Path -LiteralPath $LogHtmlPath) { Start-Process -FilePath $LogHtmlPath } })

###############################################################################
# Startup
###############################################################################
Initialize-LogHtml
Write-LogHtml -Level 'INFO' -Action 'Start' -Details ("Root={0}" -f $Script:ScriptRoot)
[void]$form.ShowDialog()
