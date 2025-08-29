# BackupTool (PowerShell)

Einfaches, portables Backup-Skript mit optionaler ZIP-Erstellung, minimaler Windows-GUI und Terminal-Menü für macOS/Linux. Alle Aktionen werden mit Zeitstempel in eine Logdatei geschrieben.

Script-Datei: `LB1-Powershell/BackupTool.ps1`
Konfiguration/Log: `LB1-Powershell/config.json`, `LB1-Powershell/backup.log`

## Planung

1) Zweck bestimmen und Skript benennen
- Name: BackupTool
- Zweck: Ordner sichern (kopieren oder als ZIP archivieren) an einen Zielort. Zusätzlich einfache Dateioperationen nach Erweiterung (Terminal) und ein kleiner Prozess-Manager.

2) Skript beschreiben: Was es machen soll
- Windows: Kleine GUI zum Auswählen von Quelle/Ziel, Checkbox „ZIP“, Buttons „Run Backup“, „View Log“, „Exit“.
- macOS/Linux (oder Windows mit `-Terminal`): Menü mit Optionen:
	- Quelle/Ziel setzen, ZIP umschalten, Backup ausführen, Log anzeigen
	- Datei-Tools: Dateien nach Erweiterung suchen und dann kopieren/verschieben/umbenennen/zippen
	- Prozess-Manager: Prozesse anzeigen/suchen/starten/beenden
- Konfiguration und Log liegen neben dem Skript, sind damit repo-portabel.

3) Welche Fehlerprüfung vorgesehen ist
- Pfadprüfung: Quelle muss existieren, Ziel wird bei Bedarf erstellt.
- Ausnahmebehandlung bei Datei-/ZIP-Operationen; Fehler werden ins Log geschrieben.
- Saubere Pfadverarbeitung (Relative/Absolute Pfade, Trennzeichen).
- Schutz vor leerer Eingabe (Quelle/Ziel dürfen nicht leer sein).
- Schreib-/Zugriffsfehler (z. B. Berechtigungen) werden abgefangen und protokolliert.

4) Eingaben des Benutzers oder eine Datei einlesen
- GUI: Ordnerauswahldialoge für Quelle/Ziel, Checkbox für ZIP.
- Terminal: Interaktive Prompts pro Menüpunkt.
- Datei-Ein-/Ausgabe: `config.json` wird beim Start geladen bzw. beim Speichern aktualisiert.

5) Ausgabe am Bildschirm und/oder in eine Datei schreiben
- Bildschirm: GUI-Dialoge bzw. Terminal-Textausgaben mit Ergebnis/Fehler.
- Datei: `backup.log` mit Zeitstempel (Format `yyyy-MM-dd HH:mm:ss`), z. B. "ZIP created: …" oder "Copy error: …".

## Voraussetzungen
- Empfohlen: PowerShell 7+ (`pwsh`).
- Windows-GUI benötigt .NET (standardmäßig vorhanden). Auf macOS/Linux läuft das Skript im Terminal-Modus.

## Verwendung

Windows (GUI)
```zsh
pwsh -File ./LB1-Powershell/BackupTool.ps1
```

macOS/Linux (Terminal-Menü) oder erzwungen auf Windows
```zsh
pwsh -File ./LB1-Powershell/BackupTool.ps1 -Terminal
```

Backup-Ergebnis
- Kopiermodus: Zielordner `QuelName_backup_YYYYMMDD_HHMMSS` wird im Ziel erstellt.
- ZIP-Modus: Datei `QuelName_backup_YYYYMMDD_HHMMSS.zip` wird im Ziel erstellt.

## Konfiguration (`config.json`)
```json
{
	"SourceFolder": "",
	"TargetFolder": "",
	"ZipBackup": false,
	"LogFile": "./LB1-Powershell/backup.log"
}
```
- Wird automatisch erzeugt/aktualisiert, wenn Werte über GUI/Terminal gesetzt werden.

## Logdatei
- Pfad: `LB1-Powershell/backup.log`
- Enthält alle Aktionen und Fehler mit Zeitstempel.

## Hinweise & Grenzen
- ZIP-Erstellung nutzt .NET ZipFile. Falls nicht verfügbar, wird der Fehler geloggt.
- **Versioning**: Wenn eine ZIP-Datei oder ein Backup-Ordner bereits existiert, wird automatisch eine versionierte Kopie erstellt (z.B. `Archiv_v1.zip`, `Backup_v1`) statt zu überschreiben.
- **Konfiguration**: Das Tool verwendet sowohl `config.json` (README-Format) als auch `datei-manager-config.json` (internes Format) für maximale Kompatibilität.
- Datei-Tools und Prozess-Manager sind bewusst einfach gehalten; auf sensible Pfade/Prozesse achten.

## Neue Funktionen

### Automatisches Versioning
- ZIP-Dateien: Statt zu überschreiben wird automatisch eine neue Version erstellt (`Archiv.zip` → `Archiv_v1.zip` → `Archiv_v2.zip`)
- Backup-Ordner: Gleiches Versioning-System für Backup-Ordner (`Backup` → `Backup_v1` → `Backup_v2`)
- Keine Überschreibung: Bestehende Dateien/Ordner bleiben erhalten

### Verbesserte Konfiguration
- Unterstützt sowohl das `config.json` Format (aus README) als auch das interne Format
- Automatische Migration zwischen Konfigurationsformaten
- Relative Pfade werden korrekt aufgelöst

