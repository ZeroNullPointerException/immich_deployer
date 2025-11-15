#!/bin/bash

# ============================================
# SCRIPT DE SAUVEGARDE IMMICH
# ============================================
# Usage: ./backup.sh
# Cron: 0 3 * * * /opt/immich/backup.sh >> /var/log/immich-backup.log 2>&1

set -e  # Arrêter si erreur

# ============================================
# CONFIGURATION
# ============================================
# Détecter automatiquement le répertoire d'installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-${SCRIPT_DIR}}"

# Répertoire de backup (dans le workspace pour simplicité et droits)
# Par défaut: ./backups/ dans le répertoire d'installation
BACKUP_DIR="${BACKUP_DIR:-${COMPOSE_DIR}/backups}"
RETENTION_COUNT=2  # Garder seulement 2 backups
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="immich_backup_${DATE}.tar.gz"

# Vérifier que le répertoire d'installation existe
if [ ! -d "${COMPOSE_DIR}" ]; then
    echo "❌ Erreur: Répertoire d'installation introuvable: ${COMPOSE_DIR}"
    echo "   Définissez COMPOSE_DIR ou placez le script dans le répertoire Immich"
    exit 1
fi

# Charger les variables d'environnement
if [ -f "${COMPOSE_DIR}/.env" ]; then
    source "${COMPOSE_DIR}/.env"
else
    echo "❌ Erreur: Fichier .env introuvable dans ${COMPOSE_DIR}"
    exit 1
fi

# Créer le répertoire de backup (dans le workspace - pas de problème de droits)
mkdir -p "${BACKUP_DIR}"
echo "📁 Répertoire de backup: ${BACKUP_DIR}"

# Vérifier que Docker est disponible
if ! command -v docker &> /dev/null; then
    echo "❌ Erreur: Docker n'est pas installé ou non accessible"
    exit 1
fi

# Vérifier que le conteneur PostgreSQL existe
if ! docker ps -a --format '{{.Names}}' | grep -q "^immich_postgres$"; then
    echo "❌ Erreur: Le conteneur immich_postgres n'existe pas"
    echo "   Assurez-vous que les services Immich sont démarrés"
    exit 1
fi

echo "=== Début sauvegarde Immich - ${DATE} ==="
echo "Répertoire d'installation: ${COMPOSE_DIR}"
echo "Répertoire de backup: ${BACKUP_DIR}"
echo ""

# Répertoire temporaire pour assembler l'archive
TEMP_BACKUP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_BACKUP_DIR}" EXIT

# ============================================
# 1. SAUVEGARDE BASE DE DONNÉES
# ============================================
echo "[1/4] Sauvegarde de la base de données PostgreSQL..."

docker exec immich_postgres pg_dump \
    -U "${DB_USERNAME}" \
    -d "${DB_DATABASE_NAME}" \
    -F c \
    -b \
    -v \
    -f "/tmp/backup_${DATE}.dump"

docker cp immich_postgres:/tmp/backup_${DATE}.dump "${TEMP_BACKUP_DIR}/database.dump"
docker exec immich_postgres rm /tmp/backup_${DATE}.dump

# Compresser la sauvegarde DB
gzip "${TEMP_BACKUP_DIR}/database.dump"

echo "✓ Base de données sauvegardée"

# ============================================
# 2. SAUVEGARDE DES PHOTOS
# ============================================
echo "[2/4] Sauvegarde des photos..."

# Créer un répertoire pour les photos dans le backup temporaire
mkdir -p "${TEMP_BACKUP_DIR}/photos"

# Copier les photos
rsync -av --delete "${UPLOAD_LOCATION}/" "${TEMP_BACKUP_DIR}/photos/"

echo "✓ Photos sauvegardées"

# ============================================
# 3. SAUVEGARDE DE LA CONFIGURATION
# ============================================
echo "[3/4] Sauvegarde de la configuration..."

mkdir -p "${TEMP_BACKUP_DIR}/config"
cp "${COMPOSE_DIR}/docker-compose.yml" "${TEMP_BACKUP_DIR}/config/" 2>/dev/null || true
cp "${COMPOSE_DIR}/.env" "${TEMP_BACKUP_DIR}/config/" 2>/dev/null || true
cp "${COMPOSE_DIR}/Caddyfile" "${TEMP_BACKUP_DIR}/config/" 2>/dev/null || true
cp -r "${COMPOSE_DIR}/fail2ban/" "${TEMP_BACKUP_DIR}/config/" 2>/dev/null || true

echo "✓ Configuration sauvegardée"

# ============================================
# 4. CRÉATION DE L'ARCHIVE UNIQUE
# ============================================
echo "[4/5] Création de l'archive compressée..."

# Créer l'archive finale avec tout dedans
cd "${TEMP_BACKUP_DIR}"
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" .

echo "✓ Archive créée: ${BACKUP_FILE}"

# ============================================
# 5. NETTOYAGE DES ANCIENNES SAUVEGARDES
# ============================================
echo "[5/5] Nettoyage des anciennes sauvegardes (garder ${RETENTION_COUNT} backups)..."

# Supprimer les anciennes sauvegardes (garder seulement les N plus récentes)
ls -1t "${BACKUP_DIR}"/immich_backup_*.tar.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | xargs -r rm -f

echo "✓ Nettoyage effectué (${RETENTION_COUNT} backups conservés)"

# ============================================
# 6. RAPPORT DE SAUVEGARDE
# ============================================
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/immich_backup_*.tar.gz 2>/dev/null | wc -l)

echo ""
echo "=== Rapport de sauvegarde ==="
echo "Date: ${DATE}"
echo "Fichier: ${BACKUP_FILE}"
echo "Taille: ${BACKUP_SIZE}"
echo "Emplacement: ${BACKUP_DIR}"
echo "Backups conservés: ${BACKUP_COUNT}/${RETENTION_COUNT}"
echo ""

# ============================================
# 7. VÉRIFICATION DE L'INTÉGRITÉ
# ============================================
echo ""
echo "Vérification de l'intégrité de l'archive..."

# Vérifier que l'archive existe et n'est pas vide
if [ ! -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
    echo "❌ ERREUR: L'archive de sauvegarde n'existe pas !"
    exit 1
fi

ARCHIVE_SIZE=$(stat -f%z "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null || stat -c%s "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null || echo "0")
if [ "$ARCHIVE_SIZE" -lt 1000 ]; then
    echo "❌ ERREUR: L'archive semble vide ou corrompue !"
    exit 1
fi

# Vérifier l'intégrité de l'archive
if tar -tzf "${BACKUP_DIR}/${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "✓ Vérification de l'intégrité réussie"
else
    echo "❌ ERREUR: L'archive semble corrompue !"
    exit 1
fi

echo ""
echo "=== Sauvegarde terminée avec succès ! ==="
echo "Date: ${DATE}"
echo "Fichier: ${BACKUP_FILE}"
echo "Emplacement: ${BACKUP_DIR}/${BACKUP_FILE}"
echo ""
echo "💡 Pour copier ce backup sur un disque externe:"
echo "   cp '${BACKUP_DIR}/${BACKUP_FILE}' /media/disque-externe/"
echo "   ou"
echo "   cp '${BACKUP_DIR}/${BACKUP_FILE}' /chemin/vers/pc/"
echo ""

# Envoyer une notification (optionnel)
# Décommenter et configurer pour activer
# if [ -n "${NOTIFICATION_URL}" ]; then
#     curl -X POST "${NOTIFICATION_URL}" -d "Sauvegarde Immich réussie - ${DATE}" 2>/dev/null || true
# fi