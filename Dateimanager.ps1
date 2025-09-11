<#
    Dateimanager.ps1
    Ein moderner PowerShell-Dateimanager mit WPF-GUI (Dark-Theme).
    Funktionen: Dateien suchen, auswählen, kopieren/verschieben, zippen/archivieren, Backup erstellen,
    Konfiguration (Presets) laden/speichern, HTML-Loganzeige.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$(Split-Path -Parent $PSCommandPath)\config.json",
    [string]$LogHtmlPath = "$(Split-Path -Parent $PSCommandPath)\log.html"
)

###############################################################################
# Helper: Ensure required assemblies
###############################################################################
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing | Out-Null

###############################################################################
# Constants & Globals
###############################################################################
$Script:AppName = "Dateimanager"
$Script:Version = "1.0.0"
$Script:SearchResults = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$Script:LogLock = New-Object Object

###############################################################################
# Logging (HTML)
###############################################################################
function Initialize-LogHtml {
    if (-not (Test-Path $LogHtmlPath)) {
        $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$($Script:AppName) – Log</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #0f1115;
    --card: #151823;
    --text: #e5e7eb;
    --muted: #9ca3af;
    --accent: #6ee7b7;
    --accent-2: #60a5fa;
    --danger: #f87171;
    --warn: #fbbf24;
    --ok: #34d399;
    --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace;
    --round: 14px;
    --shadow: 0 10px 30px rgba(0,0,0,.35);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: radial-gradient(1200px 800px at 10% 10%, #0d0f14 0%, #0f1115 40%, #0a0c10 100%);
    color: var(--text);
    font: 15px/1.5 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, "Helvetica Neue", Arial;
    padding: 32px;
  }
  header {
    display:flex; align-items:center; justify-content:space-between; margin-bottom: 20px;
  }
  h1 { font-size: 22px; margin: 0; letter-spacing:.3px; }
  .meta { color: var(--muted); font-size: 13px; }
  .card {
    background: linear-gradient(180deg, rgba(255,255,255,.03), rgba(255,255,255,.01));
    border: 1px solid rgba(255,255,255,.08);
    border-radius: var(--round);
    box-shadow: var(--shadow);
    padding: 18px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    border-spacing: 0;
    font-family: var(--mono);
    font-size: 13px;
  }
  thead th {
    text-align: left;
    color: var(--muted);
    font-weight: 600;
    padding: 10px 8px;
    border-bottom: 1px solid rgba(255,255,255,.08);
    position: sticky;
    top: 0;
    background: rgba(21,24,35,.8);
    backdrop-filter: blur(6px);
  }
  tbody td {
    padding: 10px 8px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    vertical-align: top;
  }
  tr:hover { background: rgba(255,255,255,.03); }
  .tag {
    display:inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 12px;
    border: 1px solid rgba(255,255,255,.12);
  }
  .level-info { color: var(--accent-2); border-color: rgba(96,165,250,.3); }
  .level-ok { color: var(--ok); border-color: rgba(52,211,153,.3); }
  .level-warn { color: var(--warn); border-color: rgba(251,191,36,.3); }
  .level-error { color: var(--danger); border-color: rgba(248,113,113,.3); }
  .path{ color:#d1d5db }
  .time{ color:#9ca3af }
</style>
</head>
<body>
  <header>
    <h1>$($Script:AppName) – Aktivitätslog</h1>
    <div class="meta">Version $($Script:Version)</div>
  </header>
  <div class="card">
    <table id="log">
      <thead>
        <tr>
          <th>Zeit</th>
          <th>Aktion</th>
          <th>Details</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
      </tbody>
    </table>
  </div>
  <script>
    // No dynamic backend. Entries are appended by PowerShell directly.
  </script>
</body>
</html>
"@
        Set-Content -Path $LogHtmlPath -Value $html -Encoding UTF8
    }
}

function Write-LogHtml {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR")]
        [string]$Level = "INFO",
        [string]$Action,
        [string]$Details
    )
    Initialize-LogHtml
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $levelClass = switch ($Level) {
        "INFO"  { "level-info" }
        "OK"    { "level-ok" }
        "WARN"  { "level-warn" }
        "ERROR" { "level-error" }
    }
    $row = "<tr><td class='time'>$ts</td><td>$Action</td><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($Details))</td><td><span class='tag $levelClass'>$Level</span></td></tr>"
    # Insert before closing </tbody>
    $content = Get-Content -LiteralPath $LogHtmlPath -Raw -Encoding UTF8
    $updated = $content -replace '</tbody>', "$row`n      </tbody>"
    $null = [System.Threading.Monitor]::Enter($Script:LogLock)
    try {
        Set-Content -Path $LogHtmlPath -Value $updated -Encoding UTF8
    } finally {
        [System.Threading.Monitor]::Exit($Script:LogLock)
    }
}

###############################################################################
# Config
###############################################################################
function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            return $json
        } catch {
            Write-LogHtml -Level "ERROR" -Action "Config laden" -Details "Ungültige JSON-Datei: $ConfigPath - $($_.Exception.Message)"
        }
    }
    # Defaults
    return [pscustomobject]@{
        RootPath       = "$HOME"
        Pattern        = "*"
        IncludeSub     = $true
        Destination    = "$HOME\Desktop"
        BackupRoot     = "$HOME\Backups"
        ArchivePath    = "$HOME\Desktop\Archiv.zip"
        MinSizeKB      = 0
        MaxSizeKB      = 0
        ModifiedAfter  = ""
        ModifiedBefore = ""
        UseRegex       = $false
    }
}

