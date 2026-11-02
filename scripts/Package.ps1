$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$files = @('Backend.cs','Widget.ps1','Views.ps1','Resize.ps1','Rings.cs','Sizing.cs','Install.ps1','Install.vbs','Start.vbs','codex-limits.ico','codex-limits.png','README.md','LICENSE','VERSION','tests/Check-WidgetLayout.ps1','docs/compact.png','docs/standard.png','docs/dark-dropdown.png')
$destination = Join-Path $root 'dist'
[void](New-Item -ItemType Directory -Path $destination -Force)
$archive = Join-Path $destination 'codex-limits-widget-windows-en.zip'
$staging = Join-Path $destination ('staging-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $staging 'CodexLimits'
try {
    foreach ($relative in $files) {
        $target = Join-Path $payload $relative
        [void](New-Item -ItemType Directory -Path (Split-Path $target) -Force)
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target
    }
    Compress-Archive -LiteralPath $payload -DestinationPath $archive -Force
} finally {
    if (Test-Path -LiteralPath $staging) {
        $resolved = [IO.Path]::GetFullPath($staging)
        $allowed = [IO.Path]::GetFullPath($destination).TrimEnd('\') + '\'
        if (!$resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid staging path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash + '  ' + (Split-Path $archive -Leaf) | Set-Content (Join-Path $destination 'SHA256SUMS.txt') -Encoding Ascii
Write-Output $archive
