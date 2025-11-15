#!/bin/bash

# ============================================
# SCRIPT DE MISE À JOUR DU CADDYFILE
# ============================================
# Régénère le Caddyfile depuis le fichier .env
# Usage: ./update-caddyfile.sh

set -e

echo "========================================"
echo "   Mise à jour du Caddyfile"
echo "========================================"
echo ""

# Charger les variables d'environnement
if [ ! -f .env ]; then
    echo "❌ Erreur: Le fichier .env n'existe pas"
    exit 1
fi

source .env

if [ -z "$DOMAIN" ]; then
    echo "❌ Erreur: Variable DOMAIN non définie dans .env"
    exit 1
fi

if [ -z "$EMAIL" ]; then
    echo "❌ Erreur: Variable EMAIL non définie dans .env"
    exit 1
fi

echo "✓ Domaine: ${DOMAIN}"
echo "✓ Email: ${EMAIL}"
echo ""

# Générer le Caddyfile avec template
cat > Caddyfile << 'EOF'
{
    email ${EMAIL}
    admin off
    
    log {
        output file /var/log/caddy/access.log {
            roll_size 10mb
            roll_keep 5
            roll_keep_for 720h
        }
        format json
        level INFO
    }
}

{$DOMAIN} {
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), microphone=(), camera=(self)"
        # CSP: 'unsafe-inline' et 'unsafe-eval' nécessaires pour Immich (React/JS moderne)
        # Alternative plus stricte possible avec nonces, mais nécessite modifications app
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; frame-ancestors 'self';"
        -Server
        -X-Powered-By
    }

    # Note: Rate limiting géré par Fail2ban
    # Le module rate_limit nécessite une image Caddy personnalisée avec le module http.ratelimit
    # Fail2ban fournit une protection efficace contre les attaques brute force

    @uploads {
        path /api/asset/upload
    }
    
    reverse_proxy @uploads immich-server:2283 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        
        transport http {
            read_timeout 30m
            write_timeout 30m
        }
    }

    reverse_proxy immich-server:2283 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        
        transport http {
            read_timeout 5m
            write_timeout 5m
        }
    }
}

http://{$DOMAIN} {
    redir https://{host}{uri} permanent
}
EOF

# Remplacer les variables dans le Caddyfile
ESCAPED_EMAIL=$(printf '%s\n' "$EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
ESCAPED_DOMAIN=$(printf '%s\n' "$DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')

# Remplacer ${EMAIL}
sed -i "s/\${EMAIL}/${ESCAPED_EMAIL}/g" Caddyfile

# Remplacer {$DOMAIN}
sed -i "s/{\$DOMAIN}/${ESCAPED_DOMAIN}/g" Caddyfile

echo "✅ Caddyfile mis à jour avec le domaine ${DOMAIN} et l'email ${EMAIL}"
echo ""
echo "📝 Prochaine étape: Redémarrer Caddy pour appliquer les changements:"
echo "   docker compose restart caddy"

