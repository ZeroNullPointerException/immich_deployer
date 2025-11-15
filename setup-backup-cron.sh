#!/bin/bash

# ============================================
# SCRIPT DE CONFIGURATION DES BACKUPS AUTOMATIQUES
# ============================================
# Configure un job cron pour exécuter les backups automatiquement
# Usage: sudo ./setup-backup-cron.sh

set -e

echo "========================================"
echo "   Configuration Backups Automatiques"
echo "========================================"
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ce script doit être exécuté en root (sudo)"
    exit 1
fi

# Obtenir le répertoire d'installation
INSTALL_DIR=$(pwd)
BACKUP_SCRIPT="${INSTALL_DIR}/backup.sh"
CRON_LOG="/var/log/immich-backup.log"

# Vérifier que backup.sh existe
if [ ! -f "${BACKUP_SCRIPT}" ]; then
    echo "❌ Le script backup.sh est introuvable dans ${INSTALL_DIR}"
    exit 1
fi

# Rendre le script exécutable
chmod +x "${BACKUP_SCRIPT}"
echo "✓ Script backup.sh rendu exécutable"

# Demander l'heure de backup
echo ""
echo "À quelle heure souhaitez-vous exécuter les backups ?"
echo "Format: HH (0-23, exemple: 3 pour 3h du matin)"
echo -n "Heure [3]: "
read -r BACKUP_HOUR
BACKUP_HOUR=${BACKUP_HOUR:-3}

if ! [[ "$BACKUP_HOUR" =~ ^[0-9]+$ ]] || [ "$BACKUP_HOUR" -lt 0 ] || [ "$BACKUP_HOUR" -gt 23 ]; then
    echo "❌ Heure invalide. Utilisation de 3h par défaut."
    BACKUP_HOUR=3
fi

# Créer le répertoire de logs si nécessaire
mkdir -p "$(dirname "${CRON_LOG}")"
touch "${CRON_LOG}"
chmod 644 "${CRON_LOG}"
echo "✓ Fichier de log créé: ${CRON_LOG}"

# Créer l'entrée cron (tous les 4 jours à l'heure spécifiée)
# Format cron: minute heure */4 * * (tous les 4 jours)
CRON_ENTRY="0 ${BACKUP_HOUR} */4 * * ${BACKUP_SCRIPT} >> ${CRON_LOG} 2>&1"

# Vérifier si une entrée cron existe déjà
if crontab -l 2>/dev/null | grep -q "${BACKUP_SCRIPT}"; then
    echo ""
    echo "⚠️  Une entrée cron existe déjà pour backup.sh"
    echo "Voulez-vous la remplacer ? (o/n)"
    read -r REPLACE
    
    if [ "$REPLACE" = "o" ] || [ "$REPLACE" = "O" ]; then
        # Supprimer l'ancienne entrée
        crontab -l 2>/dev/null | grep -v "${BACKUP_SCRIPT}" | crontab -
        echo "✓ Ancienne entrée cron supprimée"
    else
        echo "❌ Installation annulée"
        exit 0
    fi
fi

# Ajouter la nouvelle entrée cron
(crontab -l 2>/dev/null; echo "${CRON_ENTRY}") | crontab -

echo ""
echo "✅ Backup automatique configuré !"
echo ""
echo "📋 Configuration:"
echo "   • Script: ${BACKUP_SCRIPT}"
echo "   • Fréquence: Tous les 4 jours à ${BACKUP_HOUR}h00"
echo "   • Logs: ${CRON_LOG}"
echo ""
echo "📝 Entrée cron ajoutée:"
echo "   ${CRON_ENTRY}"
echo ""
echo "🔍 Vérifier les backups:"
echo "   • Voir les logs: tail -f ${CRON_LOG}"
echo "   • Voir le cron: crontab -l"
echo "   • Tester le backup: ${BACKUP_SCRIPT}"
echo ""
echo "⚠️  IMPORTANT:"
echo "   • Vérifiez que le répertoire de backup existe et est accessible"
echo "   • Testez le backup manuellement avant de faire confiance au cron"
echo "   • Surveillez les logs les premiers jours"
echo ""

