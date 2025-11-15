#!/bin/bash

# ============================================
# SCRIPT D'INSTALLATION IMMICH SÉCURISÉ
# ============================================
# Pour Ubuntu/Debian
# Usage: sudo ./install.sh

set -e

echo "========================================"
echo "   Installation Immich Sécurisé"
echo "========================================"
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ce script doit être exécuté en root (sudo)"
    exit 1
fi

# ============================================
# 1. INSTALLATION DES DÉPENDANCES
# ============================================
echo "📦 [1/8] Installation des dépendances..."

apt-get update
apt-get install -y \
    curl \
    git \
    rsync \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release

echo "✓ Dépendances installées"

# ============================================
# 2. INSTALLATION DOCKER
# ============================================
echo "🐳 [2/8] Installation Docker..."

if ! command -v docker &> /dev/null; then
    echo "Installation de Docker via le script officiel..."
    
    # Nettoyer les anciens dépôts qui pourraient causer des conflits
    rm -f /etc/apt/sources.list.d/docker.list
    
    # Télécharger et exécuter le script officiel Docker
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    
    # Démarrer Docker
    systemctl enable docker
    systemctl start docker
    
    # Vérifier l'installation
    if docker --version &> /dev/null && docker compose version &> /dev/null; then
        echo "✓ Docker installé avec succès"
        docker --version
        docker compose version
    else
        echo "❌ Erreur lors de l'installation de Docker"
        exit 1
    fi
else
    echo "✓ Docker déjà installé"
    docker --version
    docker compose version
fi

# Ajouter l'utilisateur au groupe docker (si pas déjà root)
if [ -n "$SUDO_USER" ]; then
    echo "Ajout de l'utilisateur $SUDO_USER au groupe docker..."
    usermod -aG docker "$SUDO_USER"
    echo "✓ Utilisateur $SUDO_USER ajouté au groupe docker"
    echo "⚠️  Note: Vous devrez vous déconnecter/reconnecter pour que les changements prennent effet"
fi

# ============================================
# 3. CONFIGURATION DU RÉPERTOIRE D'INSTALLATION
# ============================================
echo "📁 [3/8] Configuration des répertoires..."

# Utiliser le répertoire courant
INSTALL_DIR=$(pwd)

echo "Installation dans: ${INSTALL_DIR}"

# Créer les sous-répertoires nécessaires
mkdir -p logs
mkdir -p caddy_data
mkdir -p caddy_config
mkdir -p fail2ban/jail.d
mkdir -p fail2ban/filter.d
mkdir -p uptime-kuma
mkdir -p backups  # Répertoire pour les backups

echo "✓ Répertoires créés dans ${INSTALL_DIR}"

# ============================================
# 4. CONFIGURATION STOCKAGE PHOTOS
# ============================================
echo "💾 [4/8] Configuration du stockage..."

# Proposer un chemin dans le workspace par défaut
DEFAULT_PHOTOS_PATH="${INSTALL_DIR}/data/photos"

echo -n "Chemin pour stocker les photos [${DEFAULT_PHOTOS_PATH}]: "
read -r PHOTOS_PATH
PHOTOS_PATH=${PHOTOS_PATH:-${DEFAULT_PHOTOS_PATH}}

