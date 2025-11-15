#!/bin/bash

# ============================================
# SCRIPT DE CHANGEMENT DE DOMAINE
# ============================================
# Change le domaine d'une instance Immich déjà installée
# Usage: ./change-domain.sh

set -e

echo "========================================"
echo "   Changement de Domaine Immich"
echo "========================================"
echo ""

# ============================================
# CONFIGURATION
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-${SCRIPT_DIR}}"

# Vérifier que le fichier .env existe
if [ ! -f "${COMPOSE_DIR}/.env" ]; then
    echo "❌ Erreur: Le fichier .env n'existe pas dans ${COMPOSE_DIR}"
    echo "   Assurez-vous d'être dans le répertoire Immich"
    exit 1
fi

# Charger les variables actuelles
source "${COMPOSE_DIR}/.env"

echo "📍 Répertoire d'installation: ${COMPOSE_DIR}"
echo ""
echo "🌐 Domaine actuel: ${DOMAIN:-non défini}"
echo "📧 Email actuel: ${EMAIL:-non défini}"
echo ""

# ============================================
# SAISIE DU NOUVEAU DOMAINE
# ============================================
echo "Saisie du nouveau domaine:"
echo ""
echo -n "Nouveau domaine (ex: photos.monnom.freeboxos.fr) [${DOMAIN}]: "
read -r NEW_DOMAIN

if [ -z "$NEW_DOMAIN" ]; then
    NEW_DOMAIN="${DOMAIN}"
fi

if [ -z "$NEW_DOMAIN" ]; then
    echo "❌ Erreur: Le domaine est obligatoire"
    exit 1
fi

# Vérifier que le domaine est différent
if [ "$NEW_DOMAIN" = "$DOMAIN" ]; then
    echo "ℹ️  Le nouveau domaine est identique à l'actuel. Aucun changement nécessaire."
    exit 0
fi

echo ""
echo -n "Email pour Let's Encrypt [${EMAIL}]: "
read -r NEW_EMAIL
NEW_EMAIL=${NEW_EMAIL:-${EMAIL}}

if [ -z "$NEW_EMAIL" ]; then
    echo "❌ Erreur: L'email est obligatoire"
    exit 1
fi

# Confirmation
echo ""
echo "========================================"
echo "   RÉSUMÉ DES CHANGEMENTS"
echo "========================================"
echo "Ancien domaine: ${DOMAIN}"
echo "Nouveau domaine: ${NEW_DOMAIN}"
echo ""
echo "Ancien email: ${EMAIL}"
echo "Nouveau email: ${NEW_EMAIL}"
echo ""
echo "⚠️  ATTENTION:"
echo "   • Le certificat SSL actuel sera remplacé"
echo "   • Caddy sera redémarré"
echo "   • Vous devrez configurer le nouveau domaine dans votre DNS"
echo ""
echo -n "Confirmer le changement ? (oui/non) [non]: "
read -r CONFIRM

if [ "$CONFIRM" != "oui" ]; then
    echo "❌ Changement annulé"
    exit 0
fi

echo ""
echo "========================================"
echo "   DÉBUT DU CHANGEMENT DE DOMAINE"
echo "========================================"
echo ""

# ============================================
# 1. MISE À JOUR DU FICHIER .env
# ============================================
echo "[1/4] Mise à jour du fichier .env..."

# Sauvegarder l'ancien .env
cp "${COMPOSE_DIR}/.env" "${COMPOSE_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)"

# Mettre à jour DOMAIN et EMAIL dans .env
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^DOMAIN=.*/DOMAIN=${NEW_DOMAIN}/" "${COMPOSE_DIR}/.env"
    sed -i '' "s/^EMAIL=.*/EMAIL=${NEW_EMAIL}/" "${COMPOSE_DIR}/.env"
else
    # Linux
    sed -i "s/^DOMAIN=.*/DOMAIN=${NEW_DOMAIN}/" "${COMPOSE_DIR}/.env"
    sed -i "s/^EMAIL=.*/EMAIL=${NEW_EMAIL}/" "${COMPOSE_DIR}/.env"
fi

echo "✓ Fichier .env mis à jour"

# ============================================
# 2. MISE À JOUR DU CADDYFILE
# ============================================
echo "[2/4] Mise à jour du Caddyfile..."

