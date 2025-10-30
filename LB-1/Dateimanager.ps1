#Requires -Version 7.0
<#
    Dateimanager.ps1 (Fixed)
    PowerShell-Dateimanager mit WPF-GUI (Dark-Theme).
#>

###############################################################################
# Helper: Ensure required assemblies
###############################################################################
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase | Out-Null
## System.Drawing and System.Web are not needed or not supported in PowerShell 7 for this script

# ScriptRoot (robust)
$Script:ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Script:ScriptRoot -PathType Container)) { $Script:ScriptRoot = (Get-Location).Path }

###############################################################################
# Constants & Globals
###############################################################################
$Script:AppName = "Dateimanager"
$Script:Version = "1.0.2"
$Script:SearchResults = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$Script:ActionStamp = $null

###############################################################################
# Paths and minimal HTML logging
###############################################################################
$LogHtmlPath = Join-Path $Script:ScriptRoot 'log.html'

function Initialize-LogHtml {
    if (Test-Path -LiteralPath $LogHtmlPath) { return }
    $header = @(
        '<!DOCTYPE html>'
        '<html lang="de"><head><meta charset="utf-8"/><title>Log</title>'
        '<style>body{font-family:Segoe UI,Arial;margin:16px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:6px 8px}thead th{background:#f5f5f5}</style>'
        '</head><body>'
        '<h2>Aktivitätslog</h2>'
        '<table><thead><tr><th>Zeit</th><th>Aktion</th><th>Details</th><th>Status</th></tr></thead><tbody>'
        '</tbody></table></body></html>'
    )
    Set-Content -Path $LogHtmlPath -Value ($header -join "`n") -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Write-LogHtml {
    param([string]$Level='INFO',[string]$Action,[string]$Details='')
    Initialize-LogHtml
    if (-not (Test-Path -LiteralPath $LogHtmlPath)) { return }
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $safe = $Details
    try { $safe = [System.Net.WebUtility]::HtmlEncode($Details) } catch {}
    $row  = "<tr><td>$ts</td><td>$Action</td><td>$safe</td><td>$Level</td></tr>"
    try {
        $html = Get-Content -LiteralPath $LogHtmlPath -Raw -Encoding UTF8
        $out  = $html -replace '</tbody>', "$row`n</tbody>"
        Set-Content -Path $LogHtmlPath -Value $out -Encoding UTF8
    } catch {}
}

###############################################################################
# Basic defaults (no config persistence)
###############################################################################
function Get-Defaults {
    return [pscustomobject]@{
        RootPath    = "$HOME"
        Pattern     = "*"
        IncludeSub  = $true
        Destination = "$HOME\Desktop"
        BackupRoot  = "$HOME\Backups"
        ArchivePath = "$HOME\Desktop\Archiv.zip"
    }
}

###############################################################################
# File Ops
###############################################################################
# Sucht nach Dateien basierend auf RootPath und Pattern.
# Optional könnten (derzeit deaktivierte) Filter wie Größe/Datum ergänzt werden.
function Get-MatchingFiles {
    param(
        [string]$RootPath,
        [string]$Pattern = "*",
        [bool]$Recurse = $true,
        [int]$MinSizeKB = 0,
        [int]$MaxSizeKB = 0,
        [string]$ModifiedAfter = "",
        [string]$ModifiedBefore = ""
    )

    if (-not (Test-Path $RootPath)) {
        Update-Status "Pfad nicht gefunden: $RootPath"
        return @()
    }

    try {
        $all = Get-ChildItem -LiteralPath $RootPath -File -Recurse:$Recurse -ErrorAction Stop -Filter $Pattern

        if ($MinSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -ge ($MinSizeKB * 1KB) } }
        if ($MaxSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -le ($MaxSizeKB * 1KB) } }
        if ($ModifiedAfter)  { $after  = Get-Date $ModifiedAfter;  $all = $all | Where-Object { $_.LastWriteTime -ge $after } }
        if ($ModifiedBefore) { $before = Get-Date $ModifiedBefore; $all = $all | Where-Object { $_.LastWriteTime -le $before } }

        $files = $all | Select-Object FullName, Name, DirectoryName, Length, LastWriteTime
        Update-Status ("Gefunden: {0} – '{1}'" -f $files.Count, $Pattern)
        return ,$files
    } catch {
        Update-Status "Fehler bei Suche: $($_.Exception.Message)"
        return @()
    }
}

