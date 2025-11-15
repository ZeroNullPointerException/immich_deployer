# 📸 Installation Immich Sécurisée

Installation automatisée et sécurisée d'Immich avec Docker Compose, Caddy (HTTPS automatique), Fail2ban et sauvegardes automatiques.

## 📋 Table des Matières

- [Fonctionnalités](#fonctionnalités)
- [Architecture](#architecture)
- [Structure du Workspace](#structure-du-workspace)
- [Installation](#installation)
- [Configuration](#configuration)
- [Sauvegardes](#sauvegardes)
- [Commandes Utiles](#commandes-utiles)
- [Sécurité](#sécurité)

## ✨ Fonctionnalités

- ✅ **Immich** : Serveur de photos personnel avec reconnaissance faciale
- ✅ **HTTPS automatique** : Certificats Let's Encrypt via Caddy
- ✅ **Sécurité renforcée** : Fail2ban, rate limiting, headers de sécurité
- ✅ **Sauvegardes automatiques** : Archives compressées, rétention configurable
- ✅ **Mises à jour automatiques** : Watchtower configuré
- ✅ **Isolation réseau** : Base de données et Redis sur réseau privé
- ✅ **Monitoring optionnel** : Uptime Kuma (profil monitoring)

## 🏗️ Architecture

### Services Docker

- **Caddy** : Reverse proxy avec HTTPS automatique (ports 80/443)
- **Immich Server** : API et interface web (port 2283 interne)
- **Immich Machine Learning** : Reconnaissance faciale et IA
- **PostgreSQL** : Base de données (réseau privé)
- **Redis** : Cache (réseau privé)
- **Fail2ban** : Protection contre les attaques brute force
- **Watchtower** : Mises à jour automatiques (dimanche 4h)
- **Uptime Kuma** : Monitoring (optionnel, localhost uniquement)

### Réseaux Docker

- **immich_public** : Services accessibles publiquement (Caddy, Immich Server)
- **immich_private** : Services isolés sans accès Internet (PostgreSQL, Redis, ML)

## 📁 Structure du Workspace

```
./Immich/
├── backups/                    # 📦 Sauvegardes automatiques (2 historiques max)
│   ├── immich_backup_YYYYMMDD_HHMMSS.tar.gz
│   └── immich_backup_YYYYMMDD_HHMMSS.tar.gz
│
├── data/                       # 💾 Données de l'application
│   └── photos/                 # Photos Immich (UPLOAD_LOCATION)
│       ├── original/
│       ├── thumb/
│       └── ...
│
├── logs/                       # 📝 Logs
│   └── access.log              # Logs d'accès Caddy (JSON)
│
├── caddy_data/                 # 🔒 Certificats SSL
│   └── caddy/
│       └── certificates/       # Certificats Let's Encrypt
│
├── caddy_config/               # ⚙️ Configuration Caddy
│   └── caddy/
│       └── autosave.json
│
├── fail2ban/                   # 🛡️ Configuration Fail2ban
│   ├── jail.d/
│   │   └── immich.conf
│   ├── filter.d/
│   │   └── immich-auth.conf
│   └── db/
│       └── fail2ban.sqlite3
│
├── uptime-kuma/                # 📊 Données Uptime Kuma (si activé)
│
├── docker-compose.yml          # 🐳 Configuration Docker Compose
├── .env                        # 🔐 Variables d'environnement (secrets)
├── Caddyfile                    # 🌐 Configuration Caddy (reverse proxy)
│
├── install.sh                  # 📥 Script d'installation
├── backup.sh                   # 💾 Script de sauvegarde
├── restore.sh                  # 🔄 Script de restauration
├── setup-backup-cron.sh        # ⏰ Configuration backups automatiques
├── update-caddyfile.sh         # 🔧 Mise à jour Caddyfile depuis .env
├── check-certificate.sh        # 🔍 Vérification certificat SSL
├── verify-config.sh            # ✅ Vérification de conformité
├── cleanup.sh                  # 🧹 Nettoyage complet
│
├── README.md                   # 📖 Ce fichier
├── SPECIFICATION.md            # 📋 Spécification technique détaillée
├── SECURITY_AUDIT.md           # 🔒 Audit de sécurité
└── VERIFICATION.md             # ✅ Vérifications de conformité
```

### Fichiers et Répertoires

#### 📦 Backups (`./backups/`)
- **Format** : Archive tar.gz unique contenant DB + Photos + Config
- **Rétention** : 2 backups maximum
- **Fréquence** : Tous les 4 jours (configurable)
- **Nom** : `immich_backup_YYYYMMDD_HHMMSS.tar.gz`

#### 💾 Données (`./data/photos/`)
- **Stockage** : Photos Immich (originaux, thumbnails, etc.)
- **Configuration** : Variable `UPLOAD_LOCATION` dans `.env`
- **Par défaut** : `./data/photos/` (dans le workspace)

#### 🔒 Certificats (`./caddy_data/`)
- **Certificats SSL** : Let's Encrypt générés automatiquement
- **Gestion** : Automatique par Caddy
- **Renouvellement** : Automatique

#### 📝 Logs (`./logs/`)
- **Format** : JSON (pour Fail2ban)
- **Rotation** : 10MB, 5 fichiers, 720h (30 jours)
- **Fichier** : `access.log`

## 🚀 Installation

### Prérequis

- Système Linux (Ubuntu/Debian recommandé)
- Accès root ou sudo
- Ports 80 et 443 disponibles
- Domaine Free (ex: `photos.monnom.freeboxos.fr`)

### Installation Automatique

```bash
# 1. Cloner ou télécharger le projet
cd /chemin/vers/Immich

# 2. Rendre le script exécutable
chmod +x install.sh

# 3. Lancer l'installation
sudo ./install.sh
```

Le script va :
1. Installer Docker (si absent)
2. Créer les répertoires nécessaires
3. Demander le domaine et l'email
4. Générer les secrets de sécurité
5. Créer les fichiers de configuration
6. Démarrer les services

### Configuration Post-Installation

1. **Ouvrir les ports sur votre Freebox** :
   - Port 80 (HTTP) → IP de votre machine
   - Port 443 (HTTPS) → IP de votre machine

2. **Configurer le DNS** :
   - Pointer votre domaine Free vers votre IP publique

3. **Attendre le certificat SSL** (2-5 minutes) :
   ```bash
   docker compose logs -f caddy
   ```
   Recherchez : `certificate obtained successfully`

4. **Accéder à Immich** :
   - URL : `https://votre-domaine.freeboxos.fr`
   - Créer votre compte administrateur

## ⚙️ Configuration

### Fichier `.env`

Le fichier `.env` contient toutes les variables de configuration :

```bash
DOMAIN=mytrix.freeboxos.fr
EMAIL=vidal.alan.m@gmail.com
UPLOAD_LOCATION=./data/photos

DB_USERNAME=immich
DB_PASSWORD=...
REDIS_PASSWORD=...
JWT_SECRET=...
```

**⚠️ Important** : Ne partagez JAMAIS le fichier `.env` (contient les secrets).

### Mettre à jour le domaine

```bash
# 1. Modifier DOMAIN dans .env
nano .env

# 2. Régénérer le Caddyfile
./update-caddyfile.sh

# 3. Redémarrer Caddy
docker compose restart caddy
```

## 💾 Sauvegardes

### Sauvegarde Manuelle

```bash
./backup.sh
```

Crée une archive dans `./backups/` contenant :
- Base de données PostgreSQL (dump compressé)
- Photos (toutes les photos)
- Configuration (docker-compose.yml, .env, Caddyfile, fail2ban)

### Restauration

```bash
# Option 1: Choix interactif parmi les backups locaux
./restore.sh

# Option 2: Spécifier un chemin direct
./restore.sh /chemin/vers/immich_backup_YYYYMMDD_HHMMSS.tar.gz

# Option 3: Depuis un disque externe ou PC
./restore.sh /media/disque-externe/immich_backup_YYYYMMDD_HHMMSS.tar.gz
```

### Backups Automatiques

```bash
# Configurer les backups automatiques (tous les 4 jours)
sudo ./setup-backup-cron.sh
```

**Configuration** :
- **Fréquence** : Tous les 4 jours
- **Heure** : Configurable (défaut: 3h du matin)
- **Rétention** : 2 backups maximum
- **Emplacement** : `./backups/`

### Copier un Backup

```bash
# Sur disque externe
cp ./backups/immich_backup_*.tar.gz /media/disque-externe/

# Sur un PC distant (SCP)
scp ./backups/immich_backup_*.tar.gz user@pc:/chemin/
```

## 🛠️ Commandes Utiles

### Gestion des Services

```bash
# Voir l'état des services
docker compose ps

# Voir les logs
docker compose logs -f

# Logs d'un service spécifique
docker compose logs -f caddy
docker compose logs -f immich-server

# Redémarrer un service
docker compose restart caddy

# Redémarrer tous les services
docker compose restart

# Arrêter tous les services
docker compose stop

# Démarrer tous les services
docker compose start

# Arrêter et supprimer les conteneurs (⚠️ garde les données)
docker compose down
```

### Vérifications

```bash
# Vérifier la configuration
./verify-config.sh

# Vérifier le certificat SSL
./check-certificate.sh

# Tester la connexion HTTPS
curl -I https://votre-domaine.freeboxos.fr
```

### Maintenance

```bash
# Mettre à jour les images Docker
docker compose pull
docker compose up -d

# Voir l'espace disque utilisé
du -sh ./*

# Nettoyer les anciennes images Docker
docker image prune -a
```

## 🔒 Sécurité

### Mesures de Sécurité Implémentées

- ✅ **HTTPS automatique** : Certificats Let's Encrypt
- ✅ **HSTS** : Strict-Transport-Security activé
- ✅ **Headers de sécurité** : CSP, X-Frame-Options, etc.
- ✅ **Fail2ban** : Ban automatique après 5 échecs (1h)
- ✅ **Isolation réseau** : PostgreSQL et Redis sur réseau privé
- ✅ **Limites de ressources** : CPU/RAM pour tous les services
- ✅ **Secrets aléatoires** : Génération automatique (DB, Redis, JWT)
- ✅ **Uptime Kuma** : Limité à localhost uniquement
- ✅ **Watchtower sécurisé** : Socket Docker en lecture seule

### Recommandations

- 🔐 Utilisez un **mot de passe fort** (16+ caractères) pour votre compte Immich
- 🔄 **Surveillez les logs** régulièrement : `docker compose logs -f fail2ban`
- 📦 **Faites des backups réguliers** (automatiques configurés)
- 🔍 **Vérifiez les mises à jour** : Les services se mettent à jour automatiquement

## 📦 Structure des Backups

Chaque backup est une archive `immich_backup_YYYYMMDD_HHMMSS.tar.gz` contenant :

```
immich_backup_YYYYMMDD_HHMMSS.tar.gz
├── database.dump.gz          # Base de données PostgreSQL (dump compressé)
├── photos/                   # Toutes les photos
│   ├── original/
│   ├── thumb/
│   └── ...
└── config/                   # Configuration
    ├── docker-compose.yml
    ├── .env                  # ⚠️ Contient les secrets
    ├── Caddyfile
    └── fail2ban/
```

## 🔄 Migration / Déplacement

Pour déplacer l'installation sur une autre machine :

1. **Sauvegarder** : `./backup.sh`
2. **Copier** le répertoire entier ou juste le backup
3. **Installer** sur la nouvelle machine : `sudo ./install.sh`
4. **Restaurer** : `./restore.sh chemin/vers/backup.tar.gz`

## 📊 Monitoring (Optionnel)

### Activer Uptime Kuma

```bash
# Démarrer avec le profil monitoring
docker compose --profile monitoring up -d

# Accéder (localhost uniquement)
http://localhost:3001
```

⚠️ **Sécurité** : Uptime Kuma est limité à localhost pour des raisons de sécurité.

## 🆘 Dépannage

### Erreur 502 Bad Gateway

```bash
# Vérifier que tous les services sont démarrés
docker compose ps

# Vérifier les logs
docker compose logs immich-server
docker compose logs caddy

# Redémarrer les services
docker compose restart
```

### Certificat SSL non généré

```bash
# Vérifier les logs Caddy
docker compose logs caddy | grep -i acme

# Vérifier que le port 80 est accessible depuis Internet
# Vérifier que le DNS pointe vers votre IP publique

# Redémarrer Caddy
docker compose restart caddy
```

### Problème de droits

```bash
# Vérifier les permissions
ls -la .env
chmod 600 .env

# Vérifier les droits sur les répertoires
chown -R $USER:$USER ./
```

## 📚 Documentation

- **SPECIFICATION.md** : Spécification technique détaillée
- **SECURITY_AUDIT.md** : Audit de sécurité complet
- **VERIFICATION.md** : Checklist de vérification

## 📄 Licence

Ce projet est fourni tel quel, sans garantie.

## 🔗 Liens Utiles

- [Documentation Immich](https://immich.app/docs)
- [Documentation Caddy](https://caddyserver.com/docs)
- [Let's Encrypt](https://letsencrypt.org/)

---

**Créé avec ❤️ pour une gestion sécurisée de vos photos**

