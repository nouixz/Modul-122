# Dateimanager – PowerShell (Windows Forms)  

## 📖 Beschreibung  
Der Dateimanager ist ein in PowerShell 7 entwickeltes Tool mit einer **Windows Forms**-Oberfläche. Er automatisiert wiederkehrende Dateioperationen und protokolliert alle Aktionen in einer **HTML-Logdatei**. Die Suche unterstützt mehrere Muster (z. B. „pdf, jpg;png“) und rekursives Durchsuchen ist standardmäßig aktiviert.

### Funktionsumfang
- Dateien: **Kopieren** und **Verschieben** (Zielordner wird bei Bedarf automatisch angelegt)
- Sicherung: **Backup** in einen Zeitstempel-Ordner (z. B. „Backup_20250101_121314“)
- Archivierung: **ZIP-Archiv** mit Zeitstempel (z. B. „Archiv_20250101_121314.zip“)
- Suche: rekursiv, Muster wie `*.pdf`, `txt`, `.txt` oder mehrere durch Komma/Semikolon getrennt
- Protokollierung: **HTML-Log** mit farbigen Status-Tags (INFO/OK/WARN/ERROR) und „Log öffnen“-Link in der Oberfläche

Das Projekt entstand im Rahmen des Moduls „122 – Abläufe mit einer Skriptsprache automatisieren“.

---

## 🧭 Benutzeroberfläche (Aufbau)
- Linke Seite: Eingabefelder
  - Wurzelpfad (Suchbasis)
  - Muster (z. B. `*.pdf`, `txt`, `.txt`, oder mehrere: `pdf, jpg;png`)
  - Zielordner (für Kopieren/Verschieben)
  - Backup-Basisordner
  - Archiv-Ziel (Datei oder Ordner; bei Ordner wird automatisch ein Archivname erzeugt)
- Rechte Seite oben: Aktions-Buttons (farblich codiert)
  - Suchen (blau), Kopieren (grün), Verschieben (orange), Archiv (lila), Backup (türkis)
- Mitte: Ergebnisliste (ListView) mit Spalten
  - Name | Pfad | Ordner | Größe (menschenlesbar, z. B. „1,2 MB“) | Geändert (Zeitstempel)
  - Checkboxen zur Auswahl (wenn keine Auswahl getroffen: Aktionen wirken auf alle Treffer)
- Unten: Statusleiste
  - Status-Text (links)
  - Link „Log öffnen“ (öffnet die HTML-Logdatei)
  - Such-Indikator (Marquee/„Spinner“) bei laufender Suche

---

## 🔎 Suche (Details)
- Rekursion: Immer aktiv (Unterordner werden standardmäßig durchsucht)
- Muster-Eingabe:
  - `txt` → wird automatisch zu `*.txt`
  - `.txt` → wird automatisch zu `*.txt`
  - `*.log` bleibt unverändert
  - Mehrere Muster durch Komma oder Semikolon trennen, z. B.: `pdf, jpg;png`
- Robustheit:
  - Verwendet eine Pfad-Wildcard und `-Include`, um die Muster korrekt anzuwenden
  - Unterdrückt Zugriffsfehler per `-ErrorAction SilentlyContinue`
- Ergebnisliste:
  - Spalten werden nach der Suche automatisch an den Inhalt angepasst
  - Größen werden menschenlesbar angezeigt (B, KB, MB, GB, …)

---

## 🗂️ Aktionen (Details)
### Kopieren
- Kopiert die gewählten (oder alle) Treffer in den Zielordner
- Falls der Zielordner fehlt, wird er erstellt
- Ergebnis in der Statusleiste und im HTML-Log

### Verschieben
- Verschiebt die gewählten (oder alle) Treffer in den Zielordner
- Falls der Zielordner fehlt, wird er erstellt
- Ergebnis in der Statusleiste und im HTML-Log

