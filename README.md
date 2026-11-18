# AWS Three-Tier Architecture

Web tier (nginx) → internal ALB → app tier (PHP) → database tier (RDS MySQL).

```
frontend/            Web page served by nginx on the web tier
backend/api/         PHP API on the app tier (get_messages.php, save_message.php)
backend/db.ini.example   Template for the database settings file
database/schema.sql  Creates the hello_world database and messages table
nginx.conf           Web-tier nginx config (proxies /api/ to the internal ALB)
web-tier-userdata.sh EC2 user data for the web tier
```

## 1. Create the database

From the app-tier server:

```bash
mysql --host=YOUR-RDS-ENDPOINT --user=admin -p < database/schema.sql
```

## 2. Give the backend its database settings

The password is **not** stored in this repository. On the app-tier server:

```bash
sudo mkdir -p /etc/three-tier-app
sudo cp backend/db.ini.example /etc/three-tier-app/db.ini
sudo vi /etc/three-tier-app/db.ini      # set DB_HOST, DB_USER, DB_PASSWORD
```

Then let only the web server read it. Use `apache` if PHP runs under Apache
(httpd), or `nginx` if it runs under nginx with php-fpm:

```bash
sudo chown root:apache /etc/three-tier-app/db.ini
sudo chmod 640 /etc/three-tier-app/db.ini
```

## 3. Point the web tier at the app tier

In `nginx.conf` (or `BACKEND_ALB_URL` in `web-tier-userdata.sh`), replace
`update-me` with the internal ALB's DNS name.
