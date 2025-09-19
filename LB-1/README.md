# Dateimanager – PowerShell Skript  

## 📖 Beschreibung  
Dieses Projekt ist ein **Dateimanager in PowerShell** mit einer grafischen Benutzeroberfläche (WPF).  
Es automatisiert wiederkehrende Dateioperationen und erleichtert so die tägliche Arbeit.  

Der Dateimanager bietet unter anderem:  
- Dateien und Ordner **kopieren, verschieben und löschen**  
- **Backups** und **Archive** von Verzeichnissen erstellen  
- **Suchfunktion** für Dateien und Ordner  
- **Konfigurationsdateien** speichern und laden  
- Automatisierte **HTML-Protokollierung** aller ausgeführten Aktionen  

Das Projekt wurde im Rahmen des Moduls *122 – Abläufe mit einer Skriptsprache automatisieren* entwickelt.  

---

## ⚙️ Systemvoraussetzungen  
- Windows 10 oder neuer  
- PowerShell 5.1 oder PowerShell 7+  
- .NET Framework (für WPF erforderlich)  

---

## 🚀 Installation  
1. Repository oder Skript herunterladen  
2. Skript entpacken (falls ZIP-Datei)  
3. PowerShell öffnen und ins Projektverzeichnis wechseln  
4. Skript starten:  
   ```powershell
   .\Dateimanager.ps1
   ```  

---

## 🖥️ Nutzung  
- Über die grafische Oberfläche können Dateioperationen per Mausklick gestartet werden  
- **Buttons**:  
  - **Copy** → Dateien/Ordner kopieren  
  - **Move** → Dateien/Ordner verschieben  
  - **Delete** → Dateien/Ordner löschen  
  - **Backup/Archive** → Verzeichnis sichern oder archivieren  
  - **Search** → Dateien oder Ordner suchen  
  - **Config Save/Load** → Einstellungen speichern oder laden  
  - **Open Logs** → HTML-Protokolle anzeigen  

---

## 📝 Logging  
Alle ausgeführten Aktionen werden automatisch in einer **HTML-Logdatei** protokolliert.  
Dadurch ist jederzeit nachvollziehbar, wann welche Dateioperation durchgeführt wurde.  

---

## 👨‍💻 Autor  
Chavo Moser  
ICT-Fachmann EFZ (in Ausbildung)  
