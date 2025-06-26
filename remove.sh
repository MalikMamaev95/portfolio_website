#!/bin/bash
# Shebang.

# --- Variables ---
export AWS_REGION="eu-north-1"
KEY_PAIR_NAME="portfolio-website-key"

# Read IDs from file
VPC_ID=$(cat .vpc_id 2>/dev/null)
SUBNET_ID=$(cat .subnet_id 2>/dev/null)
IGW_ID=$(cat .igw_id 2>/dev/null)
ROUTE_TABLE_ID=$(cat .route_table_id 2>/dev/null)
SECURITY_GROUP_ID=$(cat .security_group_id 2>/dev/null)
INSTANCE_ID=$(cat .instance_id 2>/dev/null)
EIP_ALLOCATION_ID=$(cat .eip_allocation_id 2>/dev/null)

echo "Starting teardown process..."

# Terminate EC2 Instance ---
if [ -n "$INSTANCE_ID" ]; then
    echo "1. Terminating EC2 Instance: $INSTANCE_ID..."
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    echo "Instance terminated."
else
    echo "No instance ID found or instance already terminated. Skipping instance termination."
fi

# Delete Key Pair from AWS
if [ -n "$KEY_PAIR_NAME" ]; then
    echo "11. Deleting EC2 Key Pair from AWS: $KEY_PAIR_NAME..."
    aws ec2 delete-key-pair --key-name "$KEY_PAIR_NAME" --region "$AWS_REGION"
    if [ $? -eq 0 ]; then
        echo "EC2 Key Pair '$KEY_PAIR_NAME' deleted from AWS."
    else
        echo "Failed to delete EC2 Key Pair '$KEY_PAIR_NAME' from AWS. It might not exist or there was an error."
    fi
else
    echo "No Key Pair Name found. Skipping EC2 Key Pair deletion from AWS."
fi

# Delete Local Key Pair
if [ -f "$KEY_PAIR_NAME.pem" ]; then
    echo "2. Deleting local key pair file: $KEY_PAIR_NAME.pem..."
    rm "$KEY_PAIR_NAME.pem"
    echo "Local key pair file deleted."
fi

# Release Elastic IP
if [ -n "$EIP_ALLOCATION_ID" ]; then
    echo "3. Releasing Elastic IP (Allocation ID): $EIP_ALLOCATION_ID..."
    aws ec2 release-address --allocation-id "$EIP_ALLOCATION_ID" --region "$AWS_REGION"
    rm -f .eip_allocation_id
    if [ $? -eq 0 ]; then
        echo "Elastic IP released successfully."
    else
        echo "Failed to release Elastic IP. You may need to release it manually in the AWS console."
    fi
else
    echo "No Elastic IP Allocation ID found. Skipping EIP release."
fi

# Delete Security Group
if [ -n "$SECURITY_GROUP_ID" ]; then
    echo "3. Deleting Security Group: $SECURITY_GROUP_ID..."
    for i in $(seq 1 5); do
        aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" --region "$AWS_REGION" 2>/dev/null && break
        echo "Retrying security group deletion in 5 seconds..."
        sleep 5
    done
    if [ $? -ne 0 ]; then
        echo "Failed to delete security group. You may need to manually delete it in the AWS console."
    else
        echo "Security Group deleted."
    fi
else
    echo "No security group ID found or security group already deleted. Skipping security group deletion."
fi

# Disassociate Route Table from Subnet
if [ -n "$ROUTE_TABLE_ID" ] && [ -n "$SUBNET_ID" ]; then
    ASSOCIATION_ID=$(aws ec2 describe-route-tables \
        --route-table-ids "$ROUTE_TABLE_ID" \
        --query 'RouteTables[0].Associations[?SubnetId==`'"$SUBNET_ID"'`].RouteTableAssociationId' \
        --region "$AWS_REGION" \
        --output text 2>/dev/null)

    if [ -n "$ASSOCIATION_ID" ]; then
        echo "4. Disassociating Route Table: $ROUTE_TABLE_ID from Subnet: $SUBNET_ID..."
        aws ec2 disassociate-route-table --association-id "$ASSOCIATION_ID" --region "$AWS_REGION"
        echo "Route Table disassociated."
    else
        echo "Route Table already disassociated from subnet or association not found."
    fi
else
    echo "No route table or subnet ID found. Skipping route table disassociation."
fi

# Delete Route to Internet Gateway
if [ -n "$ROUTE_TABLE_ID" ]; then
    ROUTE_EXISTS=$(aws ec2 describe-route-tables \
        --route-table-ids "$ROUTE_TABLE_ID" \
        --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0' && GatewayId=='$IGW_ID']" \
        --region "$AWS_REGION" \
        --output text 2>/dev/null)
    if [ -n "$ROUTE_EXISTS" ]; then
        echo "5. Deleting route from Route Table: $ROUTE_TABLE_ID..."
        aws ec2 delete-route \
            --route-table-id "$ROUTE_TABLE_ID" \
            --destination-cidr-block "0.0.0.0/0" \
            --region "$AWS_REGION"
        echo "Route deleted."
    else
        echo "Route to Internet Gateway already deleted or not found. Skipping route deletion."
    fi
else
    echo "No route table ID found. Skipping route deletion."
fi

# Delete Route Table
if [ -n "$ROUTE_TABLE_ID" ]; then
    echo "6. Deleting Route Table: $ROUTE_TABLE_ID..."
    aws ec2 delete-route-table --route-table-id "$ROUTE_TABLE_ID" --region "$AWS_REGION"
    echo "Route Table deleted."
else
    echo "No route table ID found or route table already deleted. Skipping route table deletion."
fi

# Detach Internet Gateway from VPC
if [ -n "$IGW_ID" ] && [ -n "$VPC_ID" ]; then
    echo "7. Detaching Internet Gateway: $IGW_ID from VPC: $VPC_ID..."
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION" 2>/dev/null
    echo "Internet Gateway detached."
else
    echo "No Internet Gateway or VPC ID found or already detached. Skipping Internet Gateway detachment."
fi

# Delete Internet Gateway
if [ -n "$IGW_ID" ]; then
    echo "8. Deleting Internet Gateway: $IGW_ID..."
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
    echo "Internet Gateway deleted."
else
    echo "No Internet Gateway ID found or already deleted. Skipping Internet Gateway deletion."
fi

# Delete Subnet
if [ -n "$SUBNET_ID" ]; then
    echo "9. Deleting Subnet: $SUBNET_ID..."
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$AWS_REGION"
    echo "Subnet deleted."
else
    echo "No subnet ID found or already deleted. Skipping subnet deletion."
fi

# Delete VPC
if [ -n "$VPC_ID" ]; then
    echo "10. Deleting VPC: $VPC_ID..."
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION"
    echo "VPC deleted."
else
    echo "No VPC ID found or already deleted. Skipping VPC deletion."
fi

# Remove saved IDs
echo "11. Removing local resource ID files..."
rm -f .vpc_id .subnet_id .igw_id .route_table_id .security_group_id .instance_id .client1.ovpn
echo "Local resource ID files removed."
echo "Teardown complete!"