# Kopiert oder verschiebt eine Liste von Dateien in ein Zielverzeichnis.
# Bei Fehlern wird ein Log-Eintrag mit Level ERROR erzeugt.
function Copy-Or-MoveFiles {
    param(
        [array]$Items,
        [string]$Destination,
        [switch]$Move
    )
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    foreach ($it in $Items) {
        try {
            $target = Join-Path $Destination $it.Name
            if ($Move.IsPresent) {
                Move-Item -LiteralPath $it.FullName -Destination $target -Force
            } else {
                Copy-Item -LiteralPath $it.FullName -Destination $target -Force
            }
        } catch {
            Update-Status ("Fehler: {0}" -f $_.Exception.Message)
        }
    }
}

# Erstellt ein ZIP-Archiv aus den ausgewählten Dateien.
function New-Archive {
    param(
        [array]$Items,
        [string]$ArchivePath
    )
    try {
        $stamp = Get-ActionStamp
        # Zielpfad ermitteln: Falls Verzeichnis -> Archiv_<stamp>.zip darin; sonst Dateiname mit _<stamp>.zip
        $raw = $ArchivePath
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = Join-Path $HOME ("Archiv_{0}.zip" -f $stamp) }
        $outPath = $null
        if (Test-Path -LiteralPath $raw -PathType Container) {
            $outPath = Join-Path $raw ("Archiv_{0}.zip" -f $stamp)
        } else {
            $dir = Split-Path -Parent $raw
            $name = Split-Path -Leaf $raw
            if (-not $name.ToLower().EndsWith('.zip')) { $name = "$name.zip" }
            $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
            $outName = "{0}_{1}.zip" -f $base, $stamp
            if (-not $dir) { $dir = (Get-Location).Path }
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $outPath = Join-Path $dir $outName
        }

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::GetGuid().ToString())
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        foreach ($it in $Items) {
            Copy-Item -LiteralPath $it.FullName -Destination (Join-Path $tmp $it.Name) -Force
        }
        if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $outPath -Force
        Remove-Item -LiteralPath $tmp -Recurse -Force
        Update-Status ("Archiv erstellt: {0}" -f $outPath)
    } catch {
        Update-Status ("Fehler beim Archivieren: {0}" -f $_.Exception.Message)
    }
}

# Erstellt einen Zeitstempel-Ordner und kopiert die ausgewählten Dateien hinein.
function New-Backup {
    param(
        [array]$Items,
        [string]$BackupRoot
    )
    try {
        if (-not $Items -or $Items.Count -eq 0) { Update-Status 'Keine Dateien übergeben'; return }
        if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
            $BackupRoot = Join-Path $HOME 'Backups'
        }
        if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
            } catch {
                throw "BackupRoot kann nicht erstellt werden: $BackupRoot - $($_.Exception.Message)"
            }
        }
    $stamp = Get-ActionStamp
        $dest = Join-Path $BackupRoot "Backup_$stamp"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $copied = 0
        foreach ($it in $Items) {
            try {
                $targetFile = Join-Path $dest $it.Name
                Copy-Item -LiteralPath $it.FullName -Destination $targetFile -Force -ErrorAction Stop
                $copied++
            } catch {
                Update-Status ("Fehler Backup: {0}" -f $_.Exception.Message)
            }
        }
        if ($copied -le 0) { Update-Status 'Keine Dateien kopiert' }
        return $dest
    } catch {
        Update-Status ("Fehler beim Backup: {0}" -f $_.Exception.Message)
    }
}

