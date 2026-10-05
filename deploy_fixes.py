import paramiko
import sys
import os
from pathlib import Path

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

def upload_file(sftp, local_path, remote_path, description=""):
    """Upload a single file"""
    if description:
        print(f"\n{description}...")
    try:
        sftp.put(local_path, remote_path)
        print(f"  ✓ Uploaded: {os.path.basename(local_path)}")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False

def deploy_backend():
    """Deploy backend CORS fix"""
    print("="*60)
    print("DEPLOYING BACKEND FIXES")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    sftp = client.open_sftp()

    # Upload updated files.js
    local_file = "backend/src/routes/files.js"
    remote_file = "/var/www/getai-api/src/routes/files.js"

    if not upload_file(sftp, local_file, remote_file, "Uploading files.js with CORS fix"):
        sftp.close()
        client.close()
        return False

    # Restart PM2
    commands = [
        ("Restarting PM2 backend", "pm2 restart getai-api"),
        ("Checking PM2 status", "pm2 status"),
        ("Showing backend logs", "pm2 logs getai-api --lines 20 --nostream"),
    ]

    for desc, cmd in commands:
        run_command(client, cmd, desc)

    sftp.close()
    client.close()
    print("\n✓ Backend deployment complete!")
    return True

def build_flutter_web():
    """Build Flutter web with keyboard fix"""
    print("\n" + "="*60)
    print("BUILDING FLUTTER WEB")
    print("="*60)

    import subprocess

    commands = [
        ("flutter clean", "Cleaning Flutter build cache"),
        ("flutter build web --release", "Building Flutter web (release mode)"),
    ]

    for cmd, desc in commands:
        print(f"\n{desc}...")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  ✗ Failed: {result.stderr}")
            return False
        print(f"  ✓ Success")

    return True

def deploy_web():
    """Deploy Flutter web build"""
    print("\n" + "="*60)
    print("DEPLOYING WEB BUILD")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    sftp = client.open_sftp()

    # Create backup
    run_command(client, "cp -r /var/www/getai-web /var/www/getai-web.backup.$(date +%Y%m%d-%H%M%S)", "Creating backup")

    # Upload web build
    web_build_dir = "build/web"
    remote_dir = "/var/www/getai-web"

    print(f"\nUploading web files...")

    # Get all files in build/web
    for root, dirs, files in os.walk(web_build_dir):
        for file in files:
            local_path = os.path.join(root, file)
            relative_path = os.path.relpath(local_path, web_build_dir)
            remote_path = f"{remote_dir}/{relative_path}".replace('\\', '/')

            # Ensure remote directory exists
            remote_dir_path = os.path.dirname(remote_path)
            try:
                sftp.stat(remote_dir_path)
            except:
                # Create directory if it doesn't exist
                run_command(client, f"mkdir -p {remote_dir_path}")

            try:
                sftp.put(local_path, remote_path)
                print(f"  ✓ {relative_path}")
            except Exception as e:
                print(f"  ✗ {relative_path}: {e}")

    # Set permissions
    run_command(client, f"chown -R www-data:www-data {remote_dir}", "Setting permissions")
    run_command(client, f"chmod -R 755 {remote_dir}", "Setting file permissions")

    sftp.close()
    client.close()
    print("\n✓ Web deployment complete!")
    return True

def main():
    """Main deployment flow"""
    print("\n🚀 ASKCORE DEPLOYMENT - CORS & KEYBOARD FIXES")
    print("="*60)

    # Step 1: Deploy backend
    if not deploy_backend():
        print("\n❌ Backend deployment failed!")
        return False

    # Step 2: Build Flutter web
    if not build_flutter_web():
        print("\n❌ Flutter web build failed!")
        return False

    # Step 3: Deploy web
    if not deploy_web():
        print("\n❌ Web deployment failed!")
        return False

    print("\n" + "="*60)
    print("✅ DEPLOYMENT COMPLETE!")
    print("="*60)
    print("\n🌐 Web: http://178.128.59.20")
    print("🔧 API: http://178.128.59.20/api")
    print("\nFixed issues:")
    print("  ✓ Image loading (CORS headers)")
    print("  ✓ Mobile keyboard covering input")

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