function Save-Config {
    param([psobject]$Cfg)
    try {
        $Cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-LogHtml -Level "OK" -Action "Config speichern" -Details $ConfigPath
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Config speichern" -Details $_.Exception.Message
    }
}

###############################################################################
# File Ops
###############################################################################
function Get-MatchingFiles {
    param(
        [string]$RootPath,
        [string]$Pattern = "*",
        [bool]$Recurse = $true,
        [int]$MinSizeKB = 0,
        [int]$MaxSizeKB = 0,
        [string]$ModifiedAfter = "",
        [string]$ModifiedBefore = "",
        [bool]$UseRegex = $false
    )
    $files = @()
    if (-not (Test-Path $RootPath)) {
        Write-LogHtml -Level "ERROR" -Action "Suche" -Details "Pfad nicht gefunden: $RootPath"
        return @()
    }

    $searchOpt = if ($Recurse) { "-Recurse" } else { "" }
    try {
        $all = Get-ChildItem -LiteralPath $RootPath -File -ErrorAction Stop @{
            Recurse = $Recurse
            Filter = if ($UseRegex) { $null } else { $Pattern }
        }
        if ($UseRegex) {
            $all = $all | Where-Object { $_.Name -match $Pattern }
        }
        if ($MinSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -ge ($MinSizeKB * 1KB) } }
        if ($MaxSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -le ($MaxSizeKB * 1KB) } }
        if ($ModifiedAfter) { $after = Get-Date $ModifiedAfter; $all = $all | Where-Object { $_.LastWriteTime -ge $after } }
        if ($ModifiedBefore) { $before = Get-Date $ModifiedBefore; $all = $all | Where-Object { $_.LastWriteTime -le $before } }

        $files = $all | Select-Object FullName, Name, DirectoryName, Length, LastWriteTime
        Write-LogHtml -Level "OK" -Action "Suche" -Details "Gefunden: $($files.Count) – '$Pattern' in $RootPath"
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Suche" -Details $_.Exception.Message
    }
    return $files
}

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
            if ($Move) {
                Move-Item -LiteralPath $it.FullName -Destination $target -Force
                Write-LogHtml -Level "OK" -Action "Verschieben" -Details "$($it.FullName) -> $target"
            } else {
                Copy-Item -LiteralPath $it.FullName -Destination $target -Force
                Write-LogHtml -Level "OK" -Action "Kopieren" -Details "$($it.FullName) -> $target"
            }
        } catch {
            Write-LogHtml -Level "ERROR" -Action ($Move ? "Verschieben" : "Kopieren") -Details "$($it.FullName): $($_.Exception.Message)"
        }
    }
}