# Utiliser le script update-caddyfile.sh pour régénérer le Caddyfile
if [ -f "${COMPOSE_DIR}/update-caddyfile.sh" ]; then
    echo "   Utilisation du script update-caddyfile.sh..."
    # Le .env a déjà été mis à jour, donc update-caddyfile.sh utilisera les nouvelles valeurs
    bash "${COMPOSE_DIR}/update-caddyfile.sh" >/dev/null 2>&1 || {
        echo "   ⚠️  Le script update-caddyfile.sh a échoué, mise à jour manuelle..."
        # Mise à jour manuelle de secours
        ESCAPED_EMAIL=$(printf '%s\n' "$NEW_EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
        ESCAPED_DOMAIN=$(printf '%s\n' "$NEW_DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')
        ESCAPED_OLD_DOMAIN=$(printf '%s\n' "$DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/email .*/email ${ESCAPED_EMAIL}/" "${COMPOSE_DIR}/Caddyfile"
            sed -i '' "s/${ESCAPED_OLD_DOMAIN}/${ESCAPED_DOMAIN}/g" "${COMPOSE_DIR}/Caddyfile"
        else
            sed -i "s/email .*/email ${ESCAPED_EMAIL}/" "${COMPOSE_DIR}/Caddyfile"
            sed -i "s/${ESCAPED_OLD_DOMAIN}/${ESCAPED_DOMAIN}/g" "${COMPOSE_DIR}/Caddyfile"
        fi
    }
else
    # Mise à jour manuelle du Caddyfile
    echo "   Mise à jour manuelle du Caddyfile..."
    ESCAPED_EMAIL=$(printf '%s\n' "$NEW_EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
    ESCAPED_DOMAIN=$(printf '%s\n' "$NEW_DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')
    ESCAPED_OLD_DOMAIN=$(printf '%s\n' "$DOMAIN" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/email .*/email ${ESCAPED_EMAIL}/" "${COMPOSE_DIR}/Caddyfile"
        sed -i '' "s/${ESCAPED_OLD_DOMAIN}/${ESCAPED_DOMAIN}/g" "${COMPOSE_DIR}/Caddyfile"
    else
        # Linux
        sed -i "s/email .*/email ${ESCAPED_EMAIL}/" "${COMPOSE_DIR}/Caddyfile"
        sed -i "s/${ESCAPED_OLD_DOMAIN}/${ESCAPED_DOMAIN}/g" "${COMPOSE_DIR}/Caddyfile"
    fi
fi

echo "✓ Caddyfile mis à jour"

# ============================================
# 3. NETTOYAGE DE L'ANCIEN CERTIFICAT (Optionnel)
# ============================================
echo "[3/4] Nettoyage de l'ancien certificat SSL..."

if [ -d "${COMPOSE_DIR}/caddy_data/caddy/certificates" ]; then
    OLD_CERT_DIR="${COMPOSE_DIR}/caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}"
    if [ -d "$OLD_CERT_DIR" ]; then
        echo "   Suppression de l'ancien certificat pour ${DOMAIN}..."
        rm -rf "$OLD_CERT_DIR"
        echo "   ✓ Ancien certificat supprimé"
    else
        echo "   ℹ️  Aucun ancien certificat trouvé"
    fi
else
    echo "   ℹ️  Répertoire de certificats non trouvé (normal si première utilisation)"
fi

# ============================================
# 4. REDÉMARRAGE DE CADDY
# ============================================
echo "[4/4] Redémarrage de Caddy pour obtenir le nouveau certificat..."

# Vérifier que Docker est disponible
if ! command -v docker &> /dev/null; then
    echo "❌ Erreur: Docker n'est pas installé ou non accessible"
    exit 1
fi

# Vérifier que les services sont démarrés
if ! docker ps --format '{{.Names}}' | grep -q "^immich_caddy$"; then
    echo "   Démarrage de Caddy..."
    docker compose up -d caddy
else
    echo "   Redémarrage de Caddy..."
    docker compose restart caddy
fi

echo "✓ Caddy redémarré"

# Attendre un peu pour que Caddy démarre
echo ""
echo "⏳ Attente du démarrage de Caddy (5 secondes)..."
sleep 5

# ============================================
# VÉRIFICATION
# ============================================
echo ""
echo "🔍 Vérification des changements..."
echo ""

# Vérifier le nouveau domaine dans .env
if grep -q "DOMAIN=${NEW_DOMAIN}" "${COMPOSE_DIR}/.env"; then
    echo "✓ Domaine mis à jour dans .env"
else
    echo "⚠️  Attention: Vérifiez manuellement le domaine dans .env"
fi

# Vérifier le nouveau domaine dans Caddyfile
if grep -q "${NEW_DOMAIN}" "${COMPOSE_DIR}/Caddyfile"; then
    echo "✓ Domaine mis à jour dans Caddyfile"
else
    echo "⚠️  Attention: Vérifiez manuellement le domaine dans Caddyfile"
fi

# Vérifier les logs Caddy
echo ""
echo "📋 Logs Caddy (dernières lignes):"
docker compose logs --tail=10 caddy | grep -i "certificate\|acme\|${NEW_DOMAIN}" || echo "   (aucun log spécifique trouvé)"

echo ""
echo "========================================"
echo "✅ Changement de domaine terminé !"
echo "========================================"
echo ""
echo "📝 Prochaines étapes:"
echo ""
echo "1. ⚙️  Configurer le DNS:"
echo "   • Mettre à jour votre domaine Free pour pointer vers votre IP publique"
echo "   • Domaine: ${NEW_DOMAIN}"
echo ""
echo "2. ⏳ Attendre la génération du certificat (2-5 minutes):"
echo "   • Surveiller: docker compose logs -f caddy"
echo "   • Rechercher: 'certificate obtained successfully'"
echo ""
echo "3. 🌐 Accéder au nouveau domaine:"
echo "   • URL: https://${NEW_DOMAIN}"
echo ""
echo "4. 🔍 Vérifier le certificat:"
echo "   • Exécuter: ./check-certificate.sh"
echo ""
echo "⚠️  IMPORTANT:"
echo "   • Assurez-vous que le DNS pointe vers votre IP publique"
echo "   • Les ports 80 et 443 doivent être accessibles depuis Internet"
echo "   • L'ancien domaine ne fonctionnera plus après propagation DNS"
echo ""
echo "💾 Backup de l'ancien .env: .env.backup.*"
echo ""

