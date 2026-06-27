@echo off
setlocal
cd /d "%~dp0"

echo Building Open WebUI with LDAP-only login...
docker compose -f docker-compose.lmstudio.yaml build

echo Recreating Open WebUI (reload .env)...
docker compose -f docker-compose.lmstudio.yaml up -d --force-recreate

echo.
echo Waiting for API...
timeout /t 8 /nobreak >nul

echo Config check:
curl.exe -s http://localhost:3303/api/config | findstr /I "enable_ldap enable_login_form"

echo.
echo Static check:
curl.exe -sI http://localhost:3303/static/auth-ldap-fix.js | findstr /I "HTTP/"

echo.
echo Open WebUI: http://localhost:3303/auth
echo Login: Active Directory username + password only
docker ps --filter name=open-webui --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
