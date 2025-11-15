#!/bin/bash

# ============================================
# SCRIPT DE NETTOYAGE IMMICH
# ============================================
# ATTENTION: Ce script supprime TOUT (conteneurs, volumes, images, données)
# Usage: sudo ./cleanup.sh

set -e

echo "========================================"
echo "   ⚠️  NETTOYAGE COMPLET IMMICH"
echo "========================================"
echo ""
echo "Ce script va supprimer:"
echo "  • Tous les conteneurs Immich"
echo "  • Tous les volumes Docker (BASE DE DONNÉES incluse)"
echo "  • Toutes les images Docker Immich"
echo "  • Les fichiers de configuration locaux"
echo ""
echo "⚠️  LES PHOTOS NE SERONT PAS SUPPRIMÉES"
echo "   (elles restent dans le dossier UPLOAD_LOCATION)"
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ce script doit être exécuté en root (sudo)"
    exit 1
fi

# Demander confirmation
echo -n "Voulez-vous vraiment TOUT supprimer ? (tapez 'oui' pour confirmer): "
read -r CONFIRMATION

if [ "$CONFIRMATION" != "oui" ]; then
    echo "❌ Annulé"
    exit 0
fi

echo ""
echo "🗑️  Début du nettoyage..."
echo ""

# ============================================
# 1. ARRÊTER ET SUPPRIMER LES CONTENEURS
# ============================================
echo "[1/6] Arrêt et suppression des conteneurs..."

if [ -f "docker-compose.yml" ]; then
    docker compose down -v 2>/dev/null || true
    echo "✓ Conteneurs arrêtés et supprimés"
else
    # Si pas de docker-compose.yml, supprimer manuellement
    docker stop immich_server immich_machine_learning immich_postgres immich_redis immich_caddy immich_fail2ban immich_watchtower immich_uptime_kuma 2>/dev/null || true
    docker rm immich_server immich_machine_learning immich_postgres immich_redis immich_caddy immich_fail2ban immich_watchtower immich_uptime_kuma 2>/dev/null || true
    echo "✓ Conteneurs supprimés manuellement"
fi

# ============================================
# 2. SUPPRIMER LES VOLUMES
# ============================================
echo "[2/6] Suppression des volumes Docker..."

docker volume rm immich_postgres_data 2>/dev/null || true
docker volume rm immich_redis_data 2>/dev/null || true
docker volume rm immich_model_cache 2>/dev/null || true

# Supprimer tous les volumes orphelins
docker volume prune -f

echo "✓ Volumes supprimés"

# ============================================
# 3. SUPPRIMER LES RÉSEAUX
# ============================================
echo "[3/6] Suppression des réseaux Docker..."

docker network rm immich_immich_public 2>/dev/null || true
docker network rm immich_immich_private 2>/dev/null || true

echo "✓ Réseaux supprimés"

# ============================================
# 4. GARDER LES IMAGES (pas de suppression)
# ============================================
echo "[4/6] Conservation des images Docker..."

echo "✓ Images conservées (réinstallation rapide possible)"

# Note: Si vous voulez vraiment supprimer les images Immich :
# docker rmi ghcr.io/immich-app/immich-server:release
# docker rmi ghcr.io/immich-app/immich-machine-learning:release
# docker rmi tensorchord/pgvecto-rs:pg14-v0.2.0
# docker rmi redis:7.2-alpine
# docker rmi caddy:2-alpine
# docker rmi crazymax/fail2ban:latest
# docker rmi containrrr/watchtower:latest
# docker rmi louislam/uptime-kuma:1

# ============================================
# 5. SUPPRIMER LES FICHIERS LOCAUX
# ============================================
echo "[5/6] Suppression des fichiers de configuration..."

rm -rf logs/
rm -rf caddy_data/
rm -rf caddy_config/
rm -rf fail2ban/
rm -rf uptime-kuma/
rm -f .env

echo "✓ Fichiers de configuration supprimés"

# ============================================
# 6. NETTOYAGE FINAL LÉGER
# ============================================
echo "[6/6] Nettoyage léger..."

# Supprimer uniquement les conteneurs arrêtés
docker container prune -f

# Supprimer uniquement les volumes non utilisés
docker volume prune -f

# Supprimer uniquement les réseaux non utilisés
docker network prune -f

# Ne PAS supprimer les images ni le cache de build

echo "✓ Nettoyage léger effectué"

# ============================================
# RAPPORT
# ============================================
echo ""
echo "========================================"
echo "✅ NETTOYAGE TERMINÉ"
echo "========================================"
echo ""
echo "Ce qui a été supprimé:"
echo "  ✓ Tous les conteneurs Immich"
echo "  ✓ Tous les volumes (base de données, cache)"
echo "  ✓ Fichiers de configuration"
echo ""
echo "Ce qui a été conservé:"
echo "  ✓ Images Docker (réinstallation rapide)"
echo "  ✓ docker-compose.yml, install.sh, backup.sh"
echo "  ✓ Les photos dans le dossier configuré"
echo ""
echo "💾 Espace économisé en gardant les images:"
echo "   Les images pèsent ~2-3GB mais évitent 5-10 min de téléchargement"
echo ""
echo "Pour réinstaller (rapide, ~30 secondes):"
echo "  sudo ./install.sh"
echo ""
echo "Pour supprimer aussi les images (optionnel):"
echo "  docker image prune -a"
echo ""
echo "========================================"