function Create-Archive {
    param(
        [array]$Items,
        [string]$ArchivePath
    )
    try {
        $tmpDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())) -Force
        foreach ($it in $Items) {
            Copy-Item -LiteralPath $it.FullName -Destination (Join-Path $tmpDir $it.Name) -Force
        }
        if (Test-Path $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
        Compress-Archive -Path (Join-Path $tmpDir "*") -DestinationPath $ArchivePath -Force
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
        Write-LogHtml -Level "OK" -Action "Archiv erstellen" -Details $ArchivePath
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Archiv erstellen" -Details $_.Exception.Message
    }
}

function Create-Backup {
    param(
        [array]$Items,
        [string]$BackupRoot
    )
    try {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $dest = Join-Path $BackupRoot "Backup_$stamp"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        foreach ($it in $Items) {
            Copy-Item -LiteralPath $it.FullName -Destination (Join-Path $dest $it.Name) -Force
        }
        Write-LogHtml -Level "OK" -Action "Backup" -Details $dest
        return $dest
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Backup" -Details $_.Exception.Message
    }
}

###############################################################################
# WPF UI
###############################################################################
# XAML layout with dark aesthetics
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($Script:AppName) $($Script:Version)" Height="700" Width="1100"
        WindowStartupLocation="CenterScreen"
        Background="#0f1115" Foreground="#e5e7eb" FontFamily="Segoe UI">
    <Window.Resources>
        <SolidColorBrush x:Key="CardBg" Color="#151823"/>
        <SolidColorBrush x:Key="Accent" Color="#60a5fa"/>
        <SolidColorBrush x:Key="Accent2" Color="#6ee7b7"/>
        <Style TargetType="Button">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Background" Value="#1f2937"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border CornerRadius="10" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect BlurRadius="15" ShadowDepth="0" Opacity="0.25"/>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="BorderBrush" Value="#374151"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="6"/>
        </Style>
        <Style TargetType="DatePicker">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Background" Value="#0f1115"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#222"/>
            <Setter Property="RowBackground" Value="#111"/>
            <Setter Property="AlternatingRowBackground" Value="#151823"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="8"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="Background" Value="{StaticResource CardBg}"/>
            <Setter Property="BorderBrush" Value="#283044"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type GroupBox}">
                        <Grid>
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12"/>
                            <Grid Margin="6">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Text="{TemplateBinding Header}" Foreground="#9ca3af" FontSize="13" Margin="4,0,0,8"/>
                                <ContentPresenter Grid.Row="1"/>
                            </Grid>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Top Controls -->
        <StackPanel Orientation="Horizontal" Grid.Row="0">
            <Button x:Name="BtnLoadCfg" Content="Preset laden"/>
            <Button x:Name="BtnSaveCfg" Content="Preset speichern"/>
            <Button x:Name="BtnOpenLogs" Content="Logs anzeigen"/>
            <TextBlock Text=" | " VerticalAlignment="Center" Margin="4"/>
            <Button x:Name="BtnSearch" Content="Suchen"/>
            <Button x:Name="BtnCopy" Content="Kopieren"/>
            <Button x:Name="BtnMove" Content="Verschieben"/>
            <Button x:Name="BtnArchive" Content="Archiv (ZIP)"/>
            <Button x:Name="BtnBackup" Content="Backup"/>
        </StackPanel>

        <!-- Middle -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="360"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left pane: filters -->
            <StackPanel Grid.Column="0">
                <GroupBox Header="Quelle &amp; Filter">
                    <StackPanel>
                        <TextBlock Text="Wurzelpfad"/>
                        <TextBox x:Name="TbRoot"/>
                        <TextBlock Text="Muster (z.B. *.pdf | Regex siehe unten)"/>
                        <TextBox x:Name="TbPattern"/>
                        <CheckBox x:Name="CbRegex" Content="Regex verwenden"/>
                        <CheckBox x:Name="CbSub" Content="Unterordner einbeziehen"/>
                        <StackPanel Orientation="Horizontal">
                            <StackPanel Width="160">
                                <TextBlock Text="Min Größe (KB)"/><TextBox x:Name="TbMinKB"/>
                            </StackPanel>
                            <StackPanel Width="160">
                                <TextBlock Text="Max Größe (KB)"/><TextBox x:Name="TbMaxKB"/>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <StackPanel Width="160">
                                <TextBlock Text="Geändert nach"/><DatePicker x:Name="DpAfter"/>
                            </StackPanel>
                            <StackPanel Width="160">
                                <TextBlock Text="Geändert vor"/><DatePicker x:Name="DpBefore"/>
                            </StackPanel>
                        </StackPanel>
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

            <!-- Right pane: results -->
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
                        <DataGridTextColumn Header="Größe" Binding="{Binding Length}" Width="100"/>
                        <DataGridTextColumn Header="Geändert" Binding="{Binding LastWriteTime}" Width="160"/>
                    </DataGrid.Columns>
                </DataGrid>

                <TextBlock Grid.Row="1" Text="Tipp: Mehrfachauswahl mit Strg/Shift. Aktionen betreffen markierte Zeilen; ohne Auswahl wirken sie auf alle Treffer." Margin="6" Foreground="#9ca3af"/>
            </Grid>
        </Grid>

        <!-- Footer -->
        <DockPanel Grid.Row="2">
            <TextBlock x:Name="StatusText" Text="Bereit." Margin="6" Foreground="#9ca3af"/>
        </DockPanel>
    </Grid>
