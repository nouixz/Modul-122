#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic

#------------- Config and logging -------------
$Script:AppName    = 'FileManager'
$Script:Root       = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -LiteralPath $PSCommandPath -Parent }
$Script:LogPath    = Join-Path $Script:Root "$($Script:AppName).log"
$Script:ConfigPath = Join-Path $Script:Root 'config.json'

function Write-Log {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = '{0} [{1}] {2}' -f $ts,$Level,$Message
    try {
        $dir = Split-Path -Parent $Script:LogPath
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -LiteralPath $Script:LogPath -Value $line -Encoding utf8
    } catch { }
}

function Get-Config {
    if (Test-Path -LiteralPath $Script:ConfigPath) {
        try { return Get-Content -Raw -LiteralPath $Script:ConfigPath | ConvertFrom-Json } catch { }
    }
    [pscustomobject]@{
        SourceFolder = (Get-Location).Path
        TargetFolder = (Get-Location).Path
        BackupFolder = (Get-Location).Path
        ZipPath      = (Join-Path $Script:Root 'Archive.zip')
        Width        = 1000
        Height       = 650
    }
}
function Save-Config {
    param([Parameter(Mandatory)]$Cfg)
    try { $Cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Script:ConfigPath -Encoding utf8 } catch {
        Write-Log -Level 'WARN' -Message ("Failed to save config: {0}" -f $_.Exception.Message)
    }
}

#------------- Guards -------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Error 'This script must run in STA mode.'
    return
}

# Optional ASCII guard: fail fast if source contains non-ASCII
try {
    $self = Get-Content -LiteralPath $PSCommandPath -Raw -ErrorAction Stop
    if ($self -match '[^\x00-\x7F]') {
        Write-Error 'Non-ASCII characters detected in the script. Please remove them.'
        return
    }
} catch { }

$cfg = Get-Config

#------------- Theme -------------
$Theme = @{
    Bg        = [Drawing.Color]::FromArgb(30,30,30)        # #1E1E1E
    Surface   = [Drawing.Color]::FromArgb(43,43,43)        # #2B2B2B
    Text      = [Drawing.Color]::FromArgb(255,255,255)
    TextMuted = [Drawing.Color]::FromArgb(199,199,199)
    Accent    = [Drawing.Color]::FromArgb(0,120,212)       # #0078D4
    Danger    = [Drawing.Color]::FromArgb(200,64,64)
    Warn      = [Drawing.Color]::FromArgb(180,160,60)
    Ok        = [Drawing.Color]::FromArgb(56,158,76)
    Panel     = [Drawing.Color]::FromArgb(24,24,24)
    Grid      = [Drawing.Color]::FromArgb(64,64,64)
}

#------------- Form -------------
[Windows.Forms.Application]::EnableVisualStyles()
if ([Windows.Forms.Application]::SetHighDpiMode) {
    [Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::SystemAware)
}

$form = New-Object Windows.Forms.Form
$form.Text = 'File Manager'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = '840,520'
$form.Size = New-Object Drawing.Size($cfg.Width, $cfg.Height)
$form.BackColor = $Theme.Bg
$form.ForeColor = $Theme.Text
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

# Root grid
$root = New-Object Windows.Forms.TableLayoutPanel
$root.Dock = 'Fill'
$root.BackColor = $Theme.Bg
$root.ColumnCount = 1
$root.RowCount = 4
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))     | Out-Null  # top controls
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))  | Out-Null  # list
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))     | Out-Null  # actions
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))     | Out-Null  # status
$form.Controls.Add($root)

#------------- Top bar (folder + ext + search) -------------
$top = New-Object Windows.Forms.TableLayoutPanel
$top.Dock = 'Top'
$top.BackColor = $Theme.Bg
$top.ColumnCount = 6
$top.AutoSize = $true
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))             | Out-Null
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',60)))           | Out-Null
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))             | Out-Null
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))             | Out-Null
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))             | Out-Null
$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))             | Out-Null

$lblFolder = New-Object Windows.Forms.Label
$lblFolder.Text = 'Folder'
$lblFolder.AutoSize = $true
$lblFolder.Margin = '10,12,6,6'
$lblFolder.ForeColor = $Theme.Text

