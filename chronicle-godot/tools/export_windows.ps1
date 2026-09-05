param(
    [string]$Godot = 'Godot_v4.6.3-stable_win64_console.exe',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\builds\h1-windows')
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$engine = (Get-Command $Godot -ErrorAction Stop).Source
$arguments = @('--headless', '--path', ('"' + $project + '"'), '--export-release', '"Chronicle Windows H1"', ('"' + (Join-Path $output 'Chronicle.exe') + '"'))
$stdout = Join-Path $output 'export.stdout.log'
$stderr = Join-Path $output 'export.stderr.log'
$process = Start-Process -FilePath $engine -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit(600000)) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
    throw 'Windows export timed out; see export logs.'
}
$errors = @(Select-String -LiteralPath $stderr -Pattern '^(ERROR:|SCRIPT ERROR:)')
if ($process.ExitCode -ne 0 -or $errors.Count -gt 0) {
    throw "Windows export failed (exit $($process.ExitCode)); see $stderr"
}
foreach ($file in @('Chronicle.exe', 'Chronicle.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $output $file))) { throw "Missing $file" }
}
$smokeLog = Join-Path $output 'startup_smoke.log'
$smoke = Start-Process -FilePath (Join-Path $output 'Chronicle.exe') -ArgumentList @('--headless', '--quit-after', '10', '--log-file', ('"' + $smokeLog + '"')) -WorkingDirectory $output -PassThru -WindowStyle Hidden
if (-not $smoke.WaitForExit(120000)) {
    & taskkill.exe /PID $smoke.Id /T /F | Out-Null
    throw 'Standalone startup timed out.'
}
$smokeText = Get-Content -LiteralPath $smokeLog -Encoding UTF8 -Raw
if ($smoke.ExitCode -ne 0 -or $smokeText -match '(?m)^(ERROR:|SCRIPT ERROR:)' -or $smokeText -notmatch 'CHRONICLE_WORLD_READY') {
    throw "Standalone startup failed despite export status; see $smokeLog"
}
Copy-Item -LiteralPath (Join-Path $project 'texts\build\H1_WINDOWS_README.md') -Destination (Join-Path $output 'README.md')
Copy-Item -LiteralPath (Join-Path $project 'assets\world\ASSET_PROVENANCE.md') -Destination (Join-Path $output 'ASSET_PROVENANCE.md')
Copy-Item -LiteralPath (Join-Path $project 'assets\fonts\SOURCE_HAN_SERIF_LICENSE.txt') -Destination (Join-Path $output 'SOURCE_HAN_SERIF_LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $project 'texts\build\GODOT_COPYRIGHT.txt') -Destination (Join-Path $output 'GODOT_COPYRIGHT.txt')
$manifest = [ordered]@{
    createdUtc = [DateTime]::UtcNow.ToString('o')
    sourceCommit = (& git -C $project rev-parse HEAD)
    sourceDirty = [bool](& git -C $project status --porcelain)
    kind = 'H1 internal Windows smoke build, not a submission candidate'
    files = @(Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Extension -in @('.exe', '.pck') } | ForEach-Object {
        @{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build_manifest.json') -Encoding UTF8
Write-Output "Windows package: $output"
