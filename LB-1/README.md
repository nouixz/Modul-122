# Dateimanager – README

Ein schlanker Datei‑Manager in **PowerShell 7** mit **WPF‑GUI** (Dark‑Theme) für Suchen, Kopieren/Verschieben, ZIP‑Archivierung und zeitgestempelte Backups – inklusive HTML‑Log.

## Features
- **Suche** nach Dateien mit Muster (z. B. `*.pdf`) ab Startordner, optional rekursiv.
- **Mehrfachauswahl** in einer Tabelle (Name, Pfad, Ordner, Größe, Änderungsdatum).
- **Kopieren/Verschieben** der Auswahl in ein Zielverzeichnis.
- **ZIP‑Archiv** aus der Auswahl erstellen.
- **Backup** in einen datums-/zeitgestempelten Ordner.
- **Konfiguration** in `config.json` (wird gelesen/geschrieben).
- **HTML‑Log (`log.html`)** mit farbigen Leveln (INFO/OK/WARN/ERROR); Entscheidung beim Beenden: Log behalten oder zurücksetzen.

## Systemvoraussetzungen
- **Windows** mit .NET/WPF (PresentationCore, PresentationFramework, WindowsBase).
- **PowerShell 7.0+** (`#Requires -Version 7.0`).
- Ausführungsrichtlinie, die das Starten lokaler Skripte erlaubt (ggf. `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`).

## Schnellstart
1. **PowerShell 7 öffnen**.
2. In den Ordner mit `Dateimanager.ps1` wechseln.
3. Script starten:  
   ```pwsh
   pwsh -File .\Dateimanager.ps1
   ```
4. GUI bedienen:
   - Startordner und Muster festlegen → **Suchen**.
   - Treffer ggf. auswählen (ohne Auswahl werden alle Treffer genommen).
   - Zielpfade für **Kopieren/Verschieben**, **Backup** oder **Archiv** setzen.
   - Ergebnisaktionen ausführen.

## Konfigurationsdatei (`config.json`)
Wird im Skriptverzeichnis gespeichert/geladen. Felder:
- `RootPath` – Startordner für die Suche.
- `Pattern` – Suchmuster (Standard `*`, z. B. `*.jpg`).
- `IncludeSub` – `true|false` für rekursive Suche.
- `Destination` – Zielordner für Kopieren/Verschieben.
- `BackupRoot` – Basisordner für Backups.
- `ArchivePath` – Zielpfad für die ZIP‑Datei.
- (intern reserviert, aktuell nicht genutzt): `MinSizeKB`, `MaxSizeKB`, `ModifiedAfter`, `ModifiedBefore`.

Konfiguration per Buttons **Laden/Speichern** in der GUI steuerbar.

## Logging
- Automatisches Anlegen/Aktualisieren von **`log.html`** im Skriptverzeichnis.
- Einträge enthalten Zeitstempel, Level, Aktion, Details.
- Beim Schließen der App werden Sie gefragt, ob das Log **behalten**, **gelöscht/neu angelegt** oder der Vorgang **abgebrochen** werden soll.

## Ordner/Datei‑Operationen
- **Kopieren/Verschieben**: legt Zielordner bei Bedarf an; überschreibt vorhandene Dateien.
- **ZIP‑Archiv**: kopiert Auswahl in ein Temp‑Verzeichnis und erstellt daraus ein ZIP (`Compress-Archive`).
- **Backup**: erstellt `Backup_yyyyMMdd_HHmmss` unter `BackupRoot` und kopiert die Auswahl hinein.

## Bekannte Grenzen
- Filter nach Größe/Datum sind im UI vorbereitet, aber derzeit **deaktiviert**.
- Aktionen überschreiben gleichnamige Dateien ohne Rückfrage.
- Pfadlängen/ACL‑Einschränkungen des OS gelten weiterhin.

## Lizenz & Autor
- App‑Name/Version im Skript: **Dateimanager 1.0.1**
- Lizenz: (bitte ergänzen) – z. B. MIT.
