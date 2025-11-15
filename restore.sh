#!/bin/bash

# ============================================
# SCRIPT DE RESTAURATION IMMICH
# ============================================
# Restaure les backups créés par backup.sh
# Usage: ./restore.sh [chemin_vers_backup.tar.gz]

set -e

echo "========================================"
echo "   Restauration Immich"
echo "========================================"
echo ""

# ============================================
# CONFIGURATION
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-${SCRIPT_DIR}}"

# Répertoire de backup (dans le workspace par défaut)
BACKUP_DIR="${BACKUP_DIR:-${COMPOSE_DIR}/backups}"

# Si un chemin est fourni en argument, l'utiliser
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
else
    # Sinon, lister les backups disponibles
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo "❌ Erreur: Répertoire de backup introuvable: ${BACKUP_DIR}"
        echo "   Utilisation: ./restore.sh [chemin_vers_backup.tar.gz]"
        exit 1
    fi
    
    echo "🔍 Sauvegardes disponibles:"
    echo ""
    BACKUP_LIST=$(ls -1t "${BACKUP_DIR}"/immich_backup_*.tar.gz 2>/dev/null | head -10 || echo "")
    
    if [ -z "$BACKUP_LIST" ]; then
        echo "   ❌ Aucune sauvegarde trouvée dans ${BACKUP_DIR}"
        echo ""
        echo "   Vous pouvez aussi spécifier un chemin direct:"
        echo "   ./restore.sh /chemin/vers/immich_backup_YYYYMMDD_HHMMSS.tar.gz"
        exit 1
    fi
    
    COUNT=1
    declare -a BACKUP_ARRAY
    while IFS= read -r backup; do
        if [ -n "$backup" ]; then
            BACKUP_NAME=$(basename "$backup")
            BACKUP_SIZE=$(ls -lh "$backup" | awk '{print $5}')
            BACKUP_DATE=$(echo "$BACKUP_NAME" | sed 's/immich_backup_\(.*\)\.tar\.gz/\1/')
            echo "   [$COUNT] $BACKUP_DATE (${BACKUP_SIZE})"
            BACKUP_ARRAY[$COUNT]="$backup"
            COUNT=$((COUNT + 1))
        fi
    done <<< "$BACKUP_LIST"
    echo ""
    
    echo -n "Quelle sauvegarde restaurer ? [1]: "
    read -r BACKUP_CHOICE
    BACKUP_CHOICE=${BACKUP_CHOICE:-1}
    
    if [ "$BACKUP_CHOICE" -lt 1 ] || [ "$BACKUP_CHOICE" -ge ${#BACKUP_ARRAY[@]} ]; then
        echo "❌ Erreur: Choix invalide"
        exit 1
    fi
    
    BACKUP_FILE="${BACKUP_ARRAY[$BACKUP_CHOICE]}"
fi

# Vérifier que le fichier de backup existe
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Erreur: Le fichier de backup n'existe pas: $BACKUP_FILE"
    exit 1
fi

# Vérifier que Docker est disponible
if ! command -v docker &> /dev/null; then
    echo "❌ Erreur: Docker n'est pas installé ou non accessible"
    exit 1
fi

echo "📦 Backup sélectionné: $(basename "$BACKUP_FILE")"
echo "📍 Répertoire d'installation: ${COMPOSE_DIR}"
echo ""

# ============================================
# CONFIRMATION
# ============================================
echo "⚠️  ATTENTION: La restauration va écraser les données actuelles !"
echo ""
echo "Que souhaitez-vous restaurer ?"
echo "   1) Tout (Base de données + Photos + Configuration) [Recommandé]"
echo "   2) Base de données uniquement"
echo "   3) Photos uniquement"
echo "   4) Configuration uniquement"
echo ""
echo -n "Votre choix [1]: "
read -r RESTORE_CHOICE
RESTORE_CHOICE=${RESTORE_CHOICE:-1}

RESTORE_ALL=false
RESTORE_DB=false
RESTORE_PHOTOS=false
RESTORE_CONFIG=false

case "$RESTORE_CHOICE" in
    1)
        RESTORE_ALL=true
        RESTORE_DB=true
        RESTORE_PHOTOS=true
        RESTORE_CONFIG=true
        ;;
    2)
        RESTORE_DB=true
        ;;
    3)
        RESTORE_PHOTOS=true
        ;;
    4)
        RESTORE_CONFIG=true
        ;;
    *)
        echo "❌ Erreur: Choix invalide"
        exit 1
        ;;
esac

# Confirmation finale
echo ""
echo "========================================"
echo "   RÉSUMÉ DE LA RESTAURATION"
echo "========================================"
echo "Fichier: $(basename "$BACKUP_FILE")"
if [ "$RESTORE_DB" = true ]; then
    echo "✓ Base de données"
fi
if [ "$RESTORE_PHOTOS" = true ]; then
    echo "✓ Photos"
fi
if [ "$RESTORE_CONFIG" = true ]; then
    echo "✓ Configuration"
fi
echo ""
echo "⚠️  ATTENTION: Cette opération va écraser les données actuelles !"
echo -n "Confirmer la restauration ? (oui/non) [non]: "
read -r CONFIRM

if [ "$CONFIRM" != "oui" ]; then
    echo "❌ Restauration annulée"
    exit 0
fi

echo ""
echo "========================================"
echo "   DÉBUT DE LA RESTAURATION"
echo "========================================"
echo ""

# ============================================
# EXTRACTION DE L'ARCHIVE
# ============================================
echo "[1/4] Extraction de l'archive..."

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

echo "✓ Archive extraite"
echo ""

# ============================================
# RESTAURATION BASE DE DONNÉES
# ============================================
if [ "$RESTORE_DB" = true ]; then
    echo "[2/4] Restauration de la base de données..."
    
    # Vérifier que le dump existe
    if [ ! -f "${TEMP_DIR}/database.dump.gz" ]; then
        echo "❌ Erreur: Le dump de la base de données n'existe pas dans l'archive"
        exit 1
    fi
    
    # Vérifier que le conteneur PostgreSQL existe
    if ! docker ps -a --format '{{.Names}}' | grep -q "^immich_postgres$"; then
        echo "❌ Erreur: Le conteneur immich_postgres n'existe pas"
        echo "   Démarrez d'abord les services: docker compose up -d postgres"
        exit 1
    fi
    
    # Vérifier que PostgreSQL est prêt
    echo "   Attente que PostgreSQL soit prêt..."
    timeout=30
    while [ $timeout -gt 0 ]; do
        if docker exec immich_postgres pg_isready -U postgres >/dev/null 2>&1; then
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    
    if [ $timeout -eq 0 ]; then
        echo "❌ Erreur: PostgreSQL n'est pas prêt"
        exit 1
    fi
    
    # Décompresser le dump
    gunzip "${TEMP_DIR}/database.dump.gz"
    
    # Charger le .env pour obtenir les credentials
    if [ -f "${COMPOSE_DIR}/.env" ]; then
        source "${COMPOSE_DIR}/.env"
    else
        echo "❌ Erreur: Fichier .env introuvable"
        exit 1
    fi
    
    # Arrêter Immich server pour éviter les écritures
    echo "   Arrêt d'Immich server..."
    docker compose stop immich-server 2>/dev/null || true
    
    # Restaurer la base de données
    echo "   Restauration en cours..."
    docker cp "${TEMP_DIR}/database.dump" immich_postgres:/tmp/restore.dump
    docker exec immich_postgres pg_restore \
        -U "${DB_USERNAME}" \
        -d "${DB_DATABASE_NAME}" \
        --clean \
        --if-exists \
        -v \
        /tmp/restore.dump 2>&1 | grep -v "WARNING" || true
    
    docker exec immich_postgres rm /tmp/restore.dump
    
    echo "✓ Base de données restaurée"
    echo ""
fi

# ============================================
# RESTAURATION PHOTOS
# ============================================
if [ "$RESTORE_PHOTOS" = true ]; then
    echo "[3/4] Restauration des photos..."
    
    # Vérifier que le répertoire photos existe dans l'archive
    if [ ! -d "${TEMP_DIR}/photos" ]; then
        echo "❌ Erreur: Le répertoire photos n'existe pas dans l'archive"
        exit 1
    fi
    
    # Charger le .env pour obtenir le chemin des photos
    if [ -f "${COMPOSE_DIR}/.env" ]; then
        source "${COMPOSE_DIR}/.env"
    else
        echo "❌ Erreur: Fichier .env introuvable"
        exit 1
    fi
    
    if [ -z "$UPLOAD_LOCATION" ]; then
        echo "❌ Erreur: UPLOAD_LOCATION non défini dans .env"
        exit 1
    fi
    
    # Arrêter Immich server pour éviter les écritures
    echo "   Arrêt d'Immich server..."
    docker compose stop immich-server 2>/dev/null || true
    
    # Créer le répertoire si nécessaire
    mkdir -p "${UPLOAD_LOCATION}"
    
    # Restaurer les photos
    echo "   Copie des photos en cours..."
    rsync -av --delete "${TEMP_DIR}/photos/" "${UPLOAD_LOCATION}/"
    
    echo "✓ Photos restaurées"
    echo ""
fi

# ============================================
# RESTAURATION CONFIGURATION
# ============================================
if [ "$RESTORE_CONFIG" = true ]; then
    echo "[4/4] Restauration de la configuration..."
    
    # Vérifier que le répertoire config existe
    if [ ! -d "${TEMP_DIR}/config" ]; then
        echo "❌ Erreur: Le répertoire config n'existe pas dans l'archive"
        exit 1
    fi
    
    # Restaurer les fichiers
    echo "   Restauration des fichiers de configuration..."
    
    if [ -f "${TEMP_DIR}/config/docker-compose.yml" ]; then
        cp "${TEMP_DIR}/config/docker-compose.yml" "${COMPOSE_DIR}/docker-compose.yml"
        echo "   ✓ docker-compose.yml restauré"
    fi
    
    if [ -f "${TEMP_DIR}/config/.env" ]; then
        cp "${TEMP_DIR}/config/.env" "${COMPOSE_DIR}/.env"
        chmod 600 "${COMPOSE_DIR}/.env"
        echo "   ✓ .env restauré"
    fi
    
    if [ -f "${TEMP_DIR}/config/Caddyfile" ]; then
        cp "${TEMP_DIR}/config/Caddyfile" "${COMPOSE_DIR}/Caddyfile"
        echo "   ✓ Caddyfile restauré"
    fi
    
    if [ -d "${TEMP_DIR}/config/fail2ban" ]; then
        cp -r "${TEMP_DIR}/config/fail2ban" "${COMPOSE_DIR}/"
        echo "   ✓ Configuration Fail2ban restaurée"
    fi
    
    echo "✓ Configuration restaurée"
    echo ""
fi

# ============================================
# REDÉMARRAGE DES SERVICES
# ============================================
echo "🔄 Redémarrage des services..."
echo ""

# Redémarrer tous les services
docker compose up -d

echo ""
echo "⏳ Attente du démarrage des services (15 secondes)..."
sleep 15

# Vérifier l'état des services
echo ""
echo "📊 État des services:"
docker compose ps

echo ""
echo "========================================"
echo "✅ Restauration terminée avec succès !"
echo "========================================"
echo ""
echo "📝 Prochaines étapes:"
echo "   1. Vérifiez que tous les services sont démarrés (status: Up)"
echo "   2. Vérifiez les logs: docker compose logs -f"
echo "   3. Accédez à votre instance Immich"
echo ""
if [ "$RESTORE_CONFIG" = true ]; then
    echo "⚠️  NOTE: Si vous avez restauré la configuration, vous devrez peut-être:"
    echo "   • Redémarrer Caddy: docker compose restart caddy"
    echo "   • Vérifier les certificats SSL"
fi
echo ""
