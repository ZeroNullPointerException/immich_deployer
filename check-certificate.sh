#!/bin/bash

# ============================================
# SCRIPT DE VÉRIFICATION DU CERTIFICAT SSL
# ============================================
# Vérifie si le certificat Let's Encrypt a été généré correctement

set -e

echo "========================================"
echo "   Vérification du Certificat SSL"
echo "========================================"
echo ""

# Charger les variables d'environnement
if [ -f .env ]; then
    source .env
    echo "✓ Fichier .env chargé"
else
    echo "❌ Fichier .env introuvable"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "❌ Variable DOMAIN non définie dans .env"
    exit 1
fi

echo "🌐 Domaine configuré: ${DOMAIN}"
echo ""

# 1. Vérifier que Caddy est en cours d'exécution
echo "🔍 [1/5] Vérification du conteneur Caddy..."
if docker compose ps caddy | grep -q "Up"; then
    echo "✓ Caddy est en cours d'exécution"
else
    echo "❌ Caddy n'est pas en cours d'exécution"
    echo "   Démarrez avec: docker compose up -d caddy"
    exit 1
fi

# 2. Vérifier les logs Caddy pour le certificat
echo ""
echo "🔍 [2/5] Analyse des logs Caddy..."
CADDY_LOGS=$(docker compose logs caddy 2>&1 | tail -100)

if echo "$CADDY_LOGS" | grep -qi "certificate obtained\|certificate issued\|acme.*success"; then
    echo "✅ Certificat Let's Encrypt généré avec succès !"
    CERT_STATUS="OK"
elif echo "$CADDY_LOGS" | grep -qi "acme.*challenge\|obtaining certificate"; then
    echo "⏳ Certificat en cours de génération..."
    CERT_STATUS="PENDING"
elif echo "$CADDY_LOGS" | grep -qi "acme.*error\|challenge.*failed\|port.*80.*refused\|connection refused"; then
    echo "❌ ERREUR: Le certificat n'a pas pu être généré"
    CERT_STATUS="ERROR"
    echo ""
    echo "Dernières erreurs détectées:"
    echo "$CADDY_LOGS" | grep -i "error\|failed\|refused" | tail -5
else
    echo "ℹ️  Aucune information claire sur le certificat dans les logs"
    CERT_STATUS="UNKNOWN"
fi

# 3. Vérifier les fichiers de certificat
echo ""
echo "🔍 [3/5] Vérification des fichiers de certificat..."
if [ -d "caddy_data" ]; then
    CERT_FILES=$(find caddy_data -type f \( -name "*.crt" -o -name "*.key" \) 2>/dev/null | wc -l)
    if [ "$CERT_FILES" -gt 0 ]; then
        echo "✓ $CERT_FILES fichier(s) de certificat trouvé(s) dans caddy_data"
        find caddy_data -type f \( -name "*.crt" -o -name "*.key" \) 2>/dev/null | head -5
    else
        echo "⚠️  Aucun fichier de certificat trouvé dans caddy_data"
    fi
else
    echo "⚠️  Le répertoire caddy_data n'existe pas"
fi

# 4. Vérifier la résolution DNS
echo ""
echo "🔍 [4/5] Vérification de la résolution DNS..."
DOMAIN_IP=$(dig +short ${DOMAIN} 2>/dev/null | head -1 || nslookup ${DOMAIN} 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
if [ -n "$DOMAIN_IP" ]; then
    echo "✓ Le domaine ${DOMAIN} résout vers: ${DOMAIN_IP}"
    
    # Obtenir l'IP publique
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "non disponible")
    if [ "$PUBLIC_IP" != "non disponible" ]; then
        echo "  Votre IP publique: ${PUBLIC_IP}"
        if [ "$DOMAIN_IP" = "$PUBLIC_IP" ]; then
            echo "  ✅ Le DNS pointe correctement vers votre IP publique"
        else
            echo "  ⚠️  Le DNS ne pointe pas vers votre IP publique"
            echo "     Vérifiez la configuration DNS de votre domaine"
        fi
    fi
else
    echo "❌ Impossible de résoudre le domaine ${DOMAIN}"
    echo "   Vérifiez que le DNS est configuré correctement"
fi

# 5. Tester la connexion HTTPS
echo ""
echo "🔍 [5/5] Test de la connexion HTTPS..."
if command -v curl &> /dev/null; then
    HTTPS_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://${DOMAIN} 2>&1 || echo "000")
    if [ "$HTTPS_TEST" = "200" ] || [ "$HTTPS_TEST" = "301" ] || [ "$HTTPS_TEST" = "302" ]; then
        echo "✅ Connexion HTTPS réussie (code: $HTTPS_TEST)"
        
        # Vérifier le certificat
        CERT_INFO=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "")
        if [ -n "$CERT_INFO" ]; then
            echo ""
            echo "📜 Informations du certificat:"
            echo "$CERT_INFO" | head -3
        fi
    elif [ "$HTTPS_TEST" = "000" ]; then
        echo "❌ Impossible de se connecter à https://${DOMAIN}"
        echo "   Vérifiez que:"
        echo "   • Les ports 80 et 443 sont ouverts"
        echo "   • Le domaine pointe vers cette machine"
        echo "   • Caddy est en cours d'exécution"
    else
        echo "⚠️  Connexion HTTPS retourne le code: $HTTPS_TEST"
    fi
else
    echo "ℹ️  curl n'est pas installé, test HTTPS ignoré"
fi

# Résumé
echo ""
echo "========================================"
echo "   RÉSUMÉ"
echo "========================================"
echo ""

case "$CERT_STATUS" in
    OK)
        echo "✅ Le certificat Let's Encrypt est généré et fonctionne"
        echo ""
        echo "🌐 Accédez à: https://${DOMAIN}"
        ;;
    PENDING)
        echo "⏳ Le certificat est en cours de génération"
        echo ""
        echo "   Attendez 1-2 minutes supplémentaires"
        echo "   Surveillez avec: docker compose logs -f caddy"
        ;;
    ERROR)
        echo "❌ Le certificat n'a pas pu être généré"
        echo ""
        echo "   Actions à vérifier:"
        echo "   1. Les ports 80 et 443 sont-ils ouverts sur votre Freebox ?"
        echo "   2. Le domaine ${DOMAIN} pointe-t-il vers votre IP publique ?"
        echo "   3. Le DNS est-il propagé ? (vérifiez avec: nslookup ${DOMAIN})"
        echo "   4. Consultez les logs: docker compose logs caddy"
        echo ""
        echo "   Alternative: Si vous ne pouvez pas ouvrir le port 80,"
        echo "   vous devrez utiliser la méthode DNS-01 (plus complexe)"
        ;;
    *)
        echo "ℹ️  État du certificat indéterminé"
        echo ""
        echo "   Consultez les logs: docker compose logs caddy"
        ;;
esac

echo ""
echo "📋 Commandes utiles:"
echo "   • Voir les logs Caddy:     docker compose logs -f caddy"
echo "   • Redémarrer Caddy:         docker compose restart caddy"
echo "   • Vérifier les ports:       netstat -tuln | grep -E ':(80|443)'"
echo "   • Tester le DNS:            nslookup ${DOMAIN}"
echo "========================================"

