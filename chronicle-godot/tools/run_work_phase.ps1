param(
    [string]$Godot = 'Godot_v4.6.3-stable_win64_console.exe',
    [string]$Python = 'C:\Users\x4473\anaconda3\python.exe',
    [switch]$Resume,
    [string]$RunLabel = 'frozen3',
    [int[]]$Seeds = @(81001, 82002, 83003),
    [switch]$SkipAblations,
    [ValidateSet('work', 'community')][string]$Framework = 'work',
    [ValidateRange(1, 30)][int]$Days = 7,
    [ValidateRange(30, 1800)][int]$CaseTimeoutSeconds = 900,
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Get-Command $Godot).Source
if ($Seeds.Count -eq 0 -or $RunLabel -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Specify seeds and a simple run label.' }
if ($OutputDirectory -eq '') {
    $OutputDirectory = Join-Path $PSScriptRoot ('..\texts\reports\2026\2026-9\2026-9-08\work_framework_evidence\' + $RunLabel)
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
function Get-RuntimeManifest {
    $paths = @('scripts', 'data', 'scenes') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $root $_) -Recurse -File | Where-Object { $_.Extension -in @('.gd', '.json', '.tscn') }
    }
    @($paths | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName.Substring($root.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }) | ConvertTo-Json -Depth 3 -Compress
}
$manifest = Get-RuntimeManifest
$configuration = [ordered]@{ Framework = $Framework; Days = $Days; Seeds = @($Seeds); SkipAblations = [bool]$SkipAblations; RunLabel = $RunLabel } | ConvertTo-Json -Depth 3 -Compress
if ($Resume -and (Get-Content -LiteralPath (Join-Path $OutputDirectory 'run_configuration.json') -Raw -Encoding UTF8).Trim() -ne $configuration) {
    throw 'Cannot resume with different seeds, duration or mechanisms.'
}
$configuration | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run_configuration.json') -Encoding UTF8
if ($Resume -and (Get-Content -LiteralPath (Join-Path $OutputDirectory 'runtime_manifest.json') -Raw -Encoding UTF8).Trim() -ne $manifest) {
    throw 'Cannot resume after a runtime change.'
}
$manifest | Set-Content -LiteralPath (Join-Path $OutputDirectory 'runtime_manifest.json') -Encoding UTF8
$prefix = 'canon_' + $Framework + '_'
$cases = @($Seeds | ForEach-Object { @{ Mode = $prefix + $RunLabel; Seed = $_ } })
if (-not $SkipAblations) {
    $ablations = if ($Framework -eq 'work') { @('repair', 'supply', 'wear') } else { @('messages', 'policy', 'social') }
    $cases += $ablations | ForEach-Object {
        @{ Mode = $prefix + 'without_' + $_ + '_' + $RunLabel; Seed = $Seeds[0] }
    }
}
$results = @()
foreach ($case in $cases) {
    $label = '{0}_{1}' -f $case.Mode, $case.Seed
    $stdout = Join-Path $OutputDirectory ($label + '.stdout.log')
    $stderr = Join-Path $OutputDirectory ($label + '.stderr.log')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $reuse = $Resume -and (Test-Path -LiteralPath $stdout) -and (Test-Path -LiteralPath $stderr) -and
        ([string](Get-Content -LiteralPath $stdout -Raw -Encoding UTF8) -match 'FOOD_ECONOMY_RESULT PASS') -and
        ([string](Get-Content -LiteralPath $stderr -Raw -Encoding UTF8) -notmatch '(SCRIPT ERROR:|ERROR:)')
    $exitCode = 0
    if (-not $reuse) {
        $process = Start-Process -FilePath $engine -ArgumentList @('--headless', '--path', ('"' + $root + '"'), '--script', 'res://tools/food_economy_probe.gd', '--', $case.Mode, $case.Seed, $Days) -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Write-Host ('RUN {0} PID={1}' -f $label, $process.Id)
        $finished = $process.WaitForExit($CaseTimeoutSeconds * 1000)
        if (-not $finished) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
        $exitCode = $process.ExitCode
    } else {
        $finished = $true
        Write-Host ('REUSE {0}: completed passive run with unchanged runtime manifest' -f $label)
    }
    $errors = [string](Get-Content -LiteralPath $stderr -Raw -Encoding UTF8)
    $passed = $finished -and $exitCode -eq 0 -and $errors -notmatch '(SCRIPT ERROR:|ERROR:)' -and
        ([string](Get-Content -LiteralPath $stdout -Raw -Encoding UTF8) -match 'FOOD_ECONOMY_RESULT PASS')
    if ($passed) {
        $directory = Join-Path $env:APPDATA ('Godot\app_userdata\CHRONICLE_GODOT\tests\food_economy_probe\' + $label)
        $audit = if ($Framework -eq 'work') { 'audit_work_framework.py' } else { 'audit_community_life.py' }
        & $Python (Join-Path $PSScriptRoot $audit) (Join-Path $directory ('day' + $Days + '.json')) --output (Join-Path $OutputDirectory ($label + '.audit.json'))
        $passed = $LASTEXITCODE -eq 0
        Copy-Item -LiteralPath (Join-Path $directory 'result.json') -Destination (Join-Path $OutputDirectory ($label + '.probe.json'))
    }
    $results += [pscustomobject]@{ Case = $label; Passed = $passed; ExitCode = $exitCode; ReusedCompletedSimulation = $reuse; SecondsThisInvocation = [math]::Round($timer.Elapsed.TotalSeconds, 2) }
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
    Write-Host ('{0} {1} {2}s' -f $(if ($passed) {'PASS'} else {'FAIL'}), $label, $results[-1].SecondsThisInvocation)
    if (-not $passed) { exit 1 }
}
if ((Get-RuntimeManifest) -ne $manifest) { throw 'Runtime changed during frozen evaluation.' }
Write-Host 'WORK_PHASE_EXECUTION_PASS: native continuation and audits completed; inspect causal acceptance separately.'
