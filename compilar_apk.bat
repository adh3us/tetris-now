@echo off
title Compilador Gameros Tetris APK
cd /d "%~dp0"

echo =========================================================
echo       COMPILACION DIRECTA - GAMEROS TETRIS (FLUTTER)
echo =========================================================
echo.

if exist "android\local.properties" del /f /q "android\local.properties"

echo [1/2] Actualizando dependencias de Flutter...
call flutter pub get

echo.
echo [2/2] Compilando APK nativo de Android...
call flutter build apk --debug --android-skip-build-dependency-validation

echo.
echo =========================================================
set "APK_SRC=%~dp0build\app\outputs\flutter-apk\app-debug.apk"
if exist "%APK_SRC%" (
    echo [EXITO TOTAL] El APK se compilo correctamente.
    echo %APK_SRC%
    echo.
    copy /Y "%APK_SRC%" "%USERPROFILE%\Desktop\Tetris_Now_Debug.apk" >nul 2>&1
    echo APK copiado a tu Escritorio: %USERPROFILE%\Desktop\Tetris_Now_Debug.apk
) else (
    echo [ERROR] No se encontro el APK generado.
)
echo =========================================================
echo.
echo Presiona cualquier tecla para salir...
pause
