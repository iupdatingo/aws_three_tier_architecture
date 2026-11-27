[README.md](https://github.com/user-attachments/files/35521814/README.md)
# PhP Messenger: Three-Tier Architecture on AWS

A highly available three-tier web application deployed on AWS (Europe, London `eu-west-2`).
Visitors read and post messages on a web page; each message passes through the web tier
and the app tier and is stored in an RDS MySQL database.

![PhP Messenger running on AWS](php-messenger-screenshot.png)

## Step-by-Step Guide

### Step 1: Networking
1. Create a VPC (`10.0.0.0/16`) in `eu-west-2`.
2. Create subnets in three Availability Zones: public web, private app and private database.
3. Create an Internet Gateway and attach it to the VPC.
4. Create a NAT Gateway in a public subnet.
5. Create route tables:
   - Public route table: `0.0.0.0/0` → Internet Gateway, associated with the three web subnets.
   - Private route tables for web, app and database: `0.0.0.0/0` → NAT Gateway, with the correct subnet associations.

### Step 2: Security Groups

| Security group | Inbound rule |
|---|---|
| Frontend ALB | HTTP 80 from `0.0.0.0/0` |
| Frontend servers | HTTP 80 from the frontend ALB security group |
| Backend ALB | HTTP 80 from the frontend servers security group |
| Backend servers | HTTP 80 from the backend ALB security group |
| Database | MySQL 3306 from the backend servers security group |

### Step 3: Database
1. Create an RDS MySQL database in the private database subnets.
2. Disable public access and attach the database security group.
3. Single-AZ was used because Multi-AZ isn't available on the free plan.

### Step 4: Load Balancers and Target Groups
1. Create target groups (HTTP 80) for the frontend and backend servers.
   - Frontend health check path: `/health`
   - Backend health check path: `/api/get_messages.php`
2. Create an **internet-facing** frontend ALB across all three AZs.
3. Create an **internal** backend ALB in the private app subnets.

### Step 5: Build the AMIs
Launch a temporary instance for each tier in a public subnet (SSH allowed only while building), install the software below, create an AMI, then terminate the instance and remove the temporary SSH rule.

**Frontend AMI**: install NGINX and git:
```bash
sudo dnf install nginx -y
sudo dnf install git -y
```

**Backend AMI**: install Apache, PHP, the MySQL client and git:
```bash
sudo dnf install -y httpd php php-mysqlnd mariadb105 git
```

### Step 6: Create the Database Table
From a backend server:

```bash
sudo dnf install -y mariadb105
curl -s https://raw.githubusercontent.com/iupdatingo/aws_three_tier_architecture/main/database/schema.sql -o schema.sql
mysql -h <your-rds-endpoint> -u admin -p < schema.sql
```

### Step 7: Launch Templates
Create a launch template for each tier from its AMI and add this under **Advanced details → User data**.

**Frontend launch template:**
```bash
#!/bin/bash
sudo dnf install -y nginx git
cd /usr/share/nginx/html
sudo git clone https://github.com/iupdatingo/aws_three_tier_architecture.git
sudo cp /usr/share/nginx/html/aws_three_tier_architecture/nginx.conf /etc/nginx/nginx.conf
sudo sed -i 's/update-me/<your-backend-alb-dns-name>/g' /etc/nginx/nginx.conf
sudo mv /usr/share/nginx/html/aws_three_tier_architecture/frontend/* /usr/share/nginx/html/
sudo rm -rf /usr/share/nginx/html/aws_three_tier_architecture
sudo systemctl enable --now nginx
```

**Backend launch template:**
```bash
#!/bin/bash
sudo dnf install -y httpd php php-mysqlnd git
sudo systemctl start httpd
cd /var/www/html
sudo git clone https://github.com/iupdatingo/aws_three_tier_architecture.git
sudo mkdir api
sudo mv /var/www/html/aws_three_tier_architecture/backend/api/* /var/www/html/api/
sudo rm -rf /var/www/html/aws_three_tier_architecture
sudo mkdir -p /etc/three-tier-app
sudo tee /etc/three-tier-app/db.ini > /dev/null <<'EOF'
DB_HOST = "<your-rds-endpoint>"
DB_NAME = "hello_world"
DB_USER = "admin"
DB_PASSWORD = "<your-db-password>"
EOF
sudo chown root:apache /etc/three-tier-app/db.ini
sudo chmod 640 /etc/three-tier-app/db.ini
```

> `#!/bin/bash` must be the very first characters of the user data, with no space or blank line before it.

### Step 8: Auto Scaling Groups
Create an Auto Scaling group for each tier with its launch template, subnets, desired capacity and target group.

### Step 9: Roll Out Changes
User data only runs on an instance's first boot, so run an **instance refresh** on the Auto Scaling group after any change to the launch template or this repository.

### Step 10: Test
Open the frontend ALB's DNS name in a browser. The page should list the messages from the database, and new messages should save and appear in the list.

## Difficulties I Faced and How I Solved Them

| Problem | Cause | Fix |
|---|---|---|
| Could not choose Multi-AZ for RDS | Not available on the free plan | Used a single-AZ database for now |
| First instances ran the tutorial's code | Launch template user data still cloned the tutorial's repository, and its URL was misspelt, so the clone failed | Terminated those instances and pointed the launch templates at my own repository |
| My repository was missing files | It had no `backend/api/` folder, and the starter page called an API endpoint that didn't exist (404) | Added the backend API files and the message-board frontend |
| Typos broke scripts | `systemct1` instead of `systemctl`, and a stray `'` after a command | Corrected the commands |
| Database settings were not applied | `db_connection.php` reads `/etc/three-tier-app/db.ini`, so the old `sed` placeholder lines did nothing ("Database settings not found") | Backend user data now writes `db.ini` |
| User data didn't run at all | There was a space before `#!/bin/bash` | Removed it |
| **502 Bad Gateway** | NGINX was pointed at the frontend ALB instead of the backend ALB, creating a loop, and NGINX never started | Used the backend ALB's DNS name and installed the NGINX config from the repo before starting NGINX |
| Backend targets unhealthy (403) | Health check used `/`, which has no page on the backend | Changed the health check path to `/api/get_messages.php` |
| Frontend targets unhealthy | Frontend instances were in public subnets without public IPs, so they couldn't reach GitHub or the package repositories | Enabled auto-assign public IPv4 on the frontend subnets, then ran an instance refresh |
| Changes not showing on running servers | User data only runs on an instance's first boot | Ran an instance refresh after each change |
| Selected the wrong launch template version | Started a refresh with the old version | Cancelled the refresh, set the correct default version and started again |
| Page title needed changing | Still showed the tutorial's title | Renamed it to "PhP Messenger" and refreshed the frontend instances |
