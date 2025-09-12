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

# Config paths (robust Ermittlung auch beim Dot-Sourcing oder VSCode Run Selection)
$Script:ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Script:ScriptRoot -PathType Container)) { $Script:ScriptRoot = (Get-Location).Path }
$ConfigPath = Join-Path $Script:ScriptRoot 'config.json'
$LogHtmlPath = Join-Path $Script:ScriptRoot 'log.html'

###############################################################################
# Constants & Globals
###############################################################################
$Script:AppName = "Dateimanager"
$Script:Version = "1.0.1"
$Script:SearchResults = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$Script:LogLock = New-Object Object

###############################################################################
# Logging (HTML)
###############################################################################
# Funktion zur Initialisierung der HTML-Logdatei.
# Erstellt die Datei nur, wenn sie noch nicht existiert. Verwendet ein dunkles Layout.
function Initialize-LogHtml {
    # Sicherstellen, dass Zielverzeichnis existiert
    $logDir = Split-Path -Parent $LogHtmlPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { }
    }
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
        # Fallback auf %TEMP% wenn Erstellung im Repo-Verzeichnis fehlschlägt (z.B. Rechte, Lock, Virenscanner)
        $fallbackDir = Join-Path $env:TEMP 'DateimanagerLogs'
        try { if (-not (Test-Path -LiteralPath $fallbackDir)) { New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null } } catch {}
        $global:LogHtmlPath = Join-Path $fallbackDir 'log.html'
        try {
            Set-Content -Path $global:LogHtmlPath -Value ($lines -join "`n") -Encoding UTF8 -ErrorAction Stop
            Write-Host "[LOG] Primärer Pfad fehlgeschlagen -> Fallback verwendet: $global:LogHtmlPath" -ForegroundColor Yellow
        } catch {
            Write-Host "[LOG] Erstellung auch im Fallback fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}


# Schreibt einen Eintrag (Zeile) in die HTML-Logdatei.
# Parameter:
#   Level  = INFO | OK | WARN | ERROR (Steuert Farbe/Icon)
#   Action = Kurze Beschreibung der Aktion (z.B. "Suche", "Backup")
#   Details= Pfad oder Zusatzinfos
function Write-LogHtml {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR")]
        [string]$Level = "INFO",
        [string]$Action,
        [string]$Details
    )
    Initialize-LogHtml
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $levelClass = "level-info"
    if ($Level -eq "OK")    { $levelClass = "level-ok" }
    elseif ($Level -eq "WARN")  { $levelClass = "level-warn" }
    elseif ($Level -eq "ERROR") { $levelClass = "level-error" }

    $safe = $Details
    try {
        $safe = [System.Net.WebUtility]::HtmlEncode($Details)
    } catch {}

    $icon = ""
    switch ($Level) {
        "INFO"  { $icon = "<span class='icon'>ℹ️</span>" }
        "OK"    { $icon = "<span class='icon'>✅</span>" }
        "WARN"  { $icon = "<span class='icon'>⚠️</span>" }
        "ERROR" { $icon = "<span class='icon'>❌</span>" }
    }
    $row = "<tr><td class='time'>$ts</td><td>$Action</td><td class='path'>$safe</td><td><span class='tag $levelClass'>$icon$Level</span></td></tr>"
    if (-not (Test-Path -LiteralPath $LogHtmlPath)) {
        Initialize-LogHtml
        if (-not (Test-Path -LiteralPath $LogHtmlPath)) { Write-Host "[LOG] Kein Log-Pfad verfuegbar." -ForegroundColor Red; return }
    }
    $null = [System.Threading.Monitor]::Enter($Script:LogLock)
    try {
        $content = Get-Content -LiteralPath $LogHtmlPath -Raw -Encoding UTF8 -ErrorAction Stop
        $updated = $content -replace '</tbody>', "$row`n      </tbody>"
        Set-Content -Path $LogHtmlPath -Value $updated -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "[LOG] Schreibfehler: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        [System.Threading.Monitor]::Exit($Script:LogLock)
    }
}