# Convertir en chemin absolu si chemin relatif
if [[ ! "$PHOTOS_PATH" = /* ]]; then
    PHOTOS_PATH="${INSTALL_DIR}/${PHOTOS_PATH}"
fi

mkdir -p ${PHOTOS_PATH}
chmod 755 ${PHOTOS_PATH}

echo "✓ Stockage configuré: ${PHOTOS_PATH}"

# ============================================
# 5. GÉNÉRATION DES SECRETS
# ============================================
echo "🔐 [5/8] Génération des secrets de sécurité..."

DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')

echo "✓ Secrets générés"

# ============================================
# 6. CONFIGURATION DOMAINE
# ============================================
echo "🌐 [6/8] Configuration du domaine..."

echo ""
echo -n "Votre domaine Free (ex: photos.monnom.freeboxos.fr): "
read -r DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ Le domaine est obligatoire"
    exit 1
fi

echo -n "Votre email pour Let's Encrypt: "
read -r EMAIL

if [ -z "$EMAIL" ]; then
    echo "❌ L'email est obligatoire"
    exit 1
fi

echo ""
echo "✓ Domaine: ${DOMAIN}"
echo "✓ Email: ${EMAIL}"
echo ""
# Détecter WSL pour afficher les bonnes instructions
IS_WSL_INSTALL=false
WSL_HOST_IP_INSTALL=""
if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
    IS_WSL_INSTALL=true
    if [ -f /etc/resolv.conf ]; then
        WSL_HOST_IP_INSTALL=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -1)
    fi
fi

echo "⚠️  IMPORTANT - Certificat Let's Encrypt:"
echo "   Pour générer automatiquement le certificat SSL, vous DEVEZ:"
echo "   1. Ouvrir les ports 80 (HTTP) et 443 (HTTPS) sur votre Freebox"
if [ "$IS_WSL_INSTALL" = true ] && [ -n "$WSL_HOST_IP_INSTALL" ]; then
    echo "   2. Rediriger ces ports vers l'IP de l'hôte Windows: ${WSL_HOST_IP_INSTALL}"
    echo "      (WSL détecté - utilisez l'IP Windows, pas l'IP WSL interne)"
else
    echo "   2. Rediriger ces ports vers cette machine (IP: $(hostname -I | awk '{print $1}'))"
fi
echo "   3. Configurer votre domaine Free pour pointer vers votre IP publique"
echo "   4. Attendre que le DNS se propage (peut prendre quelques minutes)"
echo ""
if [ "$IS_WSL_INSTALL" = true ]; then
    echo "   ℹ️  Note WSL: Docker expose automatiquement les ports sur l'hôte Windows"
    echo "      Les ports 80/443 seront accessibles depuis Windows sur localhost"
    echo "      Pour l'accès externe, configurez le port forwarding vers l'IP Windows ci-dessus"
    echo ""
fi
echo "   Si vous ne pouvez PAS ouvrir le port 80, le certificat ne pourra pas être généré"
echo "   automatiquement. Vous devrez utiliser une méthode DNS-01 (plus complexe)."
echo ""

# ============================================
# 7. CRÉATION DES FICHIERS DE CONFIGURATION
# ============================================
echo "⚙️  [7/8] Création des fichiers de configuration..."

# Supprimer l'ancien .env s'il existe pour éviter les problèmes
if [ -f .env ]; then
    echo "Suppression de l'ancien fichier .env..."
    rm -f .env
fi

# Fichier .env - Utiliser printf pour éviter les problèmes de caractères spéciaux
printf '# Configuration Immich - Généré le %s\n' "$(date)" > .env
printf 'DOMAIN=%s\n' "${DOMAIN}" >> .env
printf 'EMAIL=%s\n' "${EMAIL}" >> .env
printf 'UPLOAD_LOCATION=%s\n' "${PHOTOS_PATH}" >> .env
printf '\n' >> .env
printf '# Base de données\n' >> .env
printf 'DB_USERNAME=immich\n' >> .env
printf 'DB_DATABASE_NAME=immich\n' >> .env
printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}" >> .env
printf '\n' >> .env
printf '# Redis\n' >> .env
printf 'REDIS_PASSWORD=%s\n' "${REDIS_PASSWORD}" >> .env
printf '\n' >> .env
printf '# Sécurité\n' >> .env
printf 'JWT_SECRET=%s\n' "${JWT_SECRET}" >> .env
printf '\n' >> .env
printf '# Optionnel\n' >> .env
printf 'NOTIFICATION_URL=\n' >> .env
printf 'TZ=Europe/Paris\n' >> .env

# Vérifier que le fichier .env a été créé correctement
if [ ! -f .env ] || [ ! -s .env ]; then
    echo "❌ Erreur lors de la création du fichier .env"
    exit 1
fi
echo "✓ Fichier .env créé"

# Caddyfile
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

# Remplacer ${EMAIL} et {$DOMAIN} dans Caddyfile
# Note: Caddy utilise {$DOMAIN} (accolades Caddy), pas ${DOMAIN} (shell)
# Échapper les caractères spéciaux pour sed
ESCAPED_EMAIL=$(printf '%s\n' "$EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
ESCAPED_DOMAIN=$(printf '%s\n' "$DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')
# Remplacer ${EMAIL} (variable shell dans le template)
sed -i "s/\${EMAIL}/${ESCAPED_EMAIL}/g" Caddyfile
# Remplacer {$DOMAIN} (variable Caddy dans le template)
sed -i "s/{\$DOMAIN}/${ESCAPED_DOMAIN}/g" Caddyfile
echo "✓ Caddyfile configuré avec le domaine ${DOMAIN} et l'email ${EMAIL}"

# Configuration Fail2ban
cat > fail2ban/jail.d/immich.conf << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport
action = %(action_mwl)s

[immich-auth]
enabled = true
port = http,https
filter = immich-auth
logpath = /var/log/caddy/access.log
maxretry = 5
findtime = 600
bantime = 3600
EOF

cat > fail2ban/filter.d/immich-auth.conf << 'EOF'
[Definition]
failregex = ^.*"remote_ip":"<HOST>".*"uri":"/api/auth/login".*"status":(401|403).*$
            ^.*"remote_ip":"<HOST>".*"uri":"/api/auth/validateToken".*"status":(401|403).*$
ignoreregex =
EOF

echo "✓ Fichiers de configuration créés"

# Définir les permissions correctes
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" .env Caddyfile fail2ban logs caddy_data caddy_config 2>/dev/null || true
fi
# Sécurité: .env doit être en 600 (lecture/écriture uniquement pour le propriétaire)
chmod 600 .env
chmod 644 Caddyfile

# ============================================
# 8. TÉLÉCHARGEMENT ET DÉMARRAGE
# ============================================
echo "🚀 [8/8] Vérification des fichiers et démarrage..."

# Vérifier que docker-compose.yml existe
if [ ! -f "docker-compose.yml" ]; then
    echo ""
    echo "❌ ERREUR: Le fichier docker-compose.yml est introuvable !"
    echo "   Assurez-vous d'avoir tous les fichiers dans le répertoire courant:"
    echo "   - docker-compose.yml"
    echo "   - install.sh (ce script)"
    echo "   - backup.sh"
    echo ""
    echo "   Répertoire actuel: ${INSTALL_DIR}"
    exit 1
fi

echo "✓ Fichier docker-compose.yml trouvé"

# Démarrer les services
echo "Téléchargement des images Docker..."
docker compose pull

echo "Démarrage des services..."
docker compose up -d

# Vérifier que le .env est bien chargé
echo ""
echo "🔍 Vérification de la configuration..."
if docker compose config > /dev/null 2>&1; then
    echo "✓ Configuration valide"
else
    echo "❌ Erreur dans la configuration"
    echo "Vérifiez le fichier .env et docker-compose.yml"
    echo ""
    echo "Détails de l'erreur:"
    docker compose config 2>&1 | head -20
    exit 1
fi

# Attendre un peu pour que les services démarrent
echo "Attente du démarrage des services (15 secondes)..."
sleep 15

# Vérifier l'état des services
echo ""
echo "🔍 Vérification de l'état des services..."
docker compose ps

# Vérifier les logs de Caddy pour les erreurs de certificat
echo ""
echo "🔍 Vérification des logs Caddy (certificat SSL)..."
CADDY_LOGS=$(docker compose logs caddy 2>&1 | tail -50)

# Vérifier les erreurs
if echo "$CADDY_LOGS" | grep -i "error\|failed\|denied" | grep -v "level=info" > /dev/null; then
    echo "⚠️  Des erreurs ont été détectées dans les logs Caddy:"
    echo "$CADDY_LOGS" | grep -i "error\|failed\|denied" | grep -v "level=info" | head -5
    echo ""
    echo "   Consultez les logs complets avec: docker compose logs -f caddy"
fi

# Vérifier si le certificat est en cours de génération ou généré
if echo "$CADDY_LOGS" | grep -i "certificate obtained\|certificate issued\|acme.*success" > /dev/null; then
    echo "✅ Certificat Let's Encrypt généré avec succès !"
elif echo "$CADDY_LOGS" | grep -i "acme.*challenge\|obtaining certificate" > /dev/null; then
    echo "⏳ Certificat Let's Encrypt en cours de génération..."
    echo "   Cela peut prendre 1-2 minutes. Vérifiez avec: docker compose logs -f caddy"
elif echo "$CADDY_LOGS" | grep -i "acme.*error\|challenge.*failed\|port.*80.*refused" > /dev/null; then
    echo "❌ ERREUR: Le certificat Let's Encrypt n'a pas pu être généré"
    echo ""
    echo "   Causes possibles:"
    echo "   • Le port 80 n'est pas accessible depuis Internet"
    echo "   • Le domaine ne pointe pas vers cette machine"
    echo "   • Le DNS n'est pas encore propagé"
    echo "   • Un pare-feu bloque les connexions"
    echo ""
    echo "   Solutions:"
    echo "   1. Vérifiez que les ports 80 et 443 sont ouverts sur votre Freebox"
    echo "   2. Vérifiez que votre domaine pointe vers votre IP publique"
    echo "   3. Attendez quelques minutes pour le DNS"
    echo "   4. Consultez les logs: docker compose logs caddy"
else
    echo "ℹ️  Vérification du certificat en cours..."
    echo "   Les logs complets: docker compose logs caddy"
fi

# Vérifier si le certificat existe dans caddy_data
echo ""
echo "🔍 Vérification du certificat dans caddy_data..."
if [ -d "caddy_data" ] && [ "$(ls -A caddy_data 2>/dev/null)" ]; then
    CERT_COUNT=$(find caddy_data -name "*.crt" -o -name "*.key" 2>/dev/null | wc -l)
    if [ "$CERT_COUNT" -gt 0 ]; then
        echo "✓ Des fichiers de certificat ont été trouvés dans caddy_data"
    else
        echo "⚠️  Aucun certificat trouvé dans caddy_data (normal si première installation)"
    fi
else
    echo "⚠️  Le répertoire caddy_data est vide (normal si première installation)"
fi

# ============================================
# 9. CONFIGURATION DES BACKUPS AUTOMATIQUES
# ============================================
echo ""
echo "💾 Configuration des backups automatiques..."
echo ""
echo "Souhaitez-vous configurer les backups automatiques avec cron ?"
echo -n "  (o/n) [o]: "
read -r CONFIGURE_BACKUP
CONFIGURE_BACKUP=${CONFIGURE_BACKUP:-o}

if [ "$CONFIGURE_BACKUP" = "o" ] || [ "$CONFIGURE_BACKUP" = "O" ]; then
    echo ""
    echo "À quelle heure souhaitez-vous exécuter les backups quotidiennement ?"
    echo -n "  Heure (0-23) [3]: "
    read -r BACKUP_HOUR
    BACKUP_HOUR=${BACKUP_HOUR:-3}
    
    if ! [[ "$BACKUP_HOUR" =~ ^[0-9]+$ ]] || [ "$BACKUP_HOUR" -lt 0 ] || [ "$BACKUP_HOUR" -gt 23 ]; then
        echo "⚠️  Heure invalide. Utilisation de 3h par défaut."
        BACKUP_HOUR=3
    fi
    
    # Rendre le script backup.sh exécutable
    chmod +x "${INSTALL_DIR}/backup.sh"
    
    # Créer le fichier de log
    CRON_LOG="/var/log/immich-backup.log"
    mkdir -p "$(dirname "${CRON_LOG}")"
    touch "${CRON_LOG}"
    chmod 644 "${CRON_LOG}"
    
    # Créer l'entrée cron
    CRON_ENTRY="0 ${BACKUP_HOUR} * * * ${INSTALL_DIR}/backup.sh >> ${CRON_LOG} 2>&1"
    
    # Vérifier si une entrée existe déjà
    if crontab -l 2>/dev/null | grep -q "${INSTALL_DIR}/backup.sh"; then
        # Supprimer l'ancienne entrée
        crontab -l 2>/dev/null | grep -v "${INSTALL_DIR}/backup.sh" | crontab -
    fi
    
    # Ajouter la nouvelle entrée
    (crontab -l 2>/dev/null; echo "${CRON_ENTRY}") | crontab -
    
    echo ""
    echo "✅ Backup automatique configuré !"
    echo "   • Heure: ${BACKUP_HOUR}h00 tous les jours"
    echo "   • Logs: ${CRON_LOG}"
    echo "   • Script: ${INSTALL_DIR}/backup.sh"
else
    echo ""
    echo "ℹ️  Backup automatique non configuré"
    echo "   Pour le configurer plus tard: sudo ${INSTALL_DIR}/setup-backup-cron.sh"
fi

echo ""
echo "========================================"
echo "✅ Installation terminée !"
echo "========================================"
echo ""
echo "📍 Emplacement: ${INSTALL_DIR}"
echo "🌐 URL: https://${DOMAIN}"
echo "📁 Photos: ${PHOTOS_PATH}"
echo ""
echo "⏳ Attendez 2-3 minutes que les services démarrent..."
echo ""
echo "Commandes utiles:"
echo "  • Voir les logs:       cd ${INSTALL_DIR} && docker compose logs -f"
echo "  • Arrêter:             cd ${INSTALL_DIR} && docker compose stop"
echo "  • Démarrer:            cd ${INSTALL_DIR} && docker compose start"
echo "  • Redémarrer:          cd ${INSTALL_DIR} && docker compose restart"
echo "  • État:                cd ${INSTALL_DIR} && docker compose ps"
echo ""
# Détecter si on est dans WSL
IS_WSL=false
if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
    IS_WSL=true
    # Obtenir l'IP de l'hôte Windows depuis WSL
    # WSL2 utilise /etc/resolv.conf pour obtenir l'IP de l'hôte
    if [ -f /etc/resolv.conf ]; then
        WSL_HOST_IP=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -1)
    else
        WSL_HOST_IP=$(hostname -I | awk '{print $1}')
    fi
    WSL_IP=$(hostname -I | awk '{print $1}')
fi

echo "📝 Prochaines étapes:"
if [ "$IS_WSL" = true ]; then
    echo "  1. ✅ Configurez le port forwarding sur votre Freebox (WSL détecté)"
    echo "     → Port 80 (HTTP) → IP de l'hôte Windows: ${WSL_HOST_IP}"
    echo "     → Port 443 (HTTPS) → IP de l'hôte Windows: ${WSL_HOST_IP}"
    echo ""
    echo "     ℹ️  Note WSL: Les ports Docker sont automatiquement exposés sur l'hôte Windows"
    echo "        Vous pouvez aussi utiliser l'IP Windows directement depuis l'extérieur"
    echo "        IP WSL interne: ${WSL_IP} (ne pas utiliser pour port forwarding)"
else
    echo "  1. ✅ Configurez le port forwarding sur votre Freebox"
    echo "     → Port 80 (HTTP) → IP de cette machine: $(hostname -I | awk '{print $1}')"
    echo "     → Port 443 (HTTPS) → IP de cette machine: $(hostname -I | awk '{print $1}')"
fi
echo "  2. ✅ Configurez votre domaine Free pour pointer vers votre IP publique"
echo "     → Votre domaine: ${DOMAIN}"
echo "     → Doit pointer vers votre IP publique (trouvez-la avec: curl ifconfig.me)"
echo "  3. ⏳ Attendez 2-5 minutes pour:"
echo "     • La propagation DNS"
echo "     • La génération automatique du certificat Let's Encrypt par Caddy"
echo "  4. ✅ Vérifiez le certificat:"
echo "     → docker compose logs -f caddy"
echo "     → Recherchez 'certificate obtained' ou 'certificate issued'"
echo "  5. 🌐 Accédez à https://${DOMAIN}"
echo "  6. 👤 Créez votre compte administrateur"
echo ""
echo "🔒 Vérification du certificat:"
echo "   Si le certificat n'est pas généré après 5 minutes, vérifiez:"
echo "   • Les ports 80/443 sont bien ouverts: netstat -tuln | grep -E ':(80|443)'"
echo "   • Le domaine résout correctement: nslookup ${DOMAIN}"
echo "   • Les logs Caddy: docker compose logs caddy | grep -i acme"
echo ""
echo "🔒 SÉCURITÉ:"
echo "  • Mot de passe fort recommandé (16+ caractères)"
echo "  • Rate limiting actif: 3 tentatives/minute sur login"
echo "  • Fail2ban actif: ban automatique après 5 échecs"
echo "  • Mises à jour automatiques tous les dimanches à 4h"
echo ""
echo "📊 UPTIME KUMA (si activé avec --profile monitoring):"
echo "  • Accessible uniquement en localhost: http://localhost:3001"
echo "  • ⚠️  IMPORTANT: Configurez un mot de passe fort dans l'interface Kuma !"
echo "  • Pour accéder depuis une autre machine: utilisez SSH tunnel"
echo "  • Exemple SSH tunnel: ssh -L 3001:localhost:3001 user@serveur"
echo ""
echo "💾 SAUVEGARDES:"
if [ "$CONFIGURE_BACKUP" = "o" ] || [ "$CONFIGURE_BACKUP" = "O" ]; then
    echo "  • ✅ Backup automatique configuré à ${BACKUP_HOUR}h00"
    echo "  • Logs: /var/log/immich-backup.log"
else
    echo "  • Script disponible: ${INSTALL_DIR}/backup.sh"
    echo "  • Configuration automatique: sudo ${INSTALL_DIR}/setup-backup-cron.sh"
fi
echo "  • Test manuel: ${INSTALL_DIR}/backup.sh"
echo ""
echo "📧 Support: Consultez la documentation Immich"
echo "========================================"