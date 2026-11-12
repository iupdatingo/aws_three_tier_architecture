#!/bin/bash
# Web tier EC2 user data
# Installs nginx, writes nginx.conf (proxies /api/ to the backend ALB) and a
# starter frontend, so no external git repo is needed.
# User data runs as root, so sudo is not required.
set -euo pipefail

# >>> Set this to your internal (backend) ALB DNS name <<<
BACKEND_ALB_URL="insert-your-backend-alb-url-here"

# ---------------------------------------------------------------------------
# 1. Install nginx (Amazon Linux 2023 uses dnf; Amazon Linux 2 uses yum/extras)
# ---------------------------------------------------------------------------
if command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx
else
  amazon-linux-extras install -y nginx1 || yum install -y nginx
fi

# ---------------------------------------------------------------------------
# 2. nginx.conf  (quoted 'EOF' keeps $variables literal for nginx)
# ---------------------------------------------------------------------------
cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile          on;
    keepalive_timeout 65;
    include           /etc/nginx/mime.types;
    default_type      application/octet-stream;

    server {
        listen      80 default_server;
        listen      [::]:80 default_server;
        server_name _;
        root        /usr/share/nginx/html;
        index       index.html;

        # Health check for the external ALB target group
        location = /health {
            default_type text/plain;
            return 200 "OK\n";
        }

        # Forward API calls to the app tier through the internal ALB
        location /api/ {
            proxy_pass         http://update-me:80;
            proxy_http_version 1.1;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }

        # Single-page-app fallback
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF

# Same placeholder swap as the original script
sed -i "s/update-me/${BACKEND_ALB_URL}/g" /etc/nginx/nginx.conf

# --------------------------------------------------------------------------
# 3. Frontend (replaces the repo's frontend/ folder)
# --------------------------------------------------------------------------
rm -rf /usr/share/nginx/html/*

cat > /usr/share/nginx/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Three-Tier App</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 3rem auto; padding: 0 1rem; color: #222; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 1rem 1.25rem; margin-top: 1rem; }
    .ok { color: #1a7f37; } .err { color: #cf222e; }
    button { padding: .5rem 1rem; cursor: pointer; }
    pre { background: #f6f8fa; padding: .75rem; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>Three-Tier Web App</h1>
  <p>Web tier: nginx on EC2 &rarr; Internal ALB &rarr; App tier &rarr; RDS</p>

  <div class="card">
    <h2>Web tier</h2>
    <p>Served by: <strong id="host"></strong></p>
    <p class="ok">Frontend is up.</p>
  </div>

  <div class="card">
    <h2>App tier</h2>
    <button id="check">Call /api/health</button>
    <p id="status"></p>
    <pre id="output" hidden></pre>
  </div>

  <script>
    document.getElementById('host').textContent = location.host;
    document.getElementById('check').addEventListener('click', async () => {
      const status = document.getElementById('status');
      const output = document.getElementById('output');
      status.textContent = 'Calling backend…';
      status.className = '';
      try {
        const res = await fetch('/api/health');
        const text = await res.text();
        status.textContent = res.ok ? 'Backend reachable' : 'Backend returned ' + res.status;
        status.className = res.ok ? 'ok' : 'err';
        output.textContent = text;
        output.hidden = false;
      } catch (e) {
        status.textContent = 'Could not reach backend: ' + e.message;
        status.className = 'err';
        output.hidden = true;
      }
    });
  </script>
</body>
</html>
EOF

chown -R nginx:nginx /usr/share/nginx/html

# --------------------------------------------------------------------------
# 4. Validate config and start nginx
# --------------------------------------------------------------------------
nginx -t
systemctl enable --now nginx
