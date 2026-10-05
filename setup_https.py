import paramiko
import sys

# Fix Windows console encoding
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except:
        pass

SERVER = "178.128.59.20"
USERNAME = "root"
DOMAIN = "askcore.dev"

def get_ssh_client():
    """Create SSH client"""
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(SERVER, username=USERNAME, timeout=10)
        return client
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return None

def run_command(client, command, description=""):
    """Execute command on remote server"""
    if description:
        print(f"\n{description}...")

    stdin, stdout, stderr = client.exec_command(command, get_pty=True)

    # Stream output in real-time for interactive commands
    while True:
        line = stdout.readline()
        if not line:
            break
        print(line.rstrip())

    exit_status = stdout.channel.recv_exit_status()

    if exit_status == 0:
        print(f"✓ {description or 'Command'} completed")
    else:
        print(f"✗ {description or 'Command'} failed with exit code {exit_status}")

    return exit_status == 0

def check_dns():
    """Check if DNS is pointing to the server"""
    print("="*60)
    print("CHECKING DNS CONFIGURATION")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    print(f"\nChecking if {DOMAIN} points to {SERVER}...")
    run_command(client, f"dig +short {DOMAIN} @8.8.8.8", "DNS Lookup")

    client.close()
    return True

def install_certbot():
    """Install Certbot for Let's Encrypt"""
    print("\n" + "="*60)
    print("INSTALLING CERTBOT")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    commands = [
        ("Installing snapd", "apt-get install -y snapd"),
        ("Updating snapd", "snap install core && snap refresh core"),
        ("Removing old certbot", "apt-get remove -y certbot || true"),
        ("Installing certbot", "snap install --classic certbot"),
        ("Creating symlink", "ln -sf /snap/bin/certbot /usr/bin/certbot"),
    ]

    for desc, cmd in commands:
        run_command(client, cmd, desc)

    client.close()
    print("\n✓ Certbot installed!")
    return True

def get_ssl_certificate(email):
    """Get SSL certificate from Let's Encrypt"""
    print("\n" + "="*60)
    print("GETTING SSL CERTIFICATE")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    # Get certificate for both domain and www subdomain
    cmd = f"certbot --nginx -d {DOMAIN} -d www.{DOMAIN} --non-interactive --agree-tos --email {email} --redirect"

    run_command(client, cmd, "Obtaining SSL certificate")

    client.close()
    print("\n✓ SSL certificate obtained!")
    return True

def update_nginx_config():
    """Update Nginx configuration for the domain"""
    print("\n" + "="*60)
    print("UPDATING NGINX CONFIGURATION")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    # Updated Nginx config with domain name
    config = f"""server {{
    listen 80;
    server_name {DOMAIN} www.{DOMAIN};

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}}

server {{
    listen 443 ssl http2;
    server_name {DOMAIN} www.{DOMAIN};

    # SSL managed by Certbot
    ssl_certificate /etc/letsencrypt/live/{DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Web application
    location / {{
        root /var/www/getai-web;
        try_files $uri $uri/ /index.html;

        # Cache static assets
        location ~* \\.(?:css|js|jpg|jpeg|gif|png|ico|svg|woff|woff2|ttf|eot)$ {{
            expires 1y;
            add_header Cache-Control "public, immutable";
        }}
    }}

    # API proxy
    location /api/ {{
        proxy_pass http://localhost:4000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for long-running requests (streaming)
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }}
}}
"""

    # Upload config before certbot (certbot will modify it)
    stdin, stdout, stderr = client.exec_command(f"cat > /etc/nginx/sites-available/getai-ssl")
    stdin.write(config)
    stdin.channel.shutdown_write()
    stdout.channel.recv_exit_status()

    commands = [
        ("Creating symlink", "ln -sf /etc/nginx/sites-available/getai-ssl /etc/nginx/sites-enabled/getai-ssl"),
        ("Removing old config", "rm -f /etc/nginx/sites-enabled/getai"),
        ("Testing Nginx config", "nginx -t"),
        ("Restarting Nginx", "systemctl restart nginx"),
    ]

    for desc, cmd in commands:
        run_command(client, cmd, desc)

    client.close()
    print("\n✓ Nginx updated for HTTPS!")
    return True

def setup_auto_renewal():
    """Setup automatic SSL renewal"""
    print("\n" + "="*60)
    print("SETTING UP AUTO-RENEWAL")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    commands = [
        ("Testing renewal", "certbot renew --dry-run"),
        ("Checking renewal timer", "systemctl status certbot.timer"),
    ]

    for desc, cmd in commands:
        run_command(client, cmd, desc)

    client.close()
    print("\n✓ Auto-renewal configured!")
    return True

def main():
    print("\n" + "="*60)
    print(f"HTTPS SETUP FOR {DOMAIN}")
    print("="*60)

    # Get email from command line argument
    if len(sys.argv) < 2:
        print("\nUsage: python setup_https.py <your-email@example.com>")
        print("\nExample: python setup_https.py admin@askcore.dev")
        return

    email = sys.argv[1].strip()
    if not email or '@' not in email:
        print("✗ Invalid email address")
        return

    print(f"\nEmail for SSL notifications: {email}")
    print(f"Domain: {DOMAIN}")
    print(f"Server: {SERVER}")

    # Check DNS
    print("\nChecking DNS configuration...")
    if not check_dns():
        print("\n✗ DNS check failed!")
        return

    # Install certbot
    if not install_certbot():
        print("\n✗ Certbot installation failed!")
        return

    # Update Nginx config first (before certbot)
    if not update_nginx_config():
        print("\n✗ Nginx update failed!")
        return

    # Get SSL certificate
    if not get_ssl_certificate(email):
        print("\n✗ SSL certificate failed!")
        return

    # Setup auto-renewal
    setup_auto_renewal()

    print("\n" + "="*60)
    print("✓ HTTPS SETUP COMPLETE!")
    print("="*60)
    print(f"\nYour site is now available at:")
    print(f"  https://{DOMAIN}")
    print(f"  https://www.{DOMAIN}")
    print(f"\nAPI endpoint:")
    print(f"  https://{DOMAIN}/api")
    print(f"\nSSL certificate will auto-renew every 60 days.")

if __name__ == "__main__":
    main()
