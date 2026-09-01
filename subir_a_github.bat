@echo off
chcp 65001 >nul
title Subir Tetris Now a GitHub
echo =========================================================
echo       SUBIR PROYECTO A GITHUB - TETRIS NOW (GAMEROS)
echo =========================================================
echo.

cd /d "%~dp0"

echo [1/4] Configurando repositorio local...
if not exist ".git" (
    git init
)
git remote remove origin >nul 2>&1
git remote add origin https://github.com/adh3us/tetris-now.git
git branch -M main

echo [2/4] Indexando todos los archivos y audios (git add -A)...
git add -A

echo [3/4] Creando commit...
git commit -m "feat(audio): Fase D2 - Sonido SFX, Menu 2 Botones y Graficos 3D"

echo [4/4] Enviando a GitHub (origin/main)...
git push -u origin main --force

echo.
echo =========================================================
if %ERRORLEVEL% EQU 0 (
    echo [EXITO TOTAL] El codigo se subio correctamente a GitHub.
    echo.
    echo GitHub Actions esta compilando el APK en la nube.
    echo En 2 minutos podras descargarlo e instalarlo desde:
    echo https://github.com/adh3us/tetris-now/releases/tag/latest-apk
) else (
    echo [AVISO] Ocurrio un inconveniente al enviar a GitHub.
)
echo =========================================================
echo.
pause
