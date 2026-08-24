$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$usagePath = Join-Path $repoRoot 'app\build\app\outputs\mapping\release\usage.txt'
$registrantPath = Join-Path $repoRoot 'app\android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'

if (-not (Test-Path -LiteralPath $usagePath)) {
    throw "Release R8 report not found: $usagePath"
}
if (-not (Test-Path -LiteralPath $registrantPath)) {
    throw "Flutter plugin registrant not found: $registrantPath"
}

$requiredPlugins = @(
    'com.mr.flutter.plugin.filepicker.FilePickerPlugin',
    'com.lib.flutter_blue_plus.FlutterBluePlusPlugin',
    'com.baseflow.permissionhandler.PermissionHandlerPlugin',
    'com.github.dart_lang.jni.JniPlugin',
    'com.github.dart_lang.jni_flutter.JniFlutterPlugin'
)
$usage = Get-Content -LiteralPath $usagePath
$registrant = Get-Content -LiteralPath $registrantPath -Raw

foreach ($plugin in $requiredPlugins) {
    if ($registrant -notmatch [regex]::Escape($plugin)) {
        throw "Required plugin is missing from GeneratedPluginRegistrant: $plugin"
    }
    if ($usage -contains $plugin) {
        throw "Required plugin was removed from release APK by R8: $plugin"
    }
}

Write-Host 'Android release plugins: OK'
