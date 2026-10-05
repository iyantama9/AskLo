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

def get_ssh_client():
    """Create SSH client with key-based authentication"""
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

    stdin, stdout, stderr = client.exec_command(command)
    exit_status = stdout.channel.recv_exit_status()

    out = stdout.read().decode('utf-8').strip()
    err = stderr.read().decode('utf-8').strip()

    if out:
        print(f"  {out}")
    if err and exit_status != 0:
        print(f"  Error: {err}")

    return exit_status == 0

def setup_server():
    """Setup Node.js, PM2, and Nginx"""
    print("="*60)
    print("SETTING UP SERVER")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    commands = [
        ("Updating package list", "apt-get update"),
        ("Installing Node.js and npm", "apt-get install -y nodejs npm"),
        ("Installing PM2 globally", "npm install -g pm2"),
        ("Installing Nginx", "apt-get install -y nginx"),
        ("Starting PM2 app", "cd /var/www/getai-api && pm2 start src/index.js --name getai-api"),
        ("Saving PM2 configuration", "pm2 save"),
        ("Setting PM2 to start on boot", "pm2 startup systemd -u root --hp /root && pm2 save"),
        ("Checking PM2 status", "pm2 status"),
    ]

    for desc, cmd in commands:
        if not run_command(client, cmd, desc):
            print(f"✗ Failed: {desc}")

    client.close()
    print("\n✓ Server setup complete!")
    return True

def create_nginx_config():
    """Create Nginx configuration"""
    print("\n" + "="*60)
    print("CREATING NGINX CONFIGURATION")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    # Nginx config for web and API
    config = """server {
    listen 80;
    server_name 178.128.59.20;

    # Web application
    location / {
        root /var/www/getai-web;
        try_files $uri $uri/ /index.html;
    }

    # API proxy
    location /api/ {
        proxy_pass http://localhost:4000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
"""

    # Upload config
    stdin, stdout, stderr = client.exec_command("cat > /etc/nginx/sites-available/getai")
    stdin.write(config)
    stdin.channel.shutdown_write()
    stdout.channel.recv_exit_status()

    commands = [
        ("Creating symlink", "ln -sf /etc/nginx/sites-available/getai /etc/nginx/sites-enabled/getai"),
        ("Removing default config", "rm -f /etc/nginx/sites-enabled/default"),
        ("Testing Nginx config", "nginx -t"),
        ("Restarting Nginx", "systemctl restart nginx"),
        ("Enabling Nginx on boot", "systemctl enable nginx"),
    ]

    for desc, cmd in commands:
        run_command(client, cmd, desc)

    client.close()
    print("\n✓ Nginx configured!")
    return True

if __name__ == "__main__":
    print("\n" + "="*60)
    print("GETAI SERVER SETUP - 178.128.59.20")
    print("="*60)

    if setup_server():
        create_nginx_config()

        print("\n" + "="*60)
        print("✓ SETUP COMPLETE!")
        print("="*60)
        print("\nWeb: http://178.128.59.20")
        print("API: http://178.128.59.20/api")
        print("\nPM2 Commands:")
        print("  pm2 logs getai-api    - View logs")
        print("  pm2 restart getai-api - Restart API")
        print("  pm2 status            - Check status")
