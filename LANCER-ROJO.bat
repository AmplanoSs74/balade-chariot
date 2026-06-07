@echo off
title Serveur Rojo - Balade en chariot
cd /d "%~dp0"
echo ============================================================
echo   SERVEUR ROJO - Balade en chariot
echo ------------------------------------------------------------
echo   LAISSE CETTE FENETRE OUVERTE pendant que tu joues.
echo   (Si tu la fermes ou redemarres le PC, relance ce fichier.)
echo.
echo   Dans Studio : onglet Plugins -^> Rojo -^> Connect
echo   Adresse 127.0.0.1   Port 34872
echo ============================================================
echo.
rojo.exe serve
echo.
echo *** Le serveur Rojo s'est arrete. Regarde le message au-dessus. ***
pause
