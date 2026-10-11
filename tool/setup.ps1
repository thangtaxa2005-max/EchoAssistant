$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
if (Test-Path '.\.flutter-sdk\bin\flutter.bat') {
    $env:PATH = "$(Resolve-Path '.\.flutter-sdk\bin');$env:PATH"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Chưa tìm thấy Flutter SDK trong PATH. Cài Flutter, mở terminal mới rồi chạy lại script.'
}
flutter create --platforms=android --project-name echo_assistant --org com.echoassistant .
if ($LASTEXITCODE -ne 0) { throw 'flutter create thất bại' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AndroidManifest.xml') -Destination 'android/app/src/main/AndroidManifest.xml' -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build.gradle.kts') -Destination 'android/app/build.gradle.kts' -Force
foreach ($density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "icons/mipmap-$density/ic_launcher.png") -Destination "android/app/src/main/res/mipmap-$density/ic_launcher.png" -Force
}
foreach ($entry in @('kotlin.incremental=false', 'kotlin.compiler.execution.strategy=in-process')) {
    if (-not (Select-String -LiteralPath 'android/gradle.properties' -SimpleMatch $entry -Quiet)) {
        Add-Content -LiteralPath 'android/gradle.properties' -Value $entry
    }
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get thất bại' }
dart run build_runner build
if ($LASTEXITCODE -ne 0) { throw 'Drift code generation thất bại' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze phát hiện lỗi' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test thất bại' }
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk thất bại' }
Write-Host 'APK: build/app/outputs/flutter-apk/app-debug.apk'
