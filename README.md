# portfolio_website
## Introduction
This is my first project that I will be publishing on my Github page. I want to create and run a website using AWS and use it as my portfolio. With this project I want to display basic cloud hosting skills like: Content Delivery Network Integration using AWS Cloudfront, DNS configuration, VPN configuration and IAM.

## 1. Setting up EC2 Instance
I have decided to launch an Ubuntu instance that will function as my VPN and webserver. I have configured SSH keys and this is how my security group is configured:

![image](https://github.com/user-attachments/assets/2b1f8f2a-a381-4f4d-86bf-9681697cf49b)

I have opened HTTPS 443 port for all public traffic to my website. Port 1194 also allows all inboud traffic. This is necessary otherwise my client would not be able to connect to the server. Port 22 is open only temporarily untill I have configured the VPN. 

## 2. Setting up VPN Server
For this project I will be using OpenVPN as my VPN Server. Before I start installing, I need to configure an Elastic IP on my instance. This will make the setup of the VPN server easier. 

![image](https://github.com/user-attachments/assets/60ffcf14-f99d-4130-b64f-be34e9027d28)

I will use Nyr's OpenVPN install script: 
```
wget https://git.io/vpn -O openvpn-install.sh
sudo bash openvpn-install.sh
```
The configuration:

![image](https://github.com/user-attachments/assets/9adf751e-b626-4486-a13a-fc7bf8c85f92)

I proceeded to download the client configuration file to my local directory using scp.

```
scp -i Ubuntu_InstanceKey.pem ubuntu@13.51.179.18:/home/ubuntu/user_malik.ovpn C:\Users\malik\OneDrive\Desktop\Sleutels\
```
I then installed the OpenVPN GUI client and imported the configuration file. To test if the VPN works, I went to the website What's My IP?. If the VPN works the IP shown should be the Elastic IP we configured earlier for our VPN server.

![image](https://github.com/user-attachments/assets/6ab9be3b-e60f-4c07-8e45-6ca1d318d53e)

Now that the VPN works I need to change the security group rules for port 22. For extra security I only want to be able to connect through SSH while I'm connected with the VPN. To configure this I need to configure port 22 to only allow traffic from the IP range that OpenVPN has configured for me. 

First I need to find the IP range. This can be found in the server.conf file.

```
vim /etc/openvpn/server/server.conf
```
![image](https://github.com/user-attachments/assets/299b89f6-5fa2-45f3-9097-12402cd3131a)

Then I changed the inboud rules:

![image](https://github.com/user-attachments/assets/eab69379-b80f-45d9-ac78-f172f716f3bb)










