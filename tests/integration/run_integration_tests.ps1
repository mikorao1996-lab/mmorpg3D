$ErrorActionPreference = "Stop"
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$godotExecutable = $env:GODOT_BIN

if ([string]::IsNullOrWhiteSpace($godotExecutable)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -eq $godotCommand) {
		throw "Set GODOT_BIN or add godot to PATH."
	}
	$godotExecutable = $godotCommand.Source
}

$integrationScenes = @(
	"res://tests/integration/network_loopback.tscn",
	"res://tests/integration/client_ui_loopback.tscn",
	"res://tests/integration/quest_loopback.tscn",
	"res://tests/integration/trade_loopback.tscn",
	"res://tests/integration/chat_loopback.tscn",
	"res://tests/integration/landscape_loopback.tscn",
	"res://tests/integration/hub_content_loopback.tscn",
	"res://tests/integration/persistence_loopback.tscn"
)

foreach ($integrationScene in $integrationScenes) {
	$godotProcess = Start-Process -FilePath $godotExecutable -ArgumentList @(
		"--headless",
		"--path",
		"`"$projectPath`"",
		"--scene",
		$integrationScene
	) -NoNewWindow -Wait -PassThru

	if ($godotProcess.ExitCode -ne 0) {
		throw "Integration test failed: $integrationScene"
	}
}
