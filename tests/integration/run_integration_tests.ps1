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

$godotProcess = Start-Process -FilePath $godotExecutable -ArgumentList @(
	"--headless",
	"--path",
	"`"$projectPath`"",
	"--scene",
	"res://tests/integration/network_loopback.tscn"
) -NoNewWindow -Wait -PassThru

if ($godotProcess.ExitCode -ne 0) {
	throw "Network loopback integration test failed."
}
