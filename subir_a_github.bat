@echo off
chcp 65001 >nul
title Subir a GitHub: Rama victor/hp-combat-v2
echo =========================================================
echo    SUBIR PROYECTO A GITHUB - RAMA victor/hp-combat-v2
echo =========================================================
echo.

cd /d "%~dp0"

echo [1/4] Configurando repositorio e identidad de Git...
if not exist ".git" (
    git init
)
git config user.email "sallagovictor@gmail.com"
git config user.name "adh3us"
git remote remove origin >nul 2>&1
git remote add origin https://github.com/adh3us/tetris-now.git
git checkout -b victor/hp-combat-v2 2>nul || git checkout victor/hp-combat-v2

echo.
echo [2/4] Agregando archivos de codigo fuente y audios...
git add -A

echo.
echo [3/4] Creando commit...
git commit -m "feat(combat): Sistema HP 100, lineas diamantadas, arenas dinamicas y presencia corregida"

echo.
echo [4/4] Enviando rama a GitHub (origin/victor/hp-combat-v2)...
git push -u origin victor/hp-combat-v2 --force

echo.
echo =========================================================
if %ERRORLEVEL% EQU 0 (
    echo [EXITO TOTAL] El codigo se subio a la rama victor/hp-combat-v2!
    echo.
    echo Claude ya puede ver y comparar tu codigo en:
    echo https://github.com/adh3us/tetris-now/tree/victor/hp-combat-v2
) else (
    echo [AVISO] Ocurrio un inconveniente al enviar a GitHub.
)
echo =========================================================
echo.
pause
