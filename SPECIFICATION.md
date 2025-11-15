# 📋 Spécification Technique - Installation Immich Sécurisée

## 1. Architecture Générale

### 1.1 Stack Technologique
- **Reverse Proxy** : Caddy 2 (Alpine)
- **Application** : Immich (Server + Machine Learning)
- **Base de données** : PostgreSQL 14 avec pgvecto-rs
- **Cache** : Redis 7.2 (Alpine)
- **Monitoring** : Uptime Kuma (optionnel, profil monitoring)
- **Sécurité** : Fail2ban
- **Mises à jour** : Watchtower

### 1.2 Réseaux Docker
- **immich_public** : Réseau bridge pour services accessibles publiquement
  - Caddy (ports 80, 443)
  - Immich-server
  - Uptime Kuma (profil monitoring)
- **immich_private** : Réseau bridge interne (pas d'accès Internet)
  - PostgreSQL
  - Redis
  - Immich-machine-learning

## 2. Services Docker Compose

### 2.1 Caddy (Reverse Proxy)
- **Image** : `caddy:2-alpine`
- **Container** : `immich_caddy`
- **Ports** : `80:80`, `443:443`
- **Volumes** :
  - `./Caddyfile:/etc/caddy/Caddyfile:ro`
  - `./caddy_data:/data`
  - `./caddy_config:/config`
  - `./logs:/var/log/caddy`
- **Réseau** : `immich_public`
- **Dépendances** : `immich-server`
- **Variables** : `DOMAIN` (depuis .env)

### 2.2 Immich Server
- **Image** : `ghcr.io/immich-app/immich-server:release`
- **Container** : `immich_server`
- **Ports** : Aucun (via Caddy uniquement)
- **Volumes** :
  - `${UPLOAD_LOCATION}:/usr/src/app/upload`
  - `/etc/localtime:/etc/localtime:ro`
- **Réseaux** : `immich_public`, `immich_private`
- **Variables d'environnement** :
  - `DB_HOSTNAME=postgres`
  - `DB_USERNAME=${DB_USERNAME}`
  - `DB_PASSWORD=${DB_PASSWORD}`
  - `DB_DATABASE_NAME=${DB_DATABASE_NAME}`
  - `REDIS_HOSTNAME=redis`
  - `REDIS_PASSWORD=${REDIS_PASSWORD}`
  - `LOG_LEVEL=warn`
  - `JWT_SECRET=${JWT_SECRET}`
  - `IMMICH_WORKERS_INCLUDE=api`
- **Limites ressources** :
  - CPU max : 2.0
  - RAM max : 4G
  - CPU réservé : 0.5
  - RAM réservée : 512M

### 2.3 Immich Machine Learning
- **Image** : `ghcr.io/immich-app/immich-machine-learning:release`
- **Container** : `immich_machine_learning`
- **Volumes** : `model_cache:/cache`
- **Réseau** : `immich_private` uniquement
- **Variables d'environnement** : Identiques à immich-server sauf `IMMICH_WORKERS_INCLUDE=machine-learning`
- **Limites ressources** :
  - CPU max : 4.0
  - RAM max : 8G
  - CPU réservé : 1.0
  - RAM réservée : 2G

### 2.4 PostgreSQL
- **Image** : `tensorchord/pgvecto-rs:pg14-v0.2.0`
- **Container** : `immich_postgres`
- **Volumes** : `postgres_data:/var/lib/postgresql/data`
- **Réseau** : `immich_private` uniquement
- **Variables d'environnement** :
  - `POSTGRES_USER=${DB_USERNAME}`
  - `POSTGRES_PASSWORD=${DB_PASSWORD}`
  - `POSTGRES_DB=${DB_DATABASE_NAME}`
  - `POSTGRES_INITDB_ARGS=--data-checksums`
- **Commandes** : Configuration optimisée pour Immich
- **Healthcheck** : `pg_isready` toutes les 30s
- **Limites ressources** :
  - CPU max : 2.0
  - RAM max : 2G
  - CPU réservé : 0.25
  - RAM réservée : 256M

### 2.5 Redis
- **Image** : `redis:7.2-alpine`
- **Container** : `immich_redis`
- **Volumes** : `redis_data:/data`
- **Réseau** : `immich_private` uniquement
- **Command** : `redis-server --requirepass ${REDIS_PASSWORD} --save 60 1 --loglevel warning`
- **Variables d'environnement** :
  - `REDIS_PASSWORD=${REDIS_PASSWORD}`
  - `REDISCLI_AUTH=${REDIS_PASSWORD}` (pour healthcheck)
- **Healthcheck** : `redis-cli ping` avec authentification via REDISCLI_AUTH

### 2.6 Watchtower
- **Image** : `containrrr/watchtower:latest`
- **Container** : `immich_watchtower`
- **Volumes** : `/var/run/docker.sock:/var/run/docker.sock`
- **Réseau** : `host`
- **Schedule** : Dimanche 4h du matin (`0 0 4 * * SUN`)
- **Services surveillés** : `immich_server`, `immich_machine_learning`, `immich_postgres`, `immich_redis`

### 2.7 Uptime Kuma (Optionnel)
- **Image** : `louislam/uptime-kuma:1`
- **Container** : `immich_uptime_kuma`
- **Ports** : `127.0.0.1:3001:3001` (localhost uniquement)
- **Volumes** : `./uptime-kuma:/app/data`
- **Réseau** : `immich_public`
- **Profil** : `monitoring` (démarrage avec `--profile monitoring`)
- **Limites ressources** :
  - CPU max : 1.0
  - RAM max : 512M
  - CPU réservé : 0.1
  - RAM réservée : 128M

### 2.8 Fail2ban
- **Image** : `crazymax/fail2ban:latest`
- **Container** : `immich_fail2ban`
- **Réseau** : `host`
- **Capacités** : `NET_ADMIN`, `NET_RAW`
- **Volumes** :
  - `./fail2ban:/data`
  - `./logs:/var/log/caddy:ro`
- **Configuration** :
  - Bantime : 3600s (1h)
  - Findtime : 600s (10min)
  - Maxretry : 5
  - Ports surveillés : http, https

## 3. Configuration Caddyfile

### 3.1 Configuration Globale
- **Email** : Variable `${EMAIL}` (substituée par install.sh)
- **Admin** : Désactivé
- **Logs** :
  - Format : JSON
  - Niveau : INFO
  - Fichier : `/var/log/caddy/access.log`
  - Rotation : 10MB, 5 fichiers, 720h

### 3.2 Headers de Sécurité
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(), microphone=(), camera=(self)`
- `Content-Security-Policy`: Configuration complète avec `unsafe-inline` et `unsafe-eval` (nécessaire pour Immich)
- Suppression : `Server`, `X-Powered-By`

### 3.3 Rate Limiting
- **Global** : 30 requêtes/seconde par IP
- **Login** : 3 tentatives/minute par IP sur `/api/auth/login`

### 3.4 Reverse Proxy
- **Uploads** (`/api/asset/upload`) : Timeout 30 minutes
- **Autres** : Timeout 5 minutes
- **Headers** : `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`

### 3.5 Redirection
- HTTP → HTTPS : Redirection permanente

## 4. Fichier .env

### 4.1 Variables Requises
- `DOMAIN` : Domaine Free (ex: `photos.monnom.freeboxos.fr`)
- `EMAIL` : Email pour Let's Encrypt (notifications certificats)
- `UPLOAD_LOCATION` : Chemin de stockage des photos
- `DB_USERNAME` : `immich` (fixe)
- `DB_DATABASE_NAME` : `immich` (fixe)
- `DB_PASSWORD` : Généré aléatoirement (32 caractères base64)
- `REDIS_PASSWORD` : Généré aléatoirement (32 caractères base64)
- `JWT_SECRET` : Généré aléatoirement (64 caractères base64)
- `NOTIFICATION_URL` : Optionnel (pour Watchtower)
- `TZ` : `Europe/Paris`

### 4.2 Génération
- Généré par `install.sh` avec `printf` (évite les problèmes de caractères spéciaux)
- Ancien fichier supprimé avant recréation
- Vérification de création réussie

## 5. Script d'Installation (install.sh)

### 5.1 Prérequis
- Exécution en root (`sudo`)
- Système Ubuntu/Debian

### 5.2 Étapes d'Installation
1. **Dépendances** : curl, git, rsync, openssl, ca-certificates, gnupg, lsb-release
2. **Docker** : Installation via script officiel si absent, ajout utilisateur au groupe docker
3. **Répertoires** : Création de logs, caddy_data, caddy_config, fail2ban, uptime-kuma
4. **Stockage** : Configuration du chemin de stockage photos
5. **Secrets** : Génération aléatoire (DB, Redis, JWT)
6. **Domaine** : Saisie domaine et email (tous deux sauvegardés dans .env)
7. **Configuration** : Création .env (avec DOMAIN et EMAIL), Caddyfile (avec substitution ${EMAIL} et ${DOMAIN}), Fail2ban
8. **Démarrage** : Pull images, démarrage services, vérifications

### 5.3 Vérifications Post-Installation
- Validation configuration Docker Compose
- Vérification état des services
- Analyse logs Caddy pour certificat SSL
- Vérification fichiers certificat dans caddy_data

## 6. Sécurité

### 6.1 Chiffrement
- HTTPS automatique via Let's Encrypt
- HSTS activé (1 an, preload)
- Secrets générés aléatoirement (64+ caractères)

### 6.2 Protection Attaques
- Rate limiting global (30 req/s)
- Rate limiting login (3 req/min)
- Fail2ban (ban 1h après 5 échecs)
- Headers de sécurité complets

### 6.3 Isolation
- PostgreSQL et Redis sur réseau privé (pas d'Internet)
- Uptime Kuma limité à localhost
- Services critiques isolés

### 6.4 Limites Ressources
- Tous les services ont des limites CPU/RAM
- Protection contre DoS/consommation excessive

## 7. Fichiers de Configuration

### 7.1 Fichiers Générés par install.sh
- `.env` : Variables d'environnement (DOMAIN, EMAIL, UPLOAD_LOCATION, secrets)
- `Caddyfile` : Configuration Caddy (template avec ${EMAIL} et ${DOMAIN} substitués depuis .env)
- `fail2ban/jail.d/immich.conf` : Configuration Fail2ban
- `fail2ban/filter.d/immich-auth.conf` : Filtres Fail2ban

### 7.2 Fichiers Requis
- `docker-compose.yml` : Configuration Docker Compose
- `install.sh` : Script d'installation
- `backup.sh` : Script de sauvegarde (optionnel)

## 8. Conformité et Vérifications

### 8.1 Vérifications à Effectuer
- [ ] Toutes les variables .env sont définies (DOMAIN, EMAIL, UPLOAD_LOCATION, etc.)
- [ ] Caddyfile contient ${EMAIL} et ${DOMAIN} substitués avec les valeurs du .env
- [ ] Ports correctement mappés
- [ ] Réseaux correctement configurés
- [ ] Healthchecks fonctionnels
- [ ] Limites de ressources définies
- [ ] Secrets générés aléatoirement
- [ ] Permissions fichiers correctes

### 8.2 Tests Post-Installation
- [ ] Services démarrés : `docker compose ps`
- [ ] Certificat SSL généré : `docker compose logs caddy | grep certificate`
- [ ] Accès HTTPS : `curl -I https://${DOMAIN}`
- [ ] Fail2ban actif : `docker compose logs fail2ban`
- [ ] Healthchecks OK : `docker compose ps` (tous healthy)

