#!/bin/bash

# ============================================
# SCRIPT DE VÉRIFICATION DE CONFORMITÉ
# ============================================
# Vérifie que tous les fichiers sont conformes à la spécification

set -e

echo "========================================"
echo "   Vérification de Conformité"
echo "========================================"
echo ""

ERRORS=0
WARNINGS=0

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        ERRORS=$((ERRORS + 1))
    fi
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

# 1. Vérification des fichiers requis
echo "📁 [1/6] Vérification des fichiers requis..."
[ -f "docker-compose.yml" ] && check "docker-compose.yml présent" || warn "docker-compose.yml manquant"
[ -f "install.sh" ] && check "install.sh présent" || warn "install.sh manquant"
[ -f "backup.sh" ] && check "backup.sh présent" || warn "backup.sh manquant"
[ -f "check-certificate.sh" ] && check "check-certificate.sh présent" || warn "check-certificate.sh manquant"
[ -f "SECURITY_AUDIT.md" ] && check "SECURITY_AUDIT.md présent" || warn "SECURITY_AUDIT.md manquant"

# 2. Vérification docker-compose.yml
echo ""
echo "🐳 [2/6] Vérification docker-compose.yml..."

if [ -f "docker-compose.yml" ]; then
    # Vérifier la syntaxe
    if command -v docker &> /dev/null; then
        docker compose config > /dev/null 2>&1 && check "Syntaxe docker-compose.yml valide" || warn "Erreur de syntaxe dans docker-compose.yml"
    else
        warn "Docker non installé, impossible de vérifier la syntaxe"
    fi
    
    # Vérifier les services
    grep -q "immich_caddy" docker-compose.yml && check "Service caddy défini" || warn "Service caddy manquant"
    grep -q "immich_server" docker-compose.yml && check "Service immich-server défini" || warn "Service immich-server manquant"
    grep -q "immich_postgres" docker-compose.yml && check "Service postgres défini" || warn "Service postgres manquant"
    grep -q "immich_redis" docker-compose.yml && check "Service redis défini" || warn "Service redis manquant"
    
    # Vérifier les réseaux
    grep -q "immich_public" docker-compose.yml && check "Réseau immich_public défini" || warn "Réseau immich_public manquant"
    grep -q "immich_private" docker-compose.yml && check "Réseau immich_private défini" || warn "Réseau immich_private manquant"
    grep -q "internal: true" docker-compose.yml && check "Réseau privé configuré (internal: true)" || warn "Réseau privé non configuré"
    
    # Vérifier les limites de ressources
    grep -q "deploy:" docker-compose.yml && check "Limites de ressources définies" || warn "Limites de ressources manquantes"
    
    # Vérifier Uptime Kuma (localhost uniquement)
    grep -q "127.0.0.1:3001:3001" docker-compose.yml && check "Uptime Kuma limité à localhost" || warn "Uptime Kuma pas limité à localhost"
    
    # Vérifier Redis healthcheck
    grep -q "REDISCLI_AUTH" docker-compose.yml && check "Redis healthcheck utilise REDISCLI_AUTH" || warn "Redis healthcheck ne utilise pas REDISCLI_AUTH"
fi

# 3. Vérification install.sh
echo ""
echo "📜 [3/6] Vérification install.sh..."

if [ -f "install.sh" ]; then
    # Vérifier la structure
    grep -q "set -e" install.sh && check "Gestion erreurs (set -e) présente" || warn "Gestion erreurs manquante"
    grep -q "EUID.*-ne 0" install.sh && check "Vérification root présente" || warn "Vérification root manquante"
    
    # Vérifier génération .env
    grep -q "printf.*DOMAIN" install.sh && check "Génération DOMAIN avec printf" || warn "Génération DOMAIN incorrecte"
    grep -q "printf.*JWT_SECRET" install.sh && check "Génération JWT_SECRET avec printf" || warn "Génération JWT_SECRET incorrecte"
    
    # Vérifier génération Caddyfile
    grep -q "cat > Caddyfile" install.sh && check "Génération Caddyfile présente" || warn "Génération Caddyfile manquante"
    grep -q "sed.*EMAIL" install.sh && check "Substitution EMAIL dans Caddyfile" || warn "Substitution EMAIL manquante"
    grep -q "sed.*DOMAIN" install.sh && check "Substitution DOMAIN dans Caddyfile" || warn "Substitution DOMAIN manquante"
    
    # Vérifier Docker
    grep -q "usermod.*docker" install.sh && check "Ajout utilisateur au groupe docker" || warn "Ajout utilisateur au groupe docker manquant"
    
    # Vérifier Fail2ban
    grep -q "fail2ban/jail.d" install.sh && check "Configuration Fail2ban présente" || warn "Configuration Fail2ban manquante"
fi

# 4. Vérification Caddyfile (si présent)
echo ""
echo "🌐 [4/6] Vérification Caddyfile..."

if [ -f "Caddyfile" ]; then
    grep -q "rate_limit" Caddyfile && check "Rate limiting configuré" || warn "Rate limiting manquant"
    grep -q "Strict-Transport-Security" Caddyfile && check "HSTS configuré" || warn "HSTS manquant"
    grep -q "Content-Security-Policy" Caddyfile && check "CSP configuré" || warn "CSP manquant"
    grep -q "reverse_proxy.*immich-server" Caddyfile && check "Reverse proxy vers immich-server" || warn "Reverse proxy manquant"
    grep -q "redir.*https" Caddyfile && check "Redirection HTTP→HTTPS" || warn "Redirection HTTP→HTTPS manquante"
else
    warn "Caddyfile non présent (sera généré par install.sh)"
fi

# 5. Vérification sécurité
echo ""
echo "🔒 [5/6] Vérification sécurité..."

if [ -f "docker-compose.yml" ]; then
    # Vérifier isolation
    grep -q "immich_private.*# Réseau privé uniquement" docker-compose.yml && check "Isolation réseau configurée" || warn "Isolation réseau à vérifier"
    
    # Vérifier secrets
    grep -q "\${DB_PASSWORD}" docker-compose.yml && check "DB_PASSWORD utilisé" || warn "DB_PASSWORD non utilisé"
    grep -q "\${REDIS_PASSWORD}" docker-compose.yml && check "REDIS_PASSWORD utilisé" || warn "REDIS_PASSWORD non utilisé"
    grep -q "\${JWT_SECRET}" docker-compose.yml && check "JWT_SECRET utilisé" || warn "JWT_SECRET non utilisé"
fi

# 6. Vérification répertoires
echo ""
echo "📂 [6/6] Vérification répertoires..."

[ -d "fail2ban" ] && check "Répertoire fail2ban présent" || warn "Répertoire fail2ban manquant (sera créé par install.sh)"
[ -d "logs" ] && check "Répertoire logs présent" || warn "Répertoire logs manquant (sera créé par install.sh)"

# Résumé
echo ""
echo "========================================"
echo "   RÉSUMÉ"
echo "========================================"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ Tous les éléments sont conformes !${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  $WARNINGS avertissement(s) - Configuration globalement conforme${NC}"
    exit 0
else
    echo -e "${RED}❌ $ERRORS erreur(s) et $WARNINGS avertissement(s) détectés${NC}"
    exit 1
fi