###############################################################################
# WPF UI
###############################################################################
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($Script:AppName) $($Script:Version)" Height="700" Width="1100"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" Grid.Row="0">
            <Button x:Name="BtnSearch" Content="🔍 Suchen"/>
            <Button x:Name="BtnCopy" Content="📋 Kopieren"/>
            <Button x:Name="BtnMove" Content="✂️ Verschieben"/>
            <Button x:Name="BtnArchive" Content="🗜️ Archiv (ZIP)"/>
            <Button x:Name="BtnBackup" Content="🛡️ Backup"/>
        </StackPanel>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="360"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
                <GroupBox Header="Quelle &amp; Filter">
                    <StackPanel>
                        <TextBlock Text="Wurzelpfad"/>
                        <TextBox x:Name="TbRoot"/>
                        <TextBlock Text="Muster (z.B. *.pdf)"/>
                        <TextBox x:Name="TbPattern"/>
                        <CheckBox x:Name="CbSub" Content="Unterordner einbeziehen"/>
                            <!-- Date and size filters removed -->
                    </StackPanel>
                </GroupBox>

                <GroupBox Header="Ziel / Aktionen">
                    <StackPanel>
                        <TextBlock Text="Zielordner (Kopieren/Verschieben)"/>
                        <TextBox x:Name="TbDest"/>
                        <TextBlock Text="Backup Basisordner"/>
                        <TextBox x:Name="TbBackupRoot"/>
                        <TextBlock Text="Archiv-Ziel (ZIP)"/>
                        <TextBox x:Name="TbArchive"/>
                    </StackPanel>
                </GroupBox>
            </StackPanel>

            <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <DataGrid x:Name="GridResults" Grid.Row="0" AutoGenerateColumns="False" SelectionMode="Extended" CanUserAddRows="False">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="220"/>
                            <DataGridTextColumn Header="Pfad" Binding="{Binding FullName}" Width="*"/>
                            <DataGridTextColumn Header="Ordner" Binding="{Binding DirectoryName}" Width="200"/>
                            <DataGridTextColumn Header="Groesse" Binding="{Binding Length}" Width="100"/>
                            <DataGridTextColumn Header="Geaendert" Binding="{Binding LastWriteTime}" Width="160"/>
                        </DataGrid.Columns>
                        <DataGrid.GridLinesVisibility>Horizontal</DataGrid.GridLinesVisibility>
                </DataGrid>

                <TextBlock Grid.Row="1" Text="Tipp: Mehrfachauswahl mit Strg/Shift. Aktionen betreffen markierte Zeilen; ohne Auswahl wirken alle Aktionen auf alle Treffer." Margin="6" Foreground="#9ca3af"/>
            </Grid>
        </Grid>

        <DockPanel Grid.Row="2" LastChildFill="False">
            <TextBlock x:Name="StatusText" Text="Bereit." Margin="6"/>
            <TextBlock Margin="6">
                <Hyperlink x:Name="LinkLog">Log öffnen</Hyperlink>
            </TextBlock>
        </DockPanel>
    </Grid>
</Window>
"@

[xml]$xml = $xaml
$reader = (New-Object System.Xml.XmlNodeReader $xml)
$window = [Windows.Markup.XamlReader]::Load($reader)

###############################################################################
# Bind Controls
###############################################################################
$BtnSearch    = $window.FindName('BtnSearch')
$BtnCopy      = $window.FindName('BtnCopy')
$BtnMove      = $window.FindName('BtnMove')
$BtnArchive   = $window.FindName('BtnArchive')
$BtnBackup    = $window.FindName('BtnBackup')

$TbRoot       = $window.FindName('TbRoot')
$TbPattern    = $window.FindName('TbPattern')
$CbSub        = $window.FindName('CbSub')
## Removed Min/Max KB and Date controls

$TbDest       = $window.FindName('TbDest')
$TbBackupRoot = $window.FindName('TbBackupRoot')
$TbArchive    = $window.FindName('TbArchive')

$GridResults  = $window.FindName('GridResults')
$StatusText   = $window.FindName('StatusText')
$LinkLog      = $window.FindName('LinkLog')

$GridResults.ItemsSource = $Script:SearchResults