</Window>
"@

# Parse XAML
[xml]$xml = $xaml
$reader = (New-Object System.Xml.XmlNodeReader $xml)
$window = [Windows.Markup.XamlReader]::Load($reader)

###############################################################################
# Bind Controls
###############################################################################
$BtnLoadCfg   = $window.FindName('BtnLoadCfg')
$BtnSaveCfg   = $window.FindName('BtnSaveCfg')
$BtnOpenLogs  = $window.FindName('BtnOpenLogs')
$BtnSearch    = $window.FindName('BtnSearch')
$BtnCopy      = $window.FindName('BtnCopy')
$BtnMove      = $window.FindName('BtnMove')
$BtnArchive   = $window.FindName('BtnArchive')
$BtnBackup    = $window.FindName('BtnBackup')

$TbRoot       = $window.FindName('TbRoot')
$TbPattern    = $window.FindName('TbPattern')
$CbRegex      = $window.FindName('CbRegex')
$CbSub        = $window.FindName('CbSub')
$TbMinKB      = $window.FindName('TbMinKB')
$TbMaxKB      = $window.FindName('TbMaxKB')
$DpAfter      = $window.FindName('DpAfter')
$DpBefore     = $window.FindName('DpBefore')

$TbDest       = $window.FindName('TbDest')
$TbBackupRoot = $window.FindName('TbBackupRoot')
$TbArchive    = $window.FindName('TbArchive')

$GridResults  = $window.FindName('GridResults')
$StatusText   = $window.FindName('StatusText')

$GridResults.ItemsSource = $Script:SearchResults

###############################################################################
# Load initial config
###############################################################################
$cfg = Load-Config
$TbRoot.Text       = $cfg.RootPath
$TbPattern.Text    = $cfg.Pattern
$CbSub.IsChecked   = [bool]$cfg.IncludeSub
$TbDest.Text       = $cfg.Destination
$TbBackupRoot.Text = $cfg.BackupRoot
$TbArchive.Text    = $cfg.ArchivePath
$TbMinKB.Text      = [string]$cfg.MinSizeKB
$TbMaxKB.Text      = [string]$cfg.MaxSizeKB
$CbRegex.IsChecked = [bool]$cfg.UseRegex
if ($cfg.ModifiedAfter)  { $DpAfter.SelectedDate  = [datetime]$cfg.ModifiedAfter }
if ($cfg.ModifiedBefore) { $DpBefore.SelectedDate = [datetime]$cfg.ModifiedBefore }

Initialize-LogHtml
Write-LogHtml -Level "INFO" -Action "Start" -Details "Anwendung gestartet"

###############################################################################
# UI helpers
###############################################################################
function Get-CurrentSelection {
    $sel = @()
    foreach ($item in $GridResults.SelectedItems) { $sel += $item }
    if ($sel.Count -eq 0) { $sel = @($Script:SearchResults) }
    return $sel
}

