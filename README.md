# portfolio_website
## Introduction
This is my first project that I will be publishing on my Github page. I want to create and configure an EC2 instance on AWS using the AWS CLI. The instance is configured to host a basic Nginx web server and an OpenVPN server. The web server will host my portfolio website and the VPN is for a secure connection for maintenance. With this project I want to showcase proficiency in AWS networking, compute, security, and automation using shell scripting and AWS CLI.

**Technologies Used:**
* **AWS EC2** 
* **AWS VPC** 
* **AWS CLI** 
* **Nginx** 
* **OpenVPN** 
* **Bash Scripting** 
* **Nyr's OpenVPN-install Script**

## Architecture

My project consists of:
* A Virtual Private Cloud with a public subnet.
* An Internet Gateway to allow communication between the VPC and the internet.
* A Route Table to direct internet traffic.
* A Security Group configured to allow:
    * SSH (Port 22) for administration.
    * HTTP (Port 80) and HTTPS (Port 443) for the web server.
    * OpenVPN (Port 1194 UDP) for VPN client connections.
* An EC2 instance launched within the public subnet.
* An Elastic IP associated with the EC2 instance for the VPN.

## Diagram

![portfolio_website drawio](https://github.com/user-attachments/assets/e227fde4-de56-45d4-937d-1f31b301ec62)


## Deployment Steps

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/MalikMamaev95/portfolio_website.git
    cd portfolio_website
    ```

2.  **Configure Variables:**
    Open `instance_setup.sh` and configure the variables based on your needs.

3.  **Execute the Setup Script:**
    ```bash
    chmod +x instance_setup.sh
    ./instance_setup.sh
    ```
    This script will:
    * Create a new SSH key pair (`portfolio-website-key`).
    * Set up the VPC, subnet, internet gateway, and route table.
    * Create and configure a security group.
    * Launch an EC2 instance with `servers_setup.sh` to install Nginx and OpenVPN.
    * Allocate and associate an Elastic IP.
    * Wait for the instance to be running and then SSH into it to generate and download the OpenVPN client configuration (`client.ovpn`).

4.  **The Web Server:**
    Once the `instance_setup.sh` script completes, the test page of the website should be accessible using the EIP. 

5.  **Connect to the VPN Server:**
    * Import the `client.ovpn` file into your OpenVPN client.
    * Connect to the VPN.
    * To check if the VPN works, go to What's My Ip? and check if the IP is 10.8.x.x. This the range the VPN server is configured to use.

6.  **Configure secure SSH:**
    * After downloading the `client.ovpn` file and successfully connecting to the VPN. Change the inboud rule for SSH to only allow traffic from the VPN IP range.
    ```
    aws ec2 revoke-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"
    ```
    ```
    aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 10.8.0.0/24 \
    --region "$AWS_REGION"
    ```

    After this change the only way to SSH into the instance is by using the Private IP.

7. **`remove.sh` Script:**
    This script removes the instance along with all of it's configurations to save on AWS costs. I used this script during development after I made troubleshooting changes to prevent duplicate instances.

## Troubleshooting
During testing I encountered a couple of issues:

1. **AMI Compatibility Error:**
```
Launching EC2 Instance with AMI: ami-00f56fa8642a7e75a, Instance Type: t2.micro...
An error occurred (Unsupported) when calling the RunInstances operation: The requested configuration is currently not supported. Please check the documentation for supported configurations.
Waiting for instance to be in 'running' state
Waiter InstanceRunning failed: An error occurred (MissingParameter): The request must contain the parameter InstanceId
```
This error means my AMI is not compatible with the t2.micro instance type. I changed the instance type to a t3.micro and it fixed the issue.

2. **`servers_setup.sh` Not Executed:**
```
SSH is ready. Copying client1.ovpn from instance...
scp: /tmp/client1.ovpn: No such file or directory
Deployment complete!
Your website should be accessible at: http://13.49.32.178
```
After the `instance_setup` was finished. I noticed that `/tmp/client.ovpn` was not created. I suspected that the `servers_setup.sh` script did not run so I ssh'd into the instance to confirm. I checked the `cloud-init-output.log` and found this line:
```
2025-06-26 07:15:05,709 - handlers[WARNING]: Unhandled non-multipart (text/x-not-multipart) userdata: 'b'# Use bash '...'
```
I added a comment before the `#!/bin/bash` line to explain it and that's why the script did not run. I removed the comment and fixed the issue.

3. **OpenVPN Installer Script Version Mismatch:**
Initially, I attempted to manually configure OpenVPN using Easy-RSA directly within the servers_setup.sh script. This led to complex and persistent issues such as:
```
Illegal option -o echo
ls: cannot access '/etc/openvpn/easy-rsa/pki/index.txt': No such file or directory. 
```
After trying alot of different things without success, I decided to go for a community script (Nyr's openvpn-install.sh) to ensure a reliable VPN deployment. This script, however, required Ubuntu 22.04. The previous t3.micro instance was running Ubuntu 20.04. The solution was to update the AMI in setup.sh to deploy an instance running Ubuntu 22.04. This change allowed Nyr's script to execute successfully.

4. **VPN Client Will Not Connect to Server:**
After completing the installation and setup the VPN client connection timed out. The reason this happend was because the `client.ovpn` file used a temporay public IP because the static EIP was not recognized yet. To fix this I added this block of code:
```
echo "Updating client.ovpn on the instance with Elastic IP: $PUBLIC_IP..."
printf "sudo sed -i \"s/^remote [0-9.]* 1194\$/remote %s 1194/\" /tmp/client.ovpn" "$PUBLIC_IP" | \
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_NAME.pem" ubuntu@"$PUBLIC_IP" "bash" || \
{ echo "ERROR: Failed to update client.ovpn on instance! Check SSH connectivity and file permissions."; exit 1; }
echo "client.ovpn updated on instance."
```
This will SSH to the EC2 instance and change the public IP to the EIP. 

## What I Learned / Demonstrated

* **Infrastructure as Code principles:** Automating infrastructure deployment using shell scripts and AWS CLI commands.
* **AWS Networking:** Creating and configuring VPCs, subnets, internet gateways, route tables.
* **AWS EC2 Management:** Launching, configuring, and managing EC2 instances.
* **Security Group Configuration:** Implementing network security rules.
* **User Data Scripting:** Bootstrapping instances with initial software installations and configurations.
* **Web Server Deployment:** Setting up and basic configuration of Nginx.
* **VPN Server Setup:** Basic deployment of an OpenVPN server for secure access.
* **Troubleshooting:** Identifying and resolving issues during the deployment process.

## Future Enhancements

* ~Design webcontent and add it to the webserver.~
* Implement a CD pipeline to automatically deploy changes to the web server.
* Add monitoring and logging with AWS CloudWatch.
* Integrate a custom domain name for the website.
* Set up HTTPS for the web server using Let's Encrypt.

1. **Adding Webcontent:**
The next step after finishing the infrastructure is adding webcontent to my webserver. For a simple and straightforward setup I have decided to use a Bootstrap template and add it to my `/var/www/html` directory.

To avoid permission issues I first scp'd the template files to the home dir and then cp'd them to html directory.

```
scp -r -i "SSH-KEY" TEMPLATEFILE ubuntu@IP:/home/ubuntu
sudo cp -r TEMPLATEFILE/* /var/www/html
```























