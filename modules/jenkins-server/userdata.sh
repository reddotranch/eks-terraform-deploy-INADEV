#!/bin/bash
# Install Java
sudo apt-get upgrade -y
sudo apt-get update && apt-get -y install openjdk-17-jdk 
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [trusted=yes] \
  https://pkg.jenkins.io/debian binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install jenkins -y

# Start Jenkins service
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Install Nginx service
sudo apt-get install nginx

# Start Nginx service
sudo systemctl start nginx
sudo systemctl enable nginx
