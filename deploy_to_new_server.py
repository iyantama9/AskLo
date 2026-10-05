import paramiko
import os
import tarfile
import sys

# Fix Windows console encoding
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except:
        pass

SERVER = "178.128.59.20"
USERNAME = "root"

def create_tarball(source_dir, output_filename, exclude_patterns=None):
    """Create a tarball from source directory"""
    print(f"Creating {output_filename}...")
    exclude_patterns = exclude_patterns or []

    with tarfile.open(output_filename, "w:gz") as tar:
        for item in os.listdir(source_dir):
            # Skip excluded patterns
            if any(pattern in item for pattern in exclude_patterns):
                print(f"  Skipping {item}")
                continue

            item_path = os.path.join(source_dir, item)
            tar.add(item_path, arcname=item)
            print(f"  Added {item}")

    print(f"✓ Tarball created: {output_filename}")
    return True

def get_ssh_client():
    """Create SSH client with key-based authentication"""
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    # Try to connect using SSH keys (no password)
    try:
        client.connect(SERVER, username=USERNAME, timeout=10)
        return client
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return None

def upload_file(local_path, remote_path):
    """Upload file via SCP (more compatible than SFTP)"""
    try:
        client = get_ssh_client()
        if not client:
            return False

        print(f"Uploading {local_path} -> {remote_path}...")

        # Use SCP via shell command instead of SFTP
        with open(local_path, 'rb') as f:
            file_data = f.read()

        # Create remote directory if needed
        remote_dir = os.path.dirname(remote_path)
        stdin, stdout, stderr = client.exec_command(f"mkdir -p {remote_dir}")
        stdout.channel.recv_exit_status()

        # Upload using cat and stdin
        stdin, stdout, stderr = client.exec_command(f"cat > {remote_path}")
        stdin.write(file_data)
        stdin.channel.shutdown_write()
        exit_status = stdout.channel.recv_exit_status()

        client.close()

        if exit_status == 0:
            print(f"✓ Upload successful")
            return True
        else:
            print(f"✗ Upload failed with exit code {exit_status}")
            return False

    except Exception as e:
        print(f"✗ Upload failed: {e}")
        return False

def run_remote_command(client, command, description=""):
    """Execute command on remote server"""
    if description:
        print(f"{description}...")

    stdin, stdout, stderr = client.exec_command(command)
    exit_status = stdout.channel.recv_exit_status()

    out = stdout.read().decode('utf-8').strip()
    err = stderr.read().decode('utf-8').strip()

    if out:
        print(f"  {out}")
    if err:
        print(f"  Error: {err}")

    if exit_status == 0:
        print(f"✓ {description or 'Command'} completed")
    else:
        print(f"✗ {description or 'Command'} failed with exit code {exit_status}")

    return exit_status == 0

def deploy_web():
    """Deploy Flutter web build"""
    print("\n" + "="*60)
    print("DEPLOYING WEB APPLICATION")
    print("="*60)

    # Check if build exists
    if not os.path.exists("build/web"):
        print("✗ build/web not found. Run 'flutter build web' first.")
        return False

    # Create tarball
    tar_name = "deploy_web.tar.gz"
    if not create_tarball("build/web", tar_name):
        return False

    # Upload
    remote_tar = f"/tmp/{tar_name}"
    if not upload_file(tar_name, remote_tar):
        return False

    # Extract and setup
    client = get_ssh_client()
    if not client:
        return False

    commands = [
        ("Creating web directory", "mkdir -p /var/www/getai-web"),
        ("Clearing old web files", "find /var/www/getai-web -mindepth 1 -maxdepth 1 -exec rm -rf {} +"),
        ("Extracting web files", f"tar -xzf {remote_tar} -C /var/www/getai-web/"),
        ("Setting permissions", "chown -R www-data:www-data /var/www/getai-web"),
        ("Cleaning up tarball", f"rm {remote_tar}"),
    ]

    for desc, cmd in commands:
        if not run_remote_command(client, cmd, desc):
            client.close()
            return False

    client.close()
    print("✓ Web deployment complete!")
    return True

