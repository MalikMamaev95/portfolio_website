#!/bin/bash

# Variables
export AWS_REGION="eu-north-1"
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
              "Name=architecture,Values=x86_64" \
              "Name=virtualization-type,Values=hvm" \
              "Name=root-device-type,Values=ebs" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --region "$AWS_REGION" \
    --output text)
INSTANCE_TYPE="t3.micro"
KEY_PAIR_NAME="portfolio-website-key"
SSH_KEY_FILE_PATH="$(pwd)/$KEY_PAIR_NAME.pem"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
USER_DATA_SCRIPT="servers_setup.sh"
USER_DATA_CONTENT=$(cat "$USER_DATA_SCRIPT")

# SSH Configuration
echo "Creating Key Pair: $KEY_PAIR_NAME..."
# Check if key pair already exists
aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" 2>/dev/null
if [ $? -ne 0 ]; then
    aws ec2 create-key-pair \
        --key-name "$KEY_PAIR_NAME" \
        --query 'KeyMaterial' \
        --region "$AWS_REGION" \
        --output text > "$SSH_KEY_FILE_PATH" 
    chmod 400 "$SSH_KEY_FILE_PATH" 
    echo "Key pair '$KEY_PAIR_NAME' created and saved to '$SSH_KEY_FILE_PATH'." 
else
    echo "Key pair '$KEY_PAIR_NAME' already exists. Skipping creation."
    if [ ! -f "$SSH_KEY_FILE_PATH" ]; then 
        echo "WARNING: Existing key pair found in AWS, but .pem file not found locally. SSH access might fail."
    fi
fi

# VPC Configuration
echo "Creating VPC with CIDR: $VPC_CIDR..."

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "$VPC_CIDR" \
    --query 'Vpc.VpcId' \
    --region "$AWS_REGION" \
    --output text)

aws ec2 create-tags \
    --resources "$VPC_ID" \
    --tags Key=Name,Value="PortfolioWebsiteVPC" \
    --region "$AWS_REGION"
echo "VPC ID: $VPC_ID"

# Subnet Configuration
echo "Creating Subnet with CIDR: $SUBNET_CIDR in VPC: $VPC_ID..."
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$SUBNET_CIDR" \
    --query 'Subnet.SubnetId' \
    --region "$AWS_REGION" \
    --output text)

aws ec2 create-tags \
    --resources "$SUBNET_ID" \
    --tags Key=Name,Value="PublicSubnet" \
    --region "$AWS_REGION"
echo "Subnet ID: $SUBNET_ID"

# Enable auto-assign public IPv4 address for instances launched in this subnet
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"

# Internet Gateway Configuration
echo "Creating Internet Gateway..."

IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --region "$AWS_REGION" \
    --output text)

aws ec2 create-tags \
    --resources "$IGW_ID" \
    --tags Key=Name,Value="IGW" \
    --region "$AWS_REGION"

echo "Internet Gateway ID: $IGW_ID"

echo "5. Attaching Internet Gateway to VPC: $VPC_ID..."
aws ec2 attach-internet-gateway \
    --vpc-id "$VPC_ID" \
    --internet-gateway-id "$IGW_ID" \
    --region "$AWS_REGION"

# Route Table Configuration
echo "6. Creating Route Table for VPC: $VPC_ID..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --query 'RouteTable.RouteTableId' \
    --region "$AWS_REGION" \
    --output text)

aws ec2 create-tags \
    --resources "$ROUTE_TABLE_ID" \
    --tags Key=Name,Value="RouteTable" \
    --region "$AWS_REGION"

echo "Route Table ID: $ROUTE_TABLE_ID"

echo "7. Creating route to Internet Gateway for 0.0.0.0/0..."
aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID" \
    --region "$AWS_REGION"

