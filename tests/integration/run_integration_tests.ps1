$serverExecutable = "D:\Dev\Godot_v4.7.2-stable_win64.exe"
$projectPath = "D:\Dev\mmorpg3D"

$server = Start-Process -FilePath $serverExecutable -ArgumentList @(
	"--headless",
	"--path",
	$projectPath,
	"--scene",
	"res://server/main/server_main.tscn"
) -PassThru

try {
	Start-Sleep -Seconds 1
	& $serverExecutable --headless --path $projectPath --scene "res://tests/integration/handshake_client.tscn"
	if ($LASTEXITCODE -ne 0) {
		throw "Valid handshake test failed"
	}

	& $serverExecutable --headless --path $projectPath --scene "res://tests/integration/handshake_client.tscn" --mismatched
	if ($LASTEXITCODE -ne 0) {
		throw "Protocol mismatch test failed"
	}
}
finally {
	Stop-Process -Id $server.Id
}