function Update-Status {
    param([string]$msg)
    $StatusText.Text = $msg
}

###############################################################################
# Wire events
###############################################################################
$BtnLoadCfg.Add_Click({
    $cfg = Load-Config
    $TbRoot.Text       = $cfg.RootPath
    $TbPattern.Text    = $cfg.Pattern
    $CbSub.IsChecked   = [bool]$cfg.IncludeSub
    $TbDest.Text       = $cfg.Destination
    $TbBackupRoot.Text = $cfg.BackupRoot
    $TbArchive.Text    = $cfg.ArchivePath
    $TbMinKB.Text      = [string]$cfg.MinSizeKB
    $TbMaxKB.Text      = [string]$cfg.MaxSizeKB
    $CbRegex.IsChecked = [bool]$cfg.UseRegex
    $DpAfter.SelectedDate  = if ($cfg.ModifiedAfter)  { [datetime]$cfg.ModifiedAfter } else { $null }
    $DpBefore.SelectedDate = if ($cfg.ModifiedBefore) { [datetime]$cfg.ModifiedBefore } else { $null }
    Update-Status "Preset geladen."
})

$BtnSaveCfg.Add_Click({
    $cfg = [pscustomobject]@{
        RootPath       = $TbRoot.Text
        Pattern        = $TbPattern.Text
        IncludeSub     = [bool]$CbSub.IsChecked
        Destination    = $TbDest.Text
        BackupRoot     = $TbBackupRoot.Text
        ArchivePath    = $TbArchive.Text
        MinSizeKB      = [int]($TbMinKB.Text  -as [int])
        MaxSizeKB      = [int]($TbMaxKB.Text  -as [int])
        ModifiedAfter  = if ($DpAfter.SelectedDate)  { $DpAfter.SelectedDate.Value.ToString("yyyy-MM-dd") } else { "" }
        ModifiedBefore = if ($DpBefore.SelectedDate) { $DpBefore.SelectedDate.Value.ToString("yyyy-MM-dd") } else { "" }
        UseRegex       = [bool]$CbRegex.IsChecked
    }
    Save-Config -Cfg $cfg
    Update-Status "Preset gespeichert."
})

$BtnOpenLogs.Add_Click({
    Initialize-LogHtml
    Start-Process $LogHtmlPath
    Update-Status "Log geöffnet."
})

$BtnSearch.Add_Click({
    $Script:SearchResults.Clear()
    $files = Get-MatchingFiles -RootPath $TbRoot.Text -Pattern $TbPattern.Text -Recurse ([bool]$CbSub.IsChecked) `
        -MinSizeKB ([int]($TbMinKB.Text -as [int])) -MaxSizeKB ([int]($TbMaxKB.Text -as [int])) `
        -ModifiedAfter ($DpAfter.SelectedDate ? $DpAfter.SelectedDate.Value.ToString("yyyy-MM-dd") : "") `
        -ModifiedBefore ($DpBefore.SelectedDate ? $DpBefore.SelectedDate.Value.ToString("yyyy-MM-dd") : "") `
        -UseRegex ([bool]$CbRegex.IsChecked)
    foreach ($f in $files) { [void]$Script:SearchResults.Add($f) }
    Update-Status "Treffer: $($Script:SearchResults.Count)"
})

$BtnCopy.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    Copy-Or-MoveFiles -Items $sel -Destination $TbDest.Text
    Update-Status "Kopieren abgeschlossen."
})

$BtnMove.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    Copy-Or-MoveFiles -Items $sel -Destination $TbDest.Text -Move
    Update-Status "Verschieben abgeschlossen."
})

$BtnArchive.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    Create-Archive -Items $sel -ArchivePath $TbArchive.Text
    Update-Status "Archiv erstellt."
})

$BtnBackup.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    $dest = Create-Backup -Items $sel -BackupRoot $TbBackupRoot.Text
    if ($dest) { Update-Status "Backup erstellt: $dest" }
})

###############################################################################
# Run
###############################################################################
$null = $window.ShowDialog()
Write-LogHtml -Level "INFO" -Action "Ende" -Details "Anwendung geschlossen"
