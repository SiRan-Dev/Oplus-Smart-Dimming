$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$packageDir = Join-Path $root "build\release-package"
$moduleProp = Get-Content (Join-Path $root "module.prop")
$version = (($moduleProp | Where-Object { $_ -like "version=*" }) -replace "^version=", "").Trim().ToLower()
$versionSlug = $version -replace "[^a-z0-9]+", ""
$zipPath = Join-Path $root "build\oplus_smart_dimming_${versionSlug}_release.zip"

New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
Remove-Item -Recurse -Force (Join-Path $packageDir "*") -ErrorAction SilentlyContinue

$paths = @(
    "module.prop",
    "service.sh",
    "customize.sh",
    "META-INF"
)

foreach ($relativePath in $paths) {
    $source = Join-Path $root $relativePath
    if (Test-Path $source) {
        Copy-Item $source -Destination $packageDir -Recurse
    }
}

$runtimeScriptsDir = Join-Path $packageDir "scripts"
New-Item -ItemType Directory -Force -Path $runtimeScriptsDir | Out-Null

$runtimeScripts = @(
    "common.sh"
)

foreach ($scriptName in $runtimeScripts) {
    $source = Join-Path (Join-Path $root "scripts") $scriptName
    if (Test-Path $source) {
        Copy-Item $source -Destination $runtimeScriptsDir
    }
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $packageRoot = (Resolve-Path $packageDir).Path.TrimEnd("\", "/")
    Get-ChildItem -Path $packageDir -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length + 1)
        $entryName = $relative.Replace([System.IO.Path]::DirectorySeparatorChar, "/")
        $entryName = $entryName.Replace([System.IO.Path]::AltDirectorySeparatorChar, "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $_.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

$requiredEntries = @(
    "module.prop",
    "service.sh",
    "customize.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "scripts/common.sh"
)

$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    $badEntries = @($entries | Where-Object { $_ -like "*\*" })
    if ($badEntries.Count -gt 0) {
        throw "Zip contains Windows-style paths: $($badEntries -join ', ')"
    }

    foreach ($entry in $requiredEntries) {
        if ($entries -notcontains $entry) {
            throw "Zip is missing required entry: $entry"
        }
    }
}
finally {
    $zip.Dispose()
}

Remove-Item -Recurse -Force $packageDir -ErrorAction SilentlyContinue

Get-Item $zipPath | Select-Object FullName, Length, LastWriteTime