$tbFolder = New-Object Windows.Forms.TextBox
$tbFolder.Text = $cfg.SourceFolder
$tbFolder.Dock = 'Fill'
$tbFolder.Margin = '0,8,6,6'
$tbFolder.BackColor = $Theme.Surface
$tbFolder.ForeColor = $Theme.Text
$tbFolder.BorderStyle = 'FixedSingle'

$btnBrowse = New-Object Windows.Forms.Button
$btnBrowse.Text = '...'
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.Margin = '0,8,12,6'
$btnBrowse.BackColor = $Theme.Surface
$btnBrowse.ForeColor = $Theme.Text
$btnBrowse.FlatAppearance.BorderColor = $Theme.Accent

$lblExt = New-Object Windows.Forms.Label
$lblExt.Text = 'Ext'
$lblExt.AutoSize = $true
$lblExt.Margin = '0,12,6,6'
$lblExt.ForeColor = $Theme.Text

$tbExt = New-Object Windows.Forms.TextBox
$tbExt.Width = 90
$tbExt.Margin = '0,8,6,6'
$tbExt.BackColor = $Theme.Surface
$tbExt.ForeColor = $Theme.Text
$tbExt.BorderStyle = 'FixedSingle'
$tbExt.Text = ''

$btnSearch = New-Object Windows.Forms.Button
$btnSearch.Text = 'Search'
$btnSearch.FlatStyle = 'Flat'
$btnSearch.Margin = '6,8,10,6'
$btnSearch.BackColor = $Theme.Ok
$btnSearch.ForeColor = $Theme.Text
$btnSearch.FlatAppearance.BorderColor = $Theme.Accent

$null = $top.Controls.Add($lblFolder,0,0)
$null = $top.Controls.Add($tbFolder,1,0)
$null = $top.Controls.Add($btnBrowse,2,0)
$null = $top.Controls.Add($lblExt,3,0)
$null = $top.Controls.Add($tbExt,4,0)
$null = $top.Controls.Add($btnSearch,5,0)
$root.Controls.Add($top,0,0)

#------------- File list -------------
$lvFiles = New-Object Windows.Forms.ListView
$lvFiles.View = 'Details'
$lvFiles.CheckBoxes = $true
$lvFiles.FullRowSelect = $true
$lvFiles.GridLines = $true
$lvFiles.HideSelection = $false
$lvFiles.Dock = 'Fill'
$lvFiles.BackColor = $Theme.Surface
$lvFiles.ForeColor = $Theme.Text
$lvFiles.BorderStyle = 'FixedSingle'
$lvFiles.Columns.Add('Name', 360)    | Out-Null
$lvFiles.Columns.Add('Folder', 600)  | Out-Null

# Reduce flicker
$lvFiles.GetType().GetProperty('DoubleBuffered',[Reflection.BindingFlags]'NonPublic,Instance').SetValue($lvFiles,$true,$null)

$root.Controls.Add($lvFiles,0,1)

#------------- Actions bar (target + buttons) -------------
$actions = New-Object Windows.Forms.TableLayoutPanel
$actions.Dock = 'Top'
$actions.BackColor = $Theme.Bg
$actions.AutoSize = $true
# Ensure the layout reserves a column for each control
$actions.ColumnCount = 10
# Columns: TargetLbl | TargetBox | TargetBrowse | spacer | Copy | Move | Rename | Delete | Zip | Backup
$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))            | Out-Null
$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',60)))          | Out-Null
$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))            | Out-Null
$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',5)))           | Out-Null
for ($i=0;$i -lt 6;$i++){ $actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize'))) | Out-Null }

$lblTarget = New-Object Windows.Forms.Label
$lblTarget.Text = 'Target'
$lblTarget.AutoSize = $true
$lblTarget.Margin = '10,8,6,8'
$lblTarget.ForeColor = $Theme.Text

$tbTarget = New-Object Windows.Forms.TextBox
$tbTarget.Text = $cfg.TargetFolder
$tbTarget.Dock = 'Fill'
$tbTarget.Margin = '0,6,6,6'
$tbTarget.BackColor = $Theme.Surface
$tbTarget.ForeColor = $Theme.Text
$tbTarget.BorderStyle = 'FixedSingle'

$btnTarget = New-Object Windows.Forms.Button
$btnTarget.Text = '...'
$btnTarget.FlatStyle = 'Flat'
$btnTarget.Margin = '0,6,6,6'
$btnTarget.BackColor = $Theme.Surface
$btnTarget.ForeColor = $Theme.Text
$btnTarget.FlatAppearance.BorderColor = $Theme.Accent

function New-ActionButton([string]$text,[Drawing.Color]$bg,[Drawing.Color]$fg) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.FlatStyle = 'Flat'
    $b.Margin = '6,6,6,6'
    $b.BackColor = $bg
    $b.ForeColor = $fg
    $b.FlatAppearance.BorderColor = $Theme.Accent
    return $b
}

