# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "File Processing Tool"
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = "CenterScreen"

# Create a button for "Create Staging Folder"
$btnCreateStaging = New-Object System.Windows.Forms.Button
$btnCreateStaging.Text = "Create Staging Folder"
$btnCreateStaging.Size = New-Object System.Drawing.Size(150, 30)
$btnCreateStaging.Location = New-Object System.Drawing.Point(20, 20)
$btnCreateStaging.Add_Click({
    $stagingFolder = Create-Staging-Folder
    [System.Windows.Forms.MessageBox]::Show("Staging folder created at: $stagingFolder")
})

# Create a button for "Collect Files"
$btnCollectFiles = New-Object System.Windows.Forms.Button
$btnCollectFiles.Text = "Collect Files"
$btnCollectFiles.Size = New-Object System.Drawing.Size(150, 30)
$btnCollectFiles.Location = New-Object System.Drawing.Point(20, 70)
$btnCollectFiles.Add_Click({
    $sourceFolder = [System.Windows.Forms.FolderBrowserDialog]::new().ShowDialog()
    if ($sourceFolder -eq [System.Windows.Forms.DialogResult]::OK) {
        Collect-Files -SourceFolder $sourceFolder.SelectedPath
        [System.Windows.Forms.MessageBox]::Show("Files collected from: $sourceFolder")
    }
})

# Create a button for "Copy to Staging"
$btnCopyToStaging = New-Object System.Windows.Forms.Button
$btnCopyToStaging.Text = "Copy to Staging"
$btnCopyToStaging.Size = New-Object System.Drawing.Size(150, 30)
$btnCopyToStaging.Location = New-Object System.Drawing.Point(20, 120)
$btnCopyToStaging.Add_Click({
    $sourceFolder = [System.Windows.Forms.FolderBrowserDialog]::new().ShowDialog()
    if ($sourceFolder -eq [System.Windows.Forms.DialogResult]::OK) {
        $stagingFolder = Create-Staging-Folder
        Copy-To-Staging -SourceFolder $sourceFolder.SelectedPath -StagingFolder $stagingFolder
        [System.Windows.Forms.MessageBox]::Show("Files copied to staging folder: $stagingFolder")
    }
})

# Create a button for "Create ZIP"
$btnCreateZIP = New-Object System.Windows.Forms.Button
$btnCreateZIP.Text = "Create ZIP"
$btnCreateZIP.Size = New-Object System.Drawing.Size(150, 30)
$btnCreateZIP.Location = New-Object System.Drawing.Point(20, 170)
$btnCreateZIP.Add_Click({
    $stagingFolder = Create-Staging-Folder
    Create-ZIP -StagingFolder $stagingFolder
    [System.Windows.Forms.MessageBox]::Show("ZIP archive created from staging folder: $stagingFolder")
})

# Add buttons to the form
$form.Controls.Add($btnCreateStaging)
$form.Controls.Add($btnCollectFiles)
$form.Controls.Add($btnCopyToStaging)
$form.Controls.Add($btnCreateZIP)

# Show the form
[void]$form.ShowDialog()

# Functions
function Create-Staging-Folder {
    $StagingFolder = Join-Path -Path $env:TEMP -ChildPath "Staging"
    if (-not (Test-Path -Path $StagingFolder)) {
        New-Item -ItemType Directory -Path $StagingFolder | Out-Null
    }
    return $StagingFolder
}

function Collect-Files {
    param (
        [string]$SourceFolder
    )
    Write-Host "Dateien werden gesammelt und Excludes angewendet..."
    # Placeholder for file collection logic
}

function Copy-To-Staging {
    param (
        [string]$SourceFolder,
        [string]$StagingFolder
    )
    Write-Host "Dateien werden in Staging kopiert..."
    # Placeholder for file copy logic
}

function Create-ZIP {
    param (
        [string]$StagingFolder
    )
    Write-Host "ZIP Archiv wird erzeugt..."
    # Placeholder for ZIP creation logic
}