def deploy_backend():
    """Deploy Node.js backend"""
    print("\n" + "="*60)
    print("DEPLOYING BACKEND API")
    print("="*60)

    # Create tarball (exclude node_modules)
    tar_name = "deploy_backend.tar.gz"
    if not create_tarball("backend", tar_name, exclude_patterns=["node_modules", ".env"]):
        return False

    # Upload
    remote_tar = f"/tmp/{tar_name}"
    if not upload_file(tar_name, remote_tar):
        return False

    # Extract and setup
    client = get_ssh_client()
    if not client:
        return False

    commands = [
        ("Creating backend directory", "mkdir -p /var/www/getai-api"),
        ("Extracting backend files", f"tar -xzf {remote_tar} -C /var/www/getai-api/"),
        ("Installing dependencies", "cd /var/www/getai-api && npm install --production"),
        ("Cleaning up tarball", f"rm {remote_tar}"),
    ]

    for desc, cmd in commands:
        if not run_remote_command(client, cmd, desc):
            client.close()
            return False

    print("\n⚠ Don't forget to:")
    print("  1. Copy .env file to /var/www/getai-api/")
    print("  2. Setup PM2: pm2 start /var/www/getai-api/src/index.js --name getai-api")
    print("  3. Configure Nginx for the domains")

    client.close()
    print("✓ Backend deployment complete!")
    return True

def deploy_env():
    """Deploy .env file separately"""
    print("\n" + "="*60)
    print("DEPLOYING ENVIRONMENT FILE")
    print("="*60)

    if not os.path.exists("backend/.env"):
        print("✗ backend/.env not found")
        return False

    if not upload_file("backend/.env", "/var/www/getai-api/.env"):
        return False

    print("✓ .env deployment complete!")
    return True

def restart_services():
    """Restart PM2 services"""
    print("\n" + "="*60)
    print("RESTARTING SERVICES")
    print("="*60)

    client = get_ssh_client()
    if not client:
        return False

    run_remote_command(client, "pm2 restart getai-api || pm2 start /var/www/getai-api/src/index.js --name getai-api", "Restarting API")
    run_remote_command(client, "pm2 save", "Saving PM2 configuration")

    client.close()
    print("✓ Services restarted!")
    return True

def main():
    print("\n" + "="*60)
    print("GETAI DEPLOYMENT TO 178.128.59.20")
    print("="*60)

    # Test connection first
    print("\nTesting SSH connection...")
    client = get_ssh_client()
    if not client:
        print("✗ Cannot connect to server. Check SSH key authentication.")
        return

    print("✓ Connected successfully!")
    client.close()

    # Deploy based on argument or deploy all
    deploy_target = sys.argv[1] if len(sys.argv) > 1 else "all"

    if deploy_target in ["all", "web"]:
        if not deploy_web():
            print("\n✗ Web deployment failed!")
            return

    if deploy_target in ["all", "backend"]:
        if not deploy_backend():
            print("\n✗ Backend deployment failed!")
            return

    if deploy_target in ["all", "env"]:
        if not deploy_env():
            print("\n✗ .env deployment failed!")
            return

    if deploy_target in ["all", "restart"]:
        restart_services()

    print("\n" + "="*60)
    print("✓ DEPLOYMENT COMPLETE!")
    print("="*60)
    print("\nWeb: http://178.128.59.20 (configure Nginx)")
    print("API: http://178.128.59.20:4000 (configure Nginx)")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ["--help", "-h"]:
        print("Usage: python deploy_to_new_server.py [target]")
        print("\nTargets:")
        print("  all      - Deploy everything (default)")
        print("  web      - Deploy web only")
        print("  backend  - Deploy backend only")
        print("  env      - Deploy .env file only")
        print("  restart  - Restart services only")
        sys.exit(0)

    main()
