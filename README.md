# Datei-Manager

Ein einfacher PowerShell-Datei-Manager mit grafischer Oberfläche. Das Skript kann Dateien nach Erweiterung suchen und die ausgewählten Elemente kopieren, verschieben, umbenennen, als ZIP archivieren oder in einen Backup-Ordner kopieren. Alle Aktionen werden in `DateiManager.log` protokolliert.

## Voraussetzungen
- PowerShell 7+
- Windows mit .NET für die GUI

## Verwendung
```powershell
pwsh -File ./Datei-Manager.ps1
```
Beim Beenden speichert das Skript die zuletzt verwendeten Pfade in `config.json` im Skriptordner.

## Funktionen
- Dateien nach Erweiterung durchsuchen
- Ausgewählte Dateien kopieren oder verschieben
- Ausgewählte Dateien umbenennen
- Ausgewählte Dateien zu einem ZIP-Archiv zusammenfassen
- Backup-Kopie der Auswahl anlegen
- Protokollierung aller Aktionen
