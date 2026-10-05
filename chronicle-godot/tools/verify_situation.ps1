param([string]$Godot = "Godot_v4.6.3-stable_win64_console.exe", [switch]$Render)
$ErrorActionPreference = "Stop"
$Project = Split-Path $PSScriptRoot -Parent
$Logs = Join-Path (Split-Path $Project -Parent) "work/situation-verification"
New-Item -ItemType Directory -Path $Logs -Force | Out-Null
$Tests = @(
    "sim/situation_contract_test", "sim/situation_interaction_test", "sim/situation_consequence_test", "sim/situation_world_test", "sim/situation_continuity_test", "sim/situation_choice_chain_phase2_test", "sim/situation_selfplay_regression_test",
    "sim/goal_pressure_test", "sim/work_recipe_contract_test", "sim/resident_equipment_contract_test", "sim/world_integration_contract_test",
    "sim/combat_equipment_resolution_test", "sim/roaming_journey_contract_test",
    "sim/journey_experience_contract_test", "sim/journey_counterexample_test", "agent/agent_game_session_test"
)
if ($Render) { $Tests = @("rebuild/situation_surface_render_test", "rebuild/goal_pressure_render_test", "rebuild/roaming_player_render_test", "rebuild/roaming_interaction_render_test") }
$Failed = @()
foreach ($Test in $Tests) {
    $Log = Join-Path $Logs (($Test -replace '/', '_') + ".log")
    $Arguments = @('--path', $Project, '--script', "res://tests/$Test.gd", '--log-file', $Log)
    if (-not $Render) { $Arguments = @('--headless') + $Arguments }
    $Process = Start-Process -FilePath (Get-Command $Godot).Source -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    if (-not $Process.WaitForExit(180000)) { Stop-Process -Id $Process.Id; $Failed += $Test; Write-Output "TIMEOUT $Test"; continue }
    $Errors = Select-String -LiteralPath $Log -Pattern 'SCRIPT ERROR:|ERROR:|\[FAIL\]|RESULT FAIL'
    if ($Process.ExitCode -ne 0 -or $Errors) {
        $Failed += $Test
        Write-Output "FAIL $Test"
        $Errors | Select-Object -First 8 | ForEach-Object { Write-Output $_.Line }
    } else { Write-Output "PASS $Test" }
}
Write-Output "SITUATION_VERIFY $($Tests.Count - $Failed.Count)/$($Tests.Count)"
if ($Failed.Count) { exit 1 }