###############################################################################
# Load initial config
###############################################################################
$defaults = Get-Defaults
$TbRoot.Text       = $defaults.RootPath
$TbPattern.Text    = $defaults.Pattern
$CbSub.IsChecked   = [bool]$defaults.IncludeSub
$TbDest.Text       = $defaults.Destination
$TbBackupRoot.Text = $defaults.BackupRoot
$TbArchive.Text    = $defaults.ArchivePath

###############################################################################
# UI helpers
###############################################################################
# Ermittelt die aktuelle Auswahl im DataGrid.
# Wenn keine Auswahl getroffen wurde, werden alle angezeigten Treffer verwendet.
function Get-CurrentSelection {
    $sel = @()
    foreach ($item in $GridResults.SelectedItems) { $sel += $item }
    if ($sel.Count -eq 0) { $sel = @($Script:SearchResults) }
    return $sel
}

# Setzt die Statuszeile unten im Fenster.
function Update-Status {
    param([string]$msg)
    $StatusText.Text = $msg
}

# Gemeinsamer Zeitstempel für Backup/Archiv in einer Session/Phase
function Get-ActionStamp {
    if (-not $Script:ActionStamp) {
        $Script:ActionStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    }
    return $Script:ActionStamp
}

function Reset-ActionStamp {
    $Script:ActionStamp = $null
}

# Einfacher Modus: blendet Preset/Logs-Tasten und Tipp aus
function Toggle-SimpleUI {
    param([bool]$on)
    $vis = if ($on) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $BtnLoadCfg.Visibility = $vis
    $BtnSaveCfg.Visibility = $vis
    $BtnOpenLogs.Visibility = $vis
    if ($TxtTip) { $TxtTip.Visibility = if ($on) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible } }
}

###############################################################################
# Wire events
###############################################################################
## Preset/Log-Funktionen entfernt

$BtnSearch.Add_Click({
    $Script:SearchResults.Clear()
    Reset-ActionStamp

    $files = Get-MatchingFiles -RootPath $TbRoot.Text -Pattern $TbPattern.Text -Recurse ([bool]$CbSub.IsChecked)

    foreach ($f in $files) { [void]$Script:SearchResults.Add($f) }
    Update-Status ("Treffer: {0}" -f $Script:SearchResults.Count)
    Write-LogHtml -Level 'OK' -Action 'Suche' -Details ("Treffer: {0} – '{1}' in {2}" -f $Script:SearchResults.Count, $TbPattern.Text, $TbRoot.Text)
})

$BtnCopy.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    Copy-Or-MoveFiles -Items $sel -Destination $TbDest.Text
    Update-Status "Kopieren abgeschlossen."
    Write-LogHtml -Level 'OK' -Action 'Kopieren' -Details ("{0} Dateien -> {1}" -f $sel.Count, $TbDest.Text)
})

$BtnMove.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    Copy-Or-MoveFiles -Items $sel -Destination $TbDest.Text -Move
    Update-Status "Verschieben abgeschlossen."
    Write-LogHtml -Level 'OK' -Action 'Verschieben' -Details ("{0} Dateien -> {1}" -f $sel.Count, $TbDest.Text)
})

$BtnArchive.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    New-Archive -Items $sel -ArchivePath $TbArchive.Text
    Update-Status "Archiv erstellt."
    Write-LogHtml -Level 'OK' -Action 'Archiv' -Details ("{0} Dateien -> {1}" -f $sel.Count, $TbArchive.Text)
})

$BtnBackup.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    $dest = New-Backup -Items $sel -BackupRoot $TbBackupRoot.Text
    if ($dest) { Update-Status ("Backup erstellt: {0}" -f $dest) }
    if ($dest) { Write-LogHtml -Level 'OK' -Action 'Backup' -Details $dest }
})

# Init and log link
Initialize-LogHtml
Write-LogHtml -Level 'INFO' -Action 'Start' -Details ("Root={0}" -f $Script:ScriptRoot)
$LinkLog.Add_Click({ Initialize-LogHtml; Start-Process -FilePath $LogHtmlPath })

## Simple Mode entfernt (nur Basis-GUI bleibt aktiv)

###############################################################################
# Run
###############################################################################

## Closing-Log-Dialog entfernt
$null = $window.ShowDialog()
