param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$Filter = '*',
    [switch]$Render,
    [switch]$LongRun,
    [string]$OutputDirectory = (Join-Path $env:TEMP 'chronicle-agency-regression')
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$expectedErrors = @{
    'generated_organization_contract_test.gd' = @('ERROR: Unable to open JSON file: res://missing_organization_definition.json')
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$tests = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.gd' | Where-Object {
    $_.Name -like $Filter -and
    ($Render -or $_.Name -notlike '*_render_test.gd') -and
    ($LongRun -or $_.Name -ne 'generated_world_30_day_health_test.gd')
} | Sort-Object FullName
$results = foreach ($test in $tests) {
    $relative = $test.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    $stdout = Join-Path $OutputDirectory ($test.BaseName + '.stdout.log')
    $stderr = Join-Path $OutputDirectory ($test.BaseName + '.stderr.log')
    $arguments = @('--path', ('"' + $projectRoot + '"'), '--script', ('res://' + $relative))
    if ($Render -and $test.Name -like '*_render_test.gd') {
        $arguments += @('--rendering-method', 'gl_compatibility')
    } else {
        $arguments += '--headless'
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timeout = if ($test.Name -eq 'generated_world_30_day_health_test.gd') { 1800000 } else { 600000 }
    $finished = $process.WaitForExit($timeout)
    if (-not $finished) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
    $output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
    $unexpectedErrors = @([regex]::Matches($output, '(?m)^(SCRIPT ERROR:|ERROR:)[^\r\n]*') | ForEach-Object {
        $_.Value
    } | Where-Object { $_ -notin $expectedErrors[$test.Name] })
    $passed = $finished -and $process.ExitCode -eq 0 -and $unexpectedErrors.Count -eq 0
    $row = [pscustomobject]@{ Test = $relative; Passed = $passed; ExitCode = $process.ExitCode; TimedOut = -not $finished; Seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2); UnexpectedErrors = $unexpectedErrors }
    Write-Host ('{0} {1} ({2}s)' -f $(if ($passed) { 'PASS' } else { 'FAIL' }), $relative, $row.Seconds)
    $row
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'results.json') -Encoding utf8
$failed = @($results | Where-Object { -not $_.Passed })
Write-Host ('RESULT {0}/{1} passed. Logs: {2}' -f ($results.Count - $failed.Count), $results.Count, $OutputDirectory)
if ($failed.Count -gt 0) { exit 1 }
