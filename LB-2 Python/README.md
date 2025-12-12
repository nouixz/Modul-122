# Notenomat

Ein einfaches Terminal-Tool zur Verwaltung von Schulnoten mit SQLite. Enthält farbige Ausgaben, Tabellen im Terminal, Exporte (CSV/JSON/PDF) mit Zeitstempel sowie einen PDF-Bericht mit farbiger Notenspalte.

## Funktionsumfang
- Fächerstammdaten werden beim Start automatisch angelegt (SQLite)
- Noten erfassen (inkl. Datumsangabe, Regex-Validierung)
- Übersicht aller Noten als Tabelle (tabulate, GitHub-Style)
- Noten pro Fach mit farbiger Ausgabe und Fach-Durchschnitt
- Gesamtdurchschnitt über alle Fächer
- Exporte mit Zeitstempel:
  - CSV (`noten_export_YYYY-MM-DD_HH-MM-SS.csv`)
  - JSON (`noten_export_YYYY-MM-DD_HH-MM-SS.json`)
  - PDF (`notenbericht_YYYY-MM-DD_HH-MM-SS.pdf`) mit Kopfzeile, Tabelle und farbiger Notenspalte

## Voraussetzungen
- Python 3.10+ (getestet mit der vorhandenen Umgebung im Projekt)
- Abhängigkeiten: `tabulate`, `fpdf2` (SQLite, csv, json sind Teil der Standardbibliothek)

## Installation (empfohlen mit virtuellem Environment)
```bash
autpython3 -m venv .venv
source .venv/bin/activate
pip install tabulate fpdf2
```
Falls bereits ein `requirements.txt` existiert, kannst du alternativ nutzen:
```bash
pip install -r requirements.txt
```

## Start
```bash
cd "LB-2 Python"
python notenomat.py
```
Die SQLite-Datenbank liegt automatisch neben dem Skript als `noten.db`.

## Bedienung (Menü)
1) Note erfassen
2) Alle Noten anzeigen (Tabelle)
3) Noten nach Fach anzeigen (mit Fach-Durchschnitt)
4) Gesamtdurchschnitt anzeigen
5) Exportiere Noten als CSV
6) Exportiere Noten als JSON
7) Exportiere Noten als PDF
8) Beenden

## Validierungen
- Noten-Eingabe via Regex: erlaubt sind 1–6 sowie .0 oder .5 (z.B. 4, 4.5, 5.0)
- Datum: Eingabe im Format `YYYY-MM-DD`, leere Eingabe setzt heutiges Datum
- Duplikat-Prüfung: Dieselbe Note für dasselbe Fach am selben Datum wird nicht doppelt gespeichert

## Farb-Logik (Konsole)
- Note >= 5.0: grün
- 4.0 bis < 5.0: gelb
- < 4.0: rot

## PDF-Layout
- Titel und Erstell-Datum im Kopf
- Tabelle mit Rahmen und Header in hellgrau
- Notenspalte farbig hinterlegt (grün/gelb/rot wie oben), Fach- und Datumsspalte weiß
- Gesamtdurchschnitt fett rechts unter der Tabelle

## Exporte
- CSV/JSON/PDF erhalten automatisch einen Zeitstempel im Dateinamen und werden neben dem Skript abgelegt
- Exporte erfolgen nur, wenn mindestens eine Note vorhanden ist

## Datenablage
- SQLite-Datei: `noten.db` im Ordner des Skripts
- Tabellen: `subjects` (Fächer), `grades` (Noten)

## Häufige Fragen / Troubleshooting
- **Linien im PDF zu dünn?** Zoom erhöhen oder PDF in einem anderen Viewer öffnen; die Tabelle wird mit Rahmen gezeichnet.
- **Fehlende Pakete?** `pip install tabulate fpdf2` im aktiven venv ausführen.
- **Rechteproblem beim Schreiben?** Sicherstellen, dass du Schreibrechte im Ordner `LB-2 Python` hast.

## Lizenz / Nutzung
Lern- und Übungsprojekt; keine Gewährleistung für produktiven Einsatz.
