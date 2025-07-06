For external availability - use the following CloudFormation template:

```
AWSTemplateFormatVersion: 2010-09-09
Resources:
  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: TailnetProxySecurityGroup
      GroupDescription: Tailnet Proxy Security Group
      SecurityGroupEgress:
        - CidrIp: 0.0.0.0/0
          FromPort: 443
          ToPort: 443
          IpProtocol: -1
        - CidrIp: 0.0.0.0/0
          FromPort: 80
          ToPort: 80
          IpProtocol: -1
      SecurityGroupIngress:
        - CidrIp: 0.0.0.0/0
          FromPort: 22
          ToPort: 22
          IpProtocol: -1
      VpcId: vpc-952036f0
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateName: TailnetLaunchTemplate
      LaunchTemplateData:
        UserData:
          Fn::Base64: |
            #!/bin/bash

            # https://docs.docker.com/engine/install/ubuntu/
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update

            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            cat <<EOF | sudo docker compose -f - up -d
            services:
              app:
                image: 'jc21/nginx-proxy-manager:latest'
                restart: unless-stopped
                ports:
                  - "80:80"
                  - "81:81"
                  - "443:443"
                volumes:
                  - data:/data
                  - letsencrypt:/etc/letsencrypt

            volumes:
              data:
              letsencrypt:
            EOF


            curl -fsSL https://tailscale.com/install.sh | sh
            # Manual setup:
            # * Access `<public>:81`, log in with `admin@example.com // changeme` - prompted to create new account
            # * Create "New Proxy Host" from Domain Name to jellyfin.avril
            # * Set DNS to forward jellyfin.scubbo.org -> <public IP>
            # * `sudo tailscale up` and follow the resultant URL to connect to the TailNet
            #
            # TODO - provide a secret in an AWS Secret so `sudo tailscale up` can be autonomous (then don't need to open port 81)
  JellyfinProxyInstance:
    Type: AWS::EC2::Instance
    DependsOn: "LaunchTemplate"
    Properties:
      # ImageId: ami-00beae93a2d981137
      ImageId: ami-04b4f1a9cf54c11d0
      InstanceType: t2.micro
      LaunchTemplate:
        LaunchTemplateName: TailnetLaunchTemplate
        Version: "1"
      NetworkInterfaces:
        - AssociatePublicIpAddress: "true"
          DeviceIndex: "0"
          GroupSet:
            - Ref: "SecurityGroup"
          SubnetId: "subnet-535f3d78"
```