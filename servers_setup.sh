#!/bin/bash

# Ensure a truly non-interactive frontend for all debian package operations
export DEBIAN_FRONTEND=noninteractive

# Pre-answer prompts for iptables-persistent package
printf 'iptables-persistent iptables-persistent/autogenerate_v4 boolean true\n' | debconf-set-selections
printf 'iptables-persistent iptables-persistent/autogenerate_v6 boolean true\n' | debconf-set-selections

# Update and install software packages
echo "Updating apt packages and installing core software..."
sudo DEBCONF_NOWARNINGS=yes DEBCONF_NONINTERACTIVE_SEEN=true apt-get update -y
sudo DEBCONF_NOWARNINGS=yes DEBCONF_NONINTERACTIVE_SEEN=true apt-get install -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    nginx openvpn curl wget vim < /dev/null
echo "Core software installed."


# Nginx Setup
echo "Configuring Nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx
echo "Setting up Nginx test page..."
echo "<h1>Test</h1>" | sudo tee /var/www/html/index.nginx-debian.html
echo "Nginx setup complete."


# OpenVPN Setup
echo "Setting up OpenVPN using Nyr's automated script..."
sudo curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh || { echo "ERROR: Failed to download OpenVPN install script!"; exit 1; }
sudo chmod +x openvpn-install.sh || { echo "ERROR: Failed to make OpenVPN install script executable!"; exit 1; }
echo "Running Nyr's OpenVPN install script (this may take a few minutes)..."
sudo ./openvpn-install.sh --ipv4 --dns 1 --port 1194 --protocol udp --client client --pass no --cipher AES-256-CBC --fast-install || { echo "ERROR: Nyr's OpenVPN install script failed!"; exit 1; }

echo "Copying client configuration to /tmp..."
CLIENT_CONFIG_SOURCE_PATH="/client.ovpn" 
CLIENT_CONFIG_DEST_NAME="client.ovpn"   

if [ -f "$CLIENT_CONFIG_SOURCE_PATH" ]; then
    sudo cp "$CLIENT_CONFIG_SOURCE_PATH" "/tmp/$CLIENT_CONFIG_DEST_NAME" || { echo "ERROR: Failed to copy $CLIENT_CONFIG_DEST_NAME to /tmp!"; exit 1; }
    echo "OpenVPN server setup complete and client config /tmp/$CLIENT_CONFIG_DEST_NAME generated."
    echo "Remember to download /tmp/$CLIENT_CONFIG_DEST_NAME from the instance."
else
    # Backup plan if config file is not found
    echo "WARNING: Client .ovpn file not found at expected path ($CLIENT_CONFIG_SOURCE_PATH). Attempting to locate using find command..."

    # Find any .ovpn file created in the last 5 minutes, prioritizing the one matching "client"
    OVPN_FILE=$(sudo find / -name "*client.ovpn" -o -name "*.ovpn" -mmin -5 -print -quit 2>/dev/null)
    if [ -n "$OVPN_FILE" ]; then
        sudo cp "$OVPN_FILE" "/tmp/$(basename "$OVPN_FILE")" || { echo "ERROR: Failed to copy found .ovpn file to /tmp!"; exit 1; }
        echo "OpenVPN server setup complete and client config /tmp/$(basename "$OVPN_FILE") generated."
        echo "Remember to download /tmp/$(basename "$OVPN_FILE") from the instance."
    else
        echo "ERROR: Could not locate generated client .ovpn file anywhere on the system after OpenVPN installation!"
        exit 1
    fi
fi