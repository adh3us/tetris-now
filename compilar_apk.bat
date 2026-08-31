@echo off
title Compilador Gameros Tetris APK
echo =========================================================
echo       COMPILACION DIRECTA - GAMEROS TETRIS (FLUTTER)
echo =========================================================
echo.

cd /d "%~dp0"

echo [1/2] Obteniendo dependencias de Flutter...
call flutter pub get

echo.
echo [2/2] Compilando APK nativo de Android...
call flutter build apk --debug --android-skip-build-dependency-validation

echo.
echo =========================================================
if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    echo [EXITO TOTAL] Tu archivo APK se genero correctamente:
    echo %~dp0build\app\outputs\flutter-apk\app-debug.apk
    echo.
    echo Ya puedes pasarlo a tu celular Android para instalarlo.
) else (
    echo [AVISO] Hubo un error durante la compilacion.
)
echo =========================================================
echo.
pause
