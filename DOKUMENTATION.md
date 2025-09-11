# Technische Dokumentation

## Überblick
`Dateimanager.ps1` ist ein PowerShell‑7‑Skript mit WPF‑UI. Es kapselt Dateioperationen (Suche, Kopieren/Verschieben, Archiv/Backup) und protokolliert in `log.html`.

## Architektur
- **UI**: WPF‑XAML (Dark Theme). Zentrale Controls:
  - `TbRoot`, `TbPattern`, `CbSub`
  - `TbDest`, `TbBackupRoot`, `TbArchive`
  - Buttons: `BtnSearch`, `BtnCopy`, `BtnMove`, `BtnArchive`, `BtnBackup` (+ Konfig‑Buttons)
  - `GridResults` (DataGrid, ItemsSource = ObservableCollection)
  - `StatusText` (Statusleiste)
- **State**:
  - `$Script:SearchResults`: `ObservableCollection[object]` mit `FileInfo`‑Objekten.
  - `$ConfigPath`, `$LogHtmlPath`
  - `$Script:LogLock`: Synchronisationsobjekt für Log‑Schreibzugriffe.
- **Konfig**: JSON in `config.json`, geladen bei Start, speicherbar per Button.

## Wichtige Funktionen
- `Initialize-LogHtml()`  
  Legt `log.html` im Dark‑Theme an (HTML/CSS Grundgerüst). Idempotent.

- `Write-LogHtml([Level],[Action],[Details])`  
  Fügt eine Tabellenzeile mit Zeitstempel hinzu. Levels: `INFO|OK|WARN|ERROR`.  
  Nutzt `$Script:LogLock` und überschreibt die Datei atomar mit ergänzt­er Zeile.

- `Get-Config()` / `Save-Config($cfg)`  
  Liest/schreibt `config.json`. Bei Fehlern Standardwerte + Log‑Eintrag.

- `Get-MatchingFiles($RootPath,$Pattern,$Recurse, ...)`  
  Ermittelt Dateien via `Get-ChildItem -File -Recurse:$Recurse -Filter $Pattern`.  
  Optional vorbereitete Filter (`MinSizeKB`, `MaxSizeKB`, `ModifiedAfter/Before`) sind im Code vorhanden, derzeit nicht ans UI gebunden.  
  **Rückgabe:** `FileInfo[]`.

- `Copy-Or-MoveFiles($Items,$Destination,[switch]$Move)`  
  Legt Zielordner an; `Copy-Item` bzw. `Move-Item` mit `-Force`, schreibt Log je Datei.

- `New-Archive($Items,$ArchivePath)`  
  Kopiert Auswahl in ein Temp‑Verzeichnis, entfernt bestehendes Archiv, erstellt ZIP via `Compress-Archive`, räumt Temp auf, schreibt Log.

- `New-Backup($Items,$BackupRoot)`  
  Erstellt `Backup_yyyyMMdd_HHmmss` und kopiert Auswahl hinein; Log + Rückgabe des Zielpfads.

- `Get-CurrentSelection()`  
  Gibt `GridResults.SelectedItems` zurück; falls leer, die gesamte Trefferliste.

- `Update-Status($msg)`  
  Schreibt Statuszeilentext in der UI.

## Ereignishandling (Auszug)
- `BtnSearch.Add_Click`: leert Ergebnisse, ruft `Get-MatchingFiles`, füllt `ObservableCollection`, Status zeigt Trefferanzahl.
- `BtnCopy.Add_Click` / `BtnMove.Add_Click`: holt Auswahl → `Copy-Or-MoveFiles`, Statusmeldung.
- `BtnArchive.Add_Click`: Auswahl → `New-Archive`, Statusmeldung.
- `BtnBackup.Add_Click`: Auswahl → `New-Backup`, Status mit Zielpfad.
- `Window.Add_Closing`: Dialog mit Optionen **Behalten / Zurücksetzen / Abbrechen** für `log.html`.

## Datenfluss
1. Nutzer setzt Suchparameter → **Suchen**.
2. Treffer (`FileInfo`) werden in `SearchResults` gebunden und im Grid dargestellt.
3. Aktionen (Kopieren/Verschieben/Backup/Archiv) iterieren über die Auswahl und schreiben pro Datei ins **HTML‑Log**.

## Fehlerbehandlung & Logging
- Pfadfehler, IO‑Ausnahmen etc. führen zu `Write-LogHtml(Level="ERROR", ...)`.
- Erfolgreiche Operationen erzeugen `OK`‑Einträge.
- Konfig‑ und Suchfehler werden im Log vermerkt (z. B. ungültige JSON).

## Erweiterungspunkte
- **Filter aktivieren**: UI‑Felder für Größe/Datum anbinden und Parameter an `Get-MatchingFiles` übergeben.
- **Asynchrone Aktionen**: Längere Operationen in Jobs/Runspaces auslagern; Fortschritt in Statusleiste/ProgressBar.
- **Konfliktstrategie**: `-Force` abwählbar, Dialog bei Überschreiben.
- **Internationalisierung**: Strings zentralisieren, ggf. Ressourcen‑Dictionary nutzen.
