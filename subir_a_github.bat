@echo off
title Subir Tetris Now a GitHub (adh3us/tetris-now)
echo =========================================================
echo       SUBIR PROYECTO A GITHUB - TETRIS NOW (GAMEROS)
echo =========================================================
echo.

cd /d "%~dp0"

echo [1/4] Inicializando repositorio Git local...
if not exist ".git" (
    git init
    git branch -M main
    git remote add origin https://github.com/adh3us/tetris-now.git
)

echo [2/4] Preparando todos los archivos del proyecto...
git add .

echo [3/4] Creando commit con la version v3.0...
git commit -m "feat: Tetris now by gAmeros v3.0 - New Tetris physics, Monocubes Gold/Silver, Landscape 2v2 and GitHub Actions"

echo [4/4] Subiendo a GitHub (adh3us/tetris-now)...
git push -u origin main --force

echo.
echo =========================================================
echo [EXITO] Archivos subidos a: https://github.com/adh3us/tetris-now
echo.
echo GitHub Actions compilara automaticamente el APK en la nube.
echo Podras descargarlo desde la pestana "Actions" de tu repositorio.
echo =========================================================
echo.
pause
