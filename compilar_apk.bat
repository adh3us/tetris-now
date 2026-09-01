@echo off
chcp 65001 >nul
title Compilador Gameros Tetris APK
echo =========================================================
echo       COMPILACION DIRECTA - GAMEROS TETRIS (FLUTTER)
echo =========================================================
echo.

cd /d "%~dp0"

if exist "android\local.properties" del /f /q "android\local.properties"

echo [1/2] Obteniendo dependencias de Flutter...
call flutter pub get

echo.
echo [2/2] Compilando APK nativo de Android...
call flutter build apk --debug --android-skip-build-dependency-validation

echo.
echo =========================================================
set "APK_SRC=%~dp0build\app\outputs\flutter-apk\app-debug.apk"

if exist "%APK_SRC%" (
    echo [EXITO TOTAL] Tu archivo APK se genero correctamente:
    echo %APK_SRC%
    echo.
    copy /Y "%APK_SRC%" "%USERPROFILE%\Desktop\Tetris_Now_Debug.apk" >nul 2>&1
    if exist "%USERPROFILE%\Desktop\Tetris_Now_Debug.apk" (
        echo [COPIA EN ESCRITORIO] %USERPROFILE%\Desktop\Tetris_Now_Debug.apk
    )
    if exist "G:\Mi unidad" (
        copy /Y "%APK_SRC%" "G:\Mi unidad\Tetris_Now_Debug.apk" >nul 2>&1
        echo [GOOGLE DRIVE] Copiado a G:\Mi unidad\Tetris_Now_Debug.apk
    )
) else (
    echo [AVISO] Hubo un error durante la compilacion.
)
echo =========================================================
echo.
pause