$btnCopy   = New-ActionButton 'Copy'     $Theme.Surface $Theme.Text
$btnMove   = New-ActionButton 'Move'     $Theme.Surface $Theme.Text
$btnRename = New-ActionButton 'Rename'   $Theme.Surface $Theme.Text
$btnDelete = New-ActionButton 'Delete'   $Theme.Danger  $Theme.Text
$btnZip    = New-ActionButton 'Zip'      $Theme.Warn    $Theme.Text
$btnBackup = New-ActionButton 'Backup'   $Theme.Surface $Theme.Text

$null = $actions.Controls.Add($lblTarget,0,0)
$null = $actions.Controls.Add($tbTarget,1,0)
$null = $actions.Controls.Add($btnTarget,2,0)
# spacer at col 3
$null = $actions.Controls.Add((New-Object Windows.Forms.Label),3,0)
$null = $actions.Controls.Add($btnCopy,4,0)
$null = $actions.Controls.Add($btnMove,5,0)
$null = $actions.Controls.Add($btnRename,6,0)
$null = $actions.Controls.Add($btnDelete,7,0)
$null = $actions.Controls.Add($btnZip,8,0)
$null = $actions.Controls.Add($btnBackup,9,0) | Out-Null

# Secondary actions (select all/none)
$secondary = New-Object Windows.Forms.FlowLayoutPanel
$secondary.FlowDirection = 'LeftToRight'
$secondary.WrapContents = $false
$secondary.Dock = 'Top'
$secondary.BackColor = $Theme.Bg
$secondary.AutoSize = $true
$btnSelectAll = New-ActionButton 'Select All'  $Theme.Surface $Theme.Text
$btnSelectNone= New-ActionButton 'Select None' $Theme.Surface $Theme.Text
$secondary.Controls.AddRange(@($btnSelectAll,$btnSelectNone))

$actionsPanel = New-Object Windows.Forms.Panel
$actionsPanel.Dock = 'Top'
$actionsPanel.BackColor = $Theme.Bg
$actionsPanel.AutoSize = $true
$actionsPanel.Controls.Add($actions)
$actionsPanel.Controls.Add($secondary)

$root.Controls.Add($actionsPanel,0,2)

#------------- Status bar -------------
$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Height = 32
$statusPanel.Dock = 'Bottom'
$statusPanel.BackColor = $Theme.Panel
$statusPanel.Padding = '8,4,8,4'

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.ForeColor = $Theme.TextMuted
$lblStatus.Text = 'Ready'

$progressBar = New-Object Windows.Forms.ProgressBar
$progressBar.Width = 240
$progressBar.Height = 18
$progressBar.Style = 'Continuous'
$progressBar.Anchor = 'Right'
$progressBar.Visible = $false
$progressBar.Location = New-Object Drawing.Point(($form.ClientSize.Width - $progressBar.Width - 16),6)
$statusPanel.Add_Resize({
    $progressBar.Location = New-Object Drawing.Point(($statusPanel.Width - $progressBar.Width - 12),6)
})

$statusPanel.Controls.Add($lblStatus)
$statusPanel.Controls.Add($progressBar)
$root.Controls.Add($statusPanel,0,3)

