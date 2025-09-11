# File Manager

A simple PowerShell file manager with a graphical interface. The script can search files by extension and copy, move, rename, zip, or back up the selected items. All actions are logged to `FileManager.log`.

## Requirements
- PowerShell 7+
- Windows with .NET for the GUI

## Usage
```powershell
pwsh -File ./Datei-Manager.ps1
```
When closing, the script saves the last used paths to `config.json` in the script folder.

## Features
- Search files by extension
- Copy or move selected files
- Rename selected files
- Create a ZIP archive of selected files
- Create a backup of the selection
- Log all actions
