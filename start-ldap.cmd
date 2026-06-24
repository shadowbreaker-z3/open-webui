@echo off
setlocal
cd /d "%~dp0"

echo Building Open WebUI with LDAP-only login...
docker compose -f docker-compose.lmstudio.yaml build

echo Starting Open WebUI...
docker compose -f docker-compose.lmstudio.yaml up -d

echo.
echo Open WebUI: http://localhost:3303/auth
echo Login: Active Directory username + password only
docker ps --filter name=open-webui --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
