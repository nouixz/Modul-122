# Dateimanager (PowerShell, WPF, Dark UI)

Ein moderner Dateimanager als PowerShell-Skript mit WPF-Oberfläche.

## Funktionen

- Dateien **finden** (inkl. Unterordner, optional Regex, Größen- und Datumsfilter)
- Treffer **anzeigen** und **auswählen**
- Dateien **kopieren** oder **verschieben** in ein Zielverzeichnis
- Dateien **archivieren (ZIP)** via `Compress-Archive`
- **Backup** der ausgewählten Dateien in einen zeitgestempelten Ordner
- **Presets** per `config.json` speichern & laden
- **Log** in einer **HTML-Datei**, per Button im Standardbrowser öffnen
- **Dark-Theme**-UI mit moderner Optik

## Voraussetzungen

- Windows 10/11
- PowerShell 5.1 oder PowerShell 7+
- .NET / WPF verfügbar (Windows Standard)

## Installation

1. Ordner entpacken/kopieren (z. B. `C:\Tools\Dateimanager`).
2. `Dateimanager.ps1` ggf. per Rechtsklick → Eigenschaften → **Zulassen**.
3. PowerShell mit ausreichenden Rechten starten. Gegebenenfalls Ausführungsrichtlinie erlauben:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

## Start

```powershell
cd C:\Tools\Dateimanager
.\Dateimanager.ps1
```

## Konfiguration (config.json)

Beim ersten Start wird eine Standardkonfiguration geladen (falls `config.json` fehlt). Über **Preset speichern** wird die aktuelle UI als `config.json` gespeichert.

**Felder:**

- `RootPath` – Startordner für die Suche
- `Pattern` – Dateimuster (z. B. `*.pdf`). Wenn **Regex verwenden** aktiv ist, wird `Pattern` als regulärer Ausdruck auf den Dateinamen angewendet.
- `IncludeSub` – Unterordner durchsuchen (true/false)
- `Destination` – Ziel für Kopieren/Verschieben
- `BackupRoot` – Basisordner für Backups (es wird ein Unterordner `Backup_YYYYMMDD_HHMMSS` angelegt)
- `ArchivePath` – Ausgabepfad der ZIP-Datei
- `MinSizeKB` / `MaxSizeKB` – Größenfilter (0 = ignorieren)
- `ModifiedAfter` / `ModifiedBefore` – Datumsfilter (Format `yyyy-MM-dd`, leer = ignorieren)
- `UseRegex` – Schaltet Regex-Suche ein

## Log

- Das Log wird in `log.html` geführt und **vor dem Ende nicht überschrieben**. Neue Einträge werden als Tabellenzeilen ergänzt.
- Über **Logs anzeigen** wird die Datei im Standardbrowser geöffnet.

## Hinweise zur Bedienung

- **Suchen**: Filter setzen → *Suchen*.  
- **Auswahl**: Mehrfachauswahl mit **Strg/Shift**; ohne Auswahl wirken Aktionen auf **alle Treffer**.
- **Kopieren/Verschieben**: Zielordner angeben → *Kopieren* oder *Verschieben*.
- **Archiv (ZIP)**: Pfad zu `.zip` angeben → *Archiv (ZIP)*.
- **Backup**: Backup-Basisordner angeben → *Backup*.

## Sicherheit & Rechte

- Das Skript erzeugt Ordner bei Bedarf automatisch.
- Fehler werden im **Log** dokumentiert.
- Für geschützte Pfade ist evtl. erhöhte PowerShell nötig.

## Deinstallation

- Ordner löschen. Optional `config.json` und `log.html` vorher sichern.