#------------- Helpers -------------
function Show-Status([string]$text) {
    $lblStatus.Text = $text
    Write-Log -Message $text
}

function Get-SelectedPaths {
    $lvFiles.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }
}

function Select-Folder([string]$initial) {
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($initial -and (Test-Path -LiteralPath $initial)) { $fbd.SelectedPath = $initial }
    return (if ($fbd.ShowDialog() -eq 'OK') { $fbd.SelectedPath } else { $null })
}

function Get-FileList {
    $lvFiles.BeginUpdate()
    try {
        $lvFiles.Items.Clear()
        $folder = $tbFolder.Text
        if (-not (Test-Path -LiteralPath $folder)) { Show-Status 'Folder not found'; return }
        $ext = $tbExt.Text.Trim().TrimStart('.')
        $pattern = if ($ext) { "*.$ext" } else { '*' }
        Get-ChildItem -LiteralPath $folder -Filter $pattern -File -ErrorAction Stop | ForEach-Object {
            $item = New-Object Windows.Forms.ListViewItem($_.Name)
            [void]$item.SubItems.Add($_.DirectoryName)
            $item.Tag = $_.FullName
            $lvFiles.Items.Add($item) | Out-Null
        }
        Show-Status ("{0} files found" -f $lvFiles.Items.Count)
    } catch {
        Show-Status ("Error reading folder: {0}" -f $_.Exception.Message)
        Write-Log -Level 'ERROR' -Message $_.Exception.ToString()
    } finally {
        $lvFiles.EndUpdate()
    }
}

function With-Progress([int]$count,[scriptblock]$body){
    if ($count -le 0) { & $body; return }
    $progressBar.Visible = $true
    $progressBar.Minimum = 0
    $progressBar.Maximum = $count
    $progressBar.Value = 0
    try { & $body } finally { $progressBar.Visible = $false }
}

#------------- Wire events -------------
$btnBrowse.Add_Click({
    $sel = Select-Folder -initial $tbFolder.Text
    if ($sel) { $tbFolder.Text = $sel }
})
$btnTarget.Add_Click({
    $sel = Select-Folder -initial $tbTarget.Text
    if ($sel) { $tbTarget.Text = $sel }
})

$btnSearch.Add_Click({ Get-FileList })
$tbFolder.Add_TextChanged({ Get-FileList })
$tbExt.Add_TextChanged({ Get-FileList })

$btnSelectAll.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $true } })
$btnSelectNone.Add_Click({ $lvFiles.Items | ForEach-Object { $_.Checked = $false } })

# Actions
$btnCopy.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path -LiteralPath $dest)) { Show-Status 'Target not valid'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { Show-Status 'No file selected'; return }

    With-Progress $sel.Count {
        foreach ($p in $sel) {
            try {
                Copy-Item -LiteralPath $p -Destination $dest -Force -ErrorAction Stop
                Write-Log -Message ("COPY {0} -> {1}" -f $p,$dest)
            } catch {
                Write-Log -Level 'ERROR' -Message ("Copy failed for {0}: {1}" -f $p,$_.Exception.Message)
            }
            $progressBar.Value++
        }
    }
    Show-Status 'Copy done'
    Get-FileList
})

$btnMove.Add_Click({
    $dest = $tbTarget.Text
    if (-not (Test-Path -LiteralPath $dest)) { Show-Status 'Target not valid'; return }
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { Show-Status 'No file selected'; return }

    With-Progress $sel.Count {
        foreach ($p in $sel) {
            try {
                Move-Item -LiteralPath $p -Destination $dest -Force -ErrorAction Stop
                Write-Log -Message ("MOVE {0} -> {1}" -f $p,$dest)
            } catch {
                Write-Log -Level 'ERROR' -Message ("Move failed for {0}: {1}" -f $p,$_.Exception.Message)
            }
            $progressBar.Value++
        }
    }
    Show-Status 'Move done'
    Get-FileList
})

