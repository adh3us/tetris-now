@echo off
title Compilador Automatico Gameros Tetris
echo =========================================================
echo       COMPILADOR AUTOMATIZADO - GAMEROS TETRIS
echo =========================================================
echo.
cd /d "%~dp0"

set /p ANON_KEY="Pega tu Supabase Anon Key (o presiona ENTER directo para Modo Prueba): "

if not "%ANON_KEY%"=="" (
    echo Configurando clave de Supabase...
    powershell -Command "(Get-Content 'lib\core\supabase_config.dart') -replace 'defaultValue: .*', 'defaultValue: \"%ANON_KEY%\",' | Set-Content 'lib\core\supabase_config.dart'"
    echo Clave configurada correctamente.
) else (
    echo Modo Prueba / Invitado habilitado por defecto.
)

echo.
echo [1/2] Limpiando dependencias...
call flutter pub get

echo.
echo [2/2] Compilando archivo APK...
call flutter build apk --debug

echo.
echo =========================================================
if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    echo [EXITO TOTAL] El archivo APK se genero correctamente:
    echo %~dp0build\app\outputs\flutter-apk\app-debug.apk
    echo.
    echo Ya puedes pasarlo a tu celular Android e instalarlo.
) else (
    echo [AVISO] Hubo un problema al generar el APK.
)
echo =========================================================
echo.
pause
