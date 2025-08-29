# =========================================
# FileManager.ps1
# Dateien nach Endungen suchen und verwalten
# =========================================

# Logdatei
$LogFile = ".\FileManager.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

function Show-Menu {
    Clear-Host
    Write-Host "===== Datei-Manager =====" -ForegroundColor Cyan
    Write-Host "1. Dateien nach Erweiterung suchen"
    Write-Host "2. Beenden"
    Write-Host "==========================="
}

function Show-ActionMenu {
    Write-Host "Wähle eine Aktion:" -ForegroundColor Yellow
    Write-Host "1. Kopieren"
    Write-Host "2. Verschieben"
    Write-Host "3. Umbenennen"
    Write-Host "4. Archiv (ZIP) erstellen"
    Write-Host "5. Backup erstellen"
    Write-Host "6. Abbrechen"
}

function File-Manager {
    param([string[]]$Files)

    do {
        Show-ActionMenu
        $action = Read-Host "Aktion wählen"
        switch ($action) {
            "1" {
                $target = Read-Host "Zielordner angeben"
                foreach ($file in $Files) {
                    Copy-Item $file -Destination $target -Force
                    Write-Log "Datei $file -> nach $target kopiert"
                }
            }
            "2" {
                $target = Read-Host "Zielordner angeben"
                foreach ($file in $Files) {
                    Move-Item $file -Destination $target -Force
                    Write-Log "Datei $file -> nach $target verschoben"
                }
            }
            "3" {
                foreach ($file in $Files) {
                    $newName = Read-Host "Neuer Name für $file"
                    Rename-Item $file -NewName $newName
                    Write-Log "Datei $file -> umbenannt in $newName"
                }
            }
            "4" {
                $zipName = Read-Host "Name der ZIP-Datei"
                Compress-Archive -Path $Files -DestinationPath "$zipName.zip" -Force
                Write-Log "Archiv $zipName.zip erstellt mit Dateien: $($Files -join ', ')"
            }
            "5" {
                $backupFolder = ".\Backup"
                if (-not (Test-Path $backupFolder)) { New-Item -ItemType Directory -Path $backupFolder }
                foreach ($file in $Files) {
                    Copy-Item $file -Destination $backupFolder -Force
                    Write-Log "Backup von $file -> $backupFolder erstellt"
                }
            }
            "6" { break }
        }
    } while ($true)
}

# Hauptschleife
do {
    Show-Menu
    $choice = Read-Host "Auswahl"

    switch ($choice) {
        "1" {
            $ext = Read-Host "Welche Erweiterung? (z.B. txt, log, jpg)"
            $path = Read-Host "In welchem Ordner suchen?"
            $files = Get-ChildItem -Path $path -Recurse -Filter "*.$ext" -File -ErrorAction SilentlyContinue

            if ($files) {
                Write-Host "Gefundene Dateien:" -ForegroundColor Green
                $files | ForEach-Object { Write-Host $_.FullName }
                File-Manager -Files $files.FullName
            } else {
                Write-Host "Keine Dateien mit .$ext gefunden." -ForegroundColor Red
                Write-Log "Keine Dateien mit .$ext in $path gefunden"
            }
        }
        "2" { break }
    }
} while ($true)
