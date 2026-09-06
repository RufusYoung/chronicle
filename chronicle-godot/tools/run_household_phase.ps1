param(
    [string]$Godot = 'Godot_v4.6.3-stable_win64_console.exe',
    [string]$OutputDirectory = 'builds/validation/household_phase_frozen',
    [int]$TimeoutSecondsPerCase = 1800
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = Split-Path $project -Parent
$engine = (Get-Command $Godot -ErrorAction Stop).Source
$output = [IO.Path]::GetFullPath($OutputDirectory)
$native = Join-Path $env:APPDATA 'Godot/app_userdata/CHRONICLE_GODOT/tests/food_economy_probe'
New-Item -ItemType Directory -Force -Path $output | Out-Null

function Get-RuntimeFingerprint {
    $files = @(foreach ($folder in @('scripts', 'scenes', 'data')) {
        Get-ChildItem -LiteralPath (Join-Path $project $folder) -Recurse -File
    }) + @(Get-Item -LiteralPath (Join-Path $project 'project.godot'))
    return @($files | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = [IO.Path]::GetRelativePath($project, $_.FullName); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}

$before = Get-RuntimeFingerprint
$manifest = [ordered]@{
    startedUtc = [DateTime]::UtcNow.ToString('o')
    sourceCommit = (& git -C $repo rev-parse HEAD)
    sourceDirty = [bool](& git -C $repo status --porcelain)
    runtime = $before
    probeSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'food_economy_probe.gd') -Algorithm SHA256).Hash
    scope = 'Passive multi-system world evaluation; explicit permission injections in the recovery case. Not human play.'
    cases = @()
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
$cases = @(
    @{ mode = 'canon_livelihood_frozen'; seed = 81001; days = 30 },
    @{ mode = 'canon_livelihood_frozen'; seed = 82002; days = 30 },
    @{ mode = 'canon_livelihood_frozen'; seed = 83003; days = 30 },
    @{ mode = 'canon_livelihood_without_affordability'; seed = 83003; days = 7 },
    @{ mode = 'canon_livelihood_without_subsistence'; seed = 81001; days = 7 },
    @{ mode = 'canon_livelihood_withdraw_reopen'; seed = 81001; days = 14 }
)
foreach ($case in $cases) {
    $id = "$($case.mode)_$($case.seed)"
    $caseOutput = Join-Path $output $id
    New-Item -ItemType Directory -Force -Path $caseOutput | Out-Null
    $stdout = Join-Path $caseOutput 'stdout.log'
    $stderr = Join-Path $caseOutput 'stderr.log'
    $arguments = @('--headless', '--path', ('"' + $project + '"'), '--script', 'res://tools/food_economy_probe.gd', '--', $case.mode, $case.seed, $case.days)
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit($TimeoutSecondsPerCase * 1000)) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw "$id timed out; partial logs retained in $caseOutput"
    }
    if ($process.ExitCode -ne 0 -or @(Select-String -LiteralPath $stderr -Pattern '^(ERROR:|SCRIPT ERROR:)').Count -gt 0 -or
        -not (Select-String -LiteralPath $stdout -SimpleMatch 'FOOD_ECONOMY_RESULT PASS')) {
        throw "$id failed; see $caseOutput"
    }
    $checkpoint = Join-Path (Join-Path $native $id) "day$($case.days).json"
    & python (Join-Path $PSScriptRoot 'audit_resident_life.py') $checkpoint --output (Join-Path $caseOutput 'audit.json') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id audit failed" }
    Copy-Item -LiteralPath (Join-Path (Join-Path $native $id) 'result.json') -Destination (Join-Path $caseOutput 'run.json')
    Compress-Archive -LiteralPath $checkpoint -DestinationPath (Join-Path $caseOutput 'native.zip') -Force
    $audit = Get-Content -LiteralPath (Join-Path $caseOutput 'audit.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($audit.food_balance_remainder -ne 0 -or $audit.initial_currency -ne $audit.remaining_currency -or $audit.resident_count -ne 16) {
        throw "$id failed conservation or population audit"
    }
    $manifest.cases += [ordered]@{ id = $id; days = $case.days; nativeSha256 = $audit.sha256; meals = $audit.consumed_meals; result = 'PASS' }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
    Write-Output "$id PASS: $($audit.consumed_meals) meals, native continuation equal, money and food conserved"
}
$after = Get-RuntimeFingerprint
$manifest.runtimeUnchanged = (($before | ConvertTo-Json -Depth 4 -Compress) -ceq ($after | ConvertTo-Json -Depth 4 -Compress))
$manifest.probeUnchanged = $manifest.probeSha256 -ceq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'food_economy_probe.gd') -Algorithm SHA256).Hash
$manifest.finishedUtc = [DateTime]::UtcNow.ToString('o')
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
if (-not $manifest.runtimeUnchanged -or -not $manifest.probeUnchanged) { throw 'Sources changed during the phase run; not frozen evidence.' }
Write-Output 'HOUSEHOLD_PHASE_RESULT PASS'