### Archiv (ZIP)
- Erstellt ein ZIP-Archiv mit einem **gemeinsamen Zeitstempel** (bis zur nächsten Suche gleichbleibend)
- Ziel-Feld Verhalten:
  - Zeigt auf einen Ordner → Name wie „Archiv_YYYYMMDD_HHMMSS.zip“ wird automatisch erzeugt
  - Zeigt auf eine Datei → Es wird „Basisname_YYYYMMDD_HHMMSS.zip“ erzeugt
- Technisch:
  - Dateien werden kurzzeitig in ein Temp-Verzeichnis kopiert und dann mit `Compress-Archive` gepackt
- Ergebnis in der Statusleiste und im HTML-Log

### Backup
- Erstellt unter dem Backup-Basisordner einen Ordner „Backup_YYYYMMDD_HHMMSS“
- Kopiert die gewählten (oder alle) Treffer dorthin
- Ergebnis in der Statusleiste und im HTML-Log

---

## 📝 HTML-Logging
- Datei: `log.html` (im Skriptordner)
- Falls das Schreiben dort scheitert (z. B. Berechtigungen), wird automatisch auf `%TEMP%\DateimanagerLogs\log.html` ausgewichen
- Format: HTML-Tabelle mit farbigen Status-Tags
  - INFO (ℹ️), OK (✅), WARN (⚠️), ERROR (❌)
- Einträge u. a. bei Start, Suche, Kopieren, Verschieben, Archiv, Backup und Fehlersituationen
- In der Statusleiste gibt es einen Link „Log öffnen“ (öffnet die Datei mit dem Standardbrowser)

---

## ⚙️ Systemvoraussetzungen
- Windows 10 oder neuer
- PowerShell 7.0 oder neuer (`#Requires -Version 7.0` ist gesetzt)
- .NET (im Lieferumfang von PowerShell 7) – erforderlich für Windows Forms

Hinweis: Das Skript startet sich automatisch neu im **STA-Modus**, da Windows Forms dies benötigt.

---

## 🚀 Installation & Start
1. Repository herunterladen oder als ZIP beziehen und entpacken
2. PowerShell öffnen und in das Verzeichnis `LB-1` wechseln
3. Skript ausführen:

```powershell
./Dateimanager.ps1
```

Beim ersten Start kann sich das Skript ggf. einmal selbst im STA-Modus neu starten.

---

## � Bedienhinweise
- Ergebnisse auswählen:
  - Checkboxen nutzen oder mehrere Zeilen markieren (Strg/Shift)
  - Keine Auswahl → Aktion gilt für alle Treffer
- Muster-Eingabe: `txt` oder `.txt` reicht – es wird automatisch `*.txt` daraus
- Sehr große Ordner: Während der Suche zeigt die Statusleiste einen „Spinner“ und den Text „Suche läuft…“

---

## ❗️ Fehlerbehandlung & Tipps
- „Keine Treffer“ trotz Muster:
  - Prüfe Schreibweise der Muster (z. B. `*.pdf`, `txt`, `.txt`, `pdf, jpg`)
  - Prüfe, ob der Wurzelpfad korrekt gesetzt ist
- Zugriff verweigert (einige Ordner):
  - Die Suche läuft weiter; betroffene Einträge werden still übersprungen
- Archiv/Backup schlägt fehl:
  - Prüfe, ob Zielpfad existiert bzw. erstellt werden kann
  - Bei Archiv: Prüfe, ob die Zieldatei nicht gesperrt ist
- Log-Datei fehlt oder leer:
  - Öffne den alternativen Pfad: `%TEMP%\DateimanagerLogs\log.html`

---

## � Datenschutz & Sicherheit
- Das Skript legt keine versteckten Kopien an (außer temporär beim Archivieren)
- Log-Datei enthält Zeitstempel, Aktionstyp und Pfade – bitte intern behandeln

---

## 📦 Funktionsstand
- Keine Konfigurationsspeicherung/-ladung in dieser Version (Voreinstellungen sind im Skript gesetzt)
- Aktionen: Suchen, Kopieren, Verschieben, Archiv (ZIP), Backup
- Windows Forms, kein WPF

---

## 👨‍💻 Autor
Chavo Moser  
ICT-Fachmann EFZ (in Ausbildung)
