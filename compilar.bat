@echo off
title Compilando Gameros Tetris APK...
echo ====================================================
echo   AUTOMATIZACION DE COMPILACION - GAMEROS TETRIS
echo ====================================================
echo.

cd /d "%~dp0"

echo [1/3] Limpiando configuraciones previas de Android...
powershell -Command "if (Test-Path 'android\app\src\main\AndroidManifest.xml') { (Get-Content 'android\app\src\main\AndroidManifest.xml') -replace 'package=\"com.gameros.tetris\"', '' | Set-Content 'android\app\src\main\AndroidManifest.xml' }"
powershell -Command "if (Test-Path '..\gameros_auth_ui\lib\src\login_screen.dart') { (Get-Content '..\gameros_auth_ui\lib\src\login_screen.dart') -replace 'EdgeInsets\.bottom\(16\)', 'EdgeInsets.only(bottom: 16)' | Set-Content '..\gameros_auth_ui\lib\src\login_screen.dart' }"
if exist "android\app\build.gradle" del /f /q "android\app\build.gradle"

echo [2/3] Descargando paquetes y dependencias de Flutter...
call flutter pub get

echo [3/3] Compilando APK para celular Android...
call flutter build apk --debug

echo.
echo ====================================================
if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    echo [EXITO] APK generado correctamente en:
    echo %~dp0build\app\outputs\flutter-apk\app-debug.apk
    echo.
    echo Ya puedes pasar ese archivo a tu celular Android.
) else (
    echo [AVISO] Hubo un problema durante la compilacion.
)
echo ====================================================
echo.
pause