$btnRename.Add_Click({
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { Show-Status 'No file selected'; return }

    foreach ($p in $sel) {
        $old = [IO.Path]::GetFileName($p)
        $new = [Microsoft.VisualBasic.Interaction]::InputBox('New name:','Rename',$old)
        if ([string]::IsNullOrWhiteSpace($new) -or $new -eq $old) { continue }
        $dir = [IO.Path]::GetDirectoryName($p)
        try {
            Rename-Item -LiteralPath $p -NewName $new -ErrorAction Stop
            Write-Log -Message ("RENAME {0} -> {1}" -f $p,(Join-Path $dir $new))
        } catch {
            Write-Log -Level 'ERROR' -Message ("Rename failed for {0}: {1}" -f $p,$_.Exception.Message)
        }
    }
    Get-FileList
})

$btnDelete.Add_Click({
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { Show-Status 'No file selected'; return }
    $confirm = [System.Windows.Forms.MessageBox]::Show('Delete selected files?','Confirm Delete','YesNo','Warning')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    With-Progress $sel.Count {
        foreach ($p in $sel) {
            try {
                Remove-Item -LiteralPath $p -Force -ErrorAction Stop
                Write-Log -Message ("DELETE {0}" -f $p)
            } catch {
                Write-Log -Level 'ERROR' -Message ("Delete failed for {0}: {1}" -f $p,$_.Exception.Message)
            }
            $progressBar.Value++
        }
    }
    Show-Status 'Delete done'
    Get-FileList
})

$btnZip.Add_Click({
    $paths = @(Get-SelectedPaths)
    if (-not $paths) { Show-Status 'No file selected'; return }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'ZIP files (*.zip)|*.zip'
    $sfd.FileName = [IO.Path]::GetFileName($cfg.ZipPath)
    if ($sfd.ShowDialog() -ne 'OK') { return }
    $zip = $sfd.FileName

    if (Test-Path -LiteralPath $zip) {
        try { Remove-Item -LiteralPath $zip -Force -ErrorAction Stop } catch {
            Show-Status ("Cannot overwrite: {0}" -f $_.Exception.Message); return
        }
    }

    With-Progress $paths.Count {
        $zipStream = [System.IO.File]::Open($zip,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
        try {
            $archive = New-Object System.IO.Compression.ZipArchive($zipStream,[System.IO.Compression.ZipArchiveMode]::Create,$false)
            try {
                foreach ($p in $paths) {
                    $entry = $archive.CreateEntry([IO.Path]::GetFileName($p))
                    $es = $entry.Open()
                    try {
                        $fs = [System.IO.File]::OpenRead($p)
                        try { $fs.CopyTo($es) } finally { $fs.Dispose() }
                    } finally { $es.Dispose() }
                    $progressBar.Value++
                }
            } finally { $archive.Dispose() }
        } finally { $zipStream.Dispose() }
    }
    Write-Log -Message ("ZIP -> {0}" -f $zip)
    Show-Status 'Zip done'
})

$btnBackup.Add_Click({
    $sel = @(Get-SelectedPaths)
    if (-not $sel) { Show-Status 'No file selected'; return }
    $target = Select-Folder -initial $cfg.BackupFolder
    if (-not $target) { return }

    With-Progress $sel.Count {
        foreach ($p in $sel) {
            try {
                Copy-Item -LiteralPath $p -Destination $target -Force -ErrorAction Stop
                Write-Log -Message ("BACKUP {0} -> {1}" -f $p,$target)
            } catch {
                Write-Log -Level 'ERROR' -Message ("Backup failed for {0}: {1}" -f $p,$_.Exception.Message)
            }
            $progressBar.Value++
        }
    }
    $cfg.BackupFolder = $target
    Show-Status 'Backup done'
})

#------------- Persist on close -------------
$form.Add_FormClosing({
    try {
        $cfg.SourceFolder = $tbFolder.Text
        $cfg.TargetFolder = $tbTarget.Text
        $cfg.Width        = $form.Width
        $cfg.Height       = $form.Height
        Save-Config -Cfg $cfg
    } catch { }
})

#------------- Initial load -------------
Get-FileList
[Windows.Forms.Application]::Run($form)