echo "8. Associating Route Table: $ROUTE_TABLE_ID with Subnet: $SUBNET_ID..."
aws ec2 associate-route-table \
    --route-table-id "$ROUTE_TABLE_ID" \
    --subnet-id "$SUBNET_ID" \
    --region "$AWS_REGION"

# Security Group Configuration
echo "9. Creating Security Group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "PortfolioSecurityGroup" \
    --description "Allow SSH, HTTP, HTTPS, and OpenVPN traffic" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --region "$AWS_REGION" \
    --output text)

aws ec2 create-tags \
    --resources "$SECURITY_GROUP_ID" \
    --tags Key=Name,Value="PortfolioSecurityGroup" \
    --region "$AWS_REGION"
echo "Security Group ID: $SECURITY_GROUP_ID"

# Ingress rules for Security Group
# SSH (Port 22) - still allowing from anywhere to allow initial setup
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

# HTTP (Port 80)
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

# HTTPS (Port 443)
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

# OpenVPN (Port 1194 UDP)
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol udp \
    --port 1194 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

# Launch EC2 Instance
echo "Launching EC2 Instance with AMI: $AMI_ID, Instance Type: $INSTANCE_TYPE..."

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_PAIR_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --user-data "$USER_DATA_CONTENT" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=MyPortfolioServer}]' \
    --query 'Instances[0].InstanceId' \
    --region "$AWS_REGION" \
    --output text)

echo "Waiting for instance to be in 'running' state"
aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION"
sleep 180

# Allocate and Associate Elastic IP
echo "Allocating Elastic IP"
EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
    --query 'AllocationId' \
    --region "$AWS_REGION" \
    --output text)
echo "Elastic IP Allocation ID: $EIP_ALLOCATION_ID"

echo "Associating Elastic IP with instance: $INSTANCE_ID"
sleep 10 
aws ec2 associate-address \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$EIP_ALLOCATION_ID" \
    --region "$AWS_REGION"
echo "Elastic IP associated."

echo "Getting Public IP of EC2 Instance"
EC2_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --region "$AWS_REGION" \
    --output text)

echo "EC2 Instance Public IP: $EC2_PUBLIC_IP"

echo "Waiting for SSH to be ready on the instance..."
until ssh -o ConnectTimeout=10 -i "$SSH_KEY_FILE_PATH" ubuntu@"$EC2_PUBLIC_IP" echo "SSH ready." > /dev/null 2>&1; do
    echo "SSH not ready yet, retrying in 10 seconds..."
    sleep 10
done
echo "SSH ready. Proceeding with client.ovpn update."


# Update client.ovpn on the instance with the correct Elastic IP
echo "Updating client.ovpn on the instance with Elastic IP: $EC2_PUBLIC_IP..."
printf "sudo sed -i \"s/^remote [0-9.]* 1194\$/remote %s 1194/\" /tmp/client.ovpn" "$EC2_PUBLIC_IP" | \
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE_PATH" ubuntu@"$EC2_PUBLIC_IP" "bash" || \
{ echo "ERROR: Failed to update client.ovpn on instance! Check SSH connectivity and file permissions."; exit 1; }
echo "client.ovpn updated on instance."

echo "Copying client.ovpn from instance..." 
scp -i "$SSH_KEY_FILE_PATH" ubuntu@"$EC2_PUBLIC_IP":/tmp/client.ovpn ./client.ovpn || \
{ echo "ERROR: Failed to copy client.ovpn from instance."; exit 1; }
echo "Deployment complete!"
echo "Your website should be accessible at: http://$EC2_PUBLIC_IP"

# Save IDs for remove script
echo "$VPC_ID" > .vpc_id
echo "$SUBNET_ID" > .subnet_id
echo "$IGW_ID" > .igw_id
echo "$ROUTE_TABLE_ID" > .route_table_id
echo "$SECURITY_GROUP_ID" > .security_group_id
echo "$INSTANCE_ID" > .instance_id
echo "$EIP_ALLOCATION_ID" > .eip_allocation_id