###############################################################################
# Config
###############################################################################
# Lädt die Konfiguration (JSON). Bei Fehlern oder nicht vorhandener Datei
# wird ein Standardobjekt zurückgegeben.
function Get-Config {
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            return $json
        } catch {
            Write-LogHtml -Level "ERROR" -Action "Config laden" -Details "Ungueltige JSON-Datei: $ConfigPath - $($_.Exception.Message)"
        }
    }
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
        # Regex support entfernt
    }
}

# Speichert die aktuelle Konfiguration als JSON.
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
        Write-LogHtml -Level "ERROR" -Action "Suche" -Details "Pfad nicht gefunden: $RootPath"
        return @()
    }

    try {
        $all = Get-ChildItem -LiteralPath $RootPath -File -Recurse:$Recurse -ErrorAction Stop -Filter $Pattern

        if ($MinSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -ge ($MinSizeKB * 1KB) } }
        if ($MaxSizeKB -gt 0) { $all = $all | Where-Object { $_.Length -le ($MaxSizeKB * 1KB) } }
        if ($ModifiedAfter)  { $after  = Get-Date $ModifiedAfter;  $all = $all | Where-Object { $_.LastWriteTime -ge $after } }
        if ($ModifiedBefore) { $before = Get-Date $ModifiedBefore; $all = $all | Where-Object { $_.LastWriteTime -le $before } }

        $files = $all | Select-Object FullName, Name, DirectoryName, Length, LastWriteTime
        Write-LogHtml -Level "OK" -Action "Suche" -Details "Gefunden: $($files.Count) – '$Pattern' in $RootPath"
        return ,$files
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Suche" -Details $_.Exception.Message
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
                Write-LogHtml -Level "OK" -Action "Verschieben" -Details "$($it.FullName) -> $target"
            } else {
                Copy-Item -LiteralPath $it.FullName -Destination $target -Force
                Write-LogHtml -Level "OK" -Action "Kopieren" -Details "$($it.FullName) -> $target"
            }
        } catch {
            $act = "Kopieren"
            if ($Move.IsPresent) { $act = "Verschieben" }
            Write-LogHtml -Level "ERROR" -Action $act -Details "$($it.FullName): $($_.Exception.Message)"
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
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        foreach ($it in $Items) {
            Copy-Item -LiteralPath $it.FullName -Destination (Join-Path $tmp $it.Name) -Force
        }
        if (Test-Path $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $ArchivePath -Force
        Remove-Item -LiteralPath $tmp -Recurse -Force
        Write-LogHtml -Level "OK" -Action "Archiv erstellen" -Details $ArchivePath
    } catch {
        Write-LogHtml -Level "ERROR" -Action "Archiv erstellen" -Details $_.Exception.Message
    }
}

# Erstellt einen Zeitstempel-Ordner und kopiert die ausgewählten Dateien hinein.
function New-Backup {
    param(
        [array]$Items,
        [string]$BackupRoot
    )
    try {
        if (-not $Items -or $Items.Count -eq 0) {
            Write-LogHtml -Level 'WARN' -Action 'Backup' -Details 'Keine Dateien übergeben'
            return
        }
        if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
            $BackupRoot = Join-Path $HOME 'Backups'
            Write-LogHtml -Level 'INFO' -Action 'Backup' -Details "Leerer BackupRoot -> Verwende $BackupRoot"
        }
        if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
                Write-LogHtml -Level 'OK' -Action 'Backup' -Details "Basisordner erstellt: $BackupRoot"
            } catch {
                throw "BackupRoot kann nicht erstellt werden: $BackupRoot - $($_.Exception.Message)"
            }
        }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $BackupRoot "Backup_$stamp"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $copied = 0
        foreach ($it in $Items) {
            try {
                $targetFile = Join-Path $dest $it.Name
                Copy-Item -LiteralPath $it.FullName -Destination $targetFile -Force -ErrorAction Stop
                Write-LogHtml -Level 'INFO' -Action 'Backup-Datei' -Details "$($it.FullName) -> $targetFile"
                $copied++
            } catch {
                Write-LogHtml -Level 'ERROR' -Action 'Backup-Datei' -Details "$($it.FullName): $($_.Exception.Message)"
            }
        }
        if ($copied -gt 0) {
            Write-LogHtml -Level 'OK' -Action 'Backup' -Details "$dest (Dateien: $copied)"
        } else {
            Write-LogHtml -Level 'WARN' -Action 'Backup' -Details 'Keine Dateien kopiert'
        }
        return $dest
    } catch {
        Write-LogHtml -Level 'ERROR' -Action 'Backup' -Details $_.Exception.Message
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
        Background="#0f1115" Foreground="#e5e7eb" FontFamily="Segoe UI">
    <Window.Resources>
    <SolidColorBrush x:Key="CardBg" Color="#181818"/>
    <SolidColorBrush x:Key="Accent" Color="#3a82f7"/>
    <SolidColorBrush x:Key="Accent2" Color="#4fc3f7"/>

        <Style TargetType="Button">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Background" Value="#181818"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="BorderBrush" Value="#232323"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border CornerRadius="0" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Opacity="0.95">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect BlurRadius="6" ShadowDepth="0" Color="#222" Opacity="0.2"/>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="#101010"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="BorderBrush" Value="#232323"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="15"/>
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
            <Setter Property="Background" Value="#101010"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="FontFamily" Value="Segoe UI, Arial, sans-serif"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="RowHeight" Value="32"/>
            <Setter Property="GridLinesVisibility" Value="All"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#232323"/>
            <Setter Property="VerticalGridLinesBrush" Value="#232323"/>
            <Setter Property="RowBackground" Value="#181818"/>
            <Setter Property="AlternatingRowBackground" Value="#232323"/>
            <Setter Property="BorderBrush" Value="#232323"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CellStyle">
                <Setter.Value>
                    <Style TargetType="DataGridCell">
                        <Setter Property="BorderThickness" Value="1"/>
                        <Setter Property="BorderBrush" Value="#232323"/>
                        <Setter Property="Background" Value="{Binding RelativeSource={RelativeSource AncestorType=DataGridRow}, Path=Background}"/>
                        <Style.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#23272f"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#3b82f6"/>
                                <Setter Property="Foreground" Value="#fff"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </Setter.Value>
            </Setter>
            <Setter Property="ColumnHeaderStyle">
                <Setter.Value>
                    <Style TargetType="DataGridColumnHeader">
                        <Setter Property="Background" Value="#181818"/>
                        <Setter Property="Foreground" Value="#a3a3a3"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                        <Setter Property="FontSize" Value="15"/>
                        <Setter Property="BorderBrush" Value="#232323"/>
                        <Setter Property="BorderThickness" Value="0,0,1,1"/>
                        <Setter Property="Padding" Value="8,4,8,4"/>
                    </Style>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Merged single default GroupBox style -->
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="8"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="Background" Value="{StaticResource CardBg}"/>
            <Setter Property="BorderBrush" Value="#283044"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type GroupBox}">
                        <Grid>
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="0" Opacity="0.70"/>
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

        <StackPanel Orientation="Horizontal" Grid.Row="0">
            <Button x:Name="BtnLoadCfg" Content="🗂️ Preset laden"/>
            <Button x:Name="BtnSaveCfg" Content="💾 Preset speichern"/>
            <Button x:Name="BtnOpenLogs" Content="📄 Logs anzeigen"/>
            <TextBlock Text=" | " VerticalAlignment="Center" Margin="4"/>
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
                        <DataGrid.BorderBrush>
                            <SolidColorBrush Color="#444"/>
                        </DataGrid.BorderBrush>
                        <DataGrid.CellStyle>
                            <Style TargetType="DataGridCell">
                                <Setter Property="BorderThickness" Value="1"/>
                                <Setter Property="BorderBrush" Value="#444"/>
                                <Setter Property="Background" Value="#181818"/>
                            </Style>
                        </DataGrid.CellStyle>
                        <DataGrid.GridLinesVisibility>All</DataGrid.GridLinesVisibility>
                </DataGrid>

                <TextBlock Grid.Row="1" Text="Tipp: Mehrfachauswahl mit Strg/Shift. Aktionen betreffen markierte Zeilen; ohne Auswahl wirken alle Aktionen auf alle Treffer." Margin="6" Foreground="#9ca3af"/>
            </Grid>
        </Grid>

        <DockPanel Grid.Row="2">
            <TextBlock x:Name="StatusText" Text="Bereit." Margin="6" Foreground="#9ca3af"/>
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
$CbSub        = $window.FindName('CbSub')
## Removed Min/Max KB and Date controls

$TbDest       = $window.FindName('TbDest')
$TbBackupRoot = $window.FindName('TbBackupRoot')
$TbArchive    = $window.FindName('TbArchive')

$GridResults  = $window.FindName('GridResults')
$StatusText   = $window.FindName('StatusText')

$GridResults.ItemsSource = $Script:SearchResults

###############################################################################
# Load initial config
###############################################################################
$cfg = Get-Config
$TbRoot.Text       = $cfg.RootPath
$TbPattern.Text    = $cfg.Pattern
$CbSub.IsChecked   = [bool]$cfg.IncludeSub
$TbDest.Text       = $cfg.Destination
$TbBackupRoot.Text = $cfg.BackupRoot
$TbArchive.Text    = $cfg.ArchivePath
## Removed Min/Max KB and Date config loading

Initialize-LogHtml
Write-LogHtml -Level 'INFO' -Action 'Start' -Details "Anwendung gestartet (Root=$($Script:ScriptRoot))"

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

###############################################################################
# Wire events
###############################################################################
$BtnLoadCfg.Add_Click({
    $cfg = Get-Config
    $TbRoot.Text       = $cfg.RootPath
    $TbPattern.Text    = $cfg.Pattern
    $CbSub.IsChecked   = [bool]$cfg.IncludeSub
    $TbDest.Text       = $cfg.Destination
    $TbBackupRoot.Text = $cfg.BackupRoot
    $TbArchive.Text    = $cfg.ArchivePath
    ## Removed Min/Max KB and Date config loading
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
        # Removed Min/Max KB and Date
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

    $files = Get-MatchingFiles -RootPath $TbRoot.Text -Pattern $TbPattern.Text -Recurse ([bool]$CbSub.IsChecked)

    foreach ($f in $files) { [void]$Script:SearchResults.Add($f) }
    Update-Status ("Treffer: {0}" -f $Script:SearchResults.Count)
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
    New-Archive -Items $sel -ArchivePath $TbArchive.Text
    Update-Status "Archiv erstellt."
})

$BtnBackup.Add_Click({
    $sel = Get-CurrentSelection
    if ($sel.Count -eq 0) { Update-Status "Keine Dateien ausgewählt."; return }
    $dest = New-Backup -Items $sel -BackupRoot $TbBackupRoot.Text
    if ($dest) { Update-Status ("Backup erstellt: {0}" -f $dest) }
})

###############################################################################
# Run
###############################################################################

# Add Closing event handler to prompt user about logs
$window.Add_Closing({
        $dlgResult = [System.Windows.MessageBox]::Show(
            "Bevor sie das Programm schliessen, sollen die Logs gespeichert oder gelöscht werden?",
            "Log behalten oder löschen?",
            [System.Windows.MessageBoxButton]::YesNoCancel,
            [System.Windows.MessageBoxImage]::Question
        )
    if ($dlgResult -eq [System.Windows.MessageBoxResult]::Cancel) {
        $_.Cancel = $true
        return
    }
    elseif ($dlgResult -eq [System.Windows.MessageBoxResult]::No) {
        # Reset logs: overwrite log file with empty log
        Remove-Item -Path $LogHtmlPath -Force -ErrorAction SilentlyContinue
        Initialize-LogHtml
            Write-LogHtml -Level "INFO" -Action "Reset" -Details "Log wurde zurückgesetzt."
    } else {
        # Keep logs: do nothing
        Write-LogHtml -Level "INFO" -Action "Ende" -Details "Anwendung geschlossen (Log behalten)"
    }
})
$null = $window.ShowDialog()
