#Configure Providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {
    name = "us-east-1"
}

data "aws_caller_identity" "current" {}

#Local Variaables

locals {
  GITHUB_REPO="https://github.com/ihsanerturk/swarm-phonebook.git"
  GITHUB_URL="https://raw.githubusercontent.com/ihsanerturk/swarm-phonebook/main/"
}

#Docker Swarm Instances
resource "aws_instance" "instance-leader-manager" {
  ami           = var.amazon-linux-2
  instance_type = var.instance-type
  key_name = var.my-key
  vpc_security_group_ids = [ aws_security_group.swarm-sec-grp.id ]
  user_data = data.template_file.leader-userdata.rendered
  iam_instance_profile = aws_iam_instance_profile.swarm-profile.name
  root_block_device {
    volume_size = 16
  }

  tags = {
    Name = "Swarm-Leader-Manager"
  }
}

resource "aws_instance" "instance-manager" {
  ami           = var.amazon-linux-2
  instance_type = var.instance-type
  key_name = var.my-key
  count = 2
  vpc_security_group_ids = [ aws_security_group.swarm-sec-grp.id ]
  user_data = data.template_file.manager-userdata.rendered
  iam_instance_profile = aws_iam_instance_profile.swarm-profile.name
  root_block_device {
    volume_size = 16
  }

  tags = {
    Name = "Swarm-Manager-${count.index + 1}"
  }
}

resource "aws_instance" "instance-worker" {
  ami           = var.amazon-linux-2
  instance_type = var.instance-type
  key_name = var.my-key
  count = 2
  vpc_security_group_ids = [ aws_security_group.swarm-sec-grp.id ]
  user_data = data.template_file.worker-userdata.rendered
  iam_instance_profile = aws_iam_instance_profile.swarm-profile.name
  root_block_device {
    volume_size = 16
  }

  tags = {
    Name = "Swarm-Worker-${count.index + 1}"
  }
}


#Security Group
resource "aws_security_group" "swarm-sec-grp" {
  name        = "docker-swarm-sec-grp-p204"

  dynamic "ingress" {
    for_each = var.tcp-ports
    iterator = port
    content {
        from_port        = port.value
        to_port          = port.value
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port        = 7946
    to_port          = 7946
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 4789
    to_port          = 4789
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

}

#IAM Role
resource "aws_iam_role" "swarm-role" {
  name = "swarm-role-project-204"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [ "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess" ]
  inline_policy {
    name = "mssh_inline_policy"

    policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "ec2-instance-connect:SendSSHPublicKey",
        "Resource": [
            "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:instance/*"
        ],
        "Condition": {
            "StringEquals": {
                "ec2:osuser": "ec2-user"
            }
        }
      },
      {
        "Effect": "Allow",
        "Action": "ec2:DescribeInstances",
        "Resource": "*"
      }
    ]
})
  }
}

resource "aws_iam_instance_profile" "swarm-profile" {
  name = "swarm-profile-project-204"
  role = aws_iam_role.swarm-role.name
}

#ECR Repository
resource "aws_ecr_repository" "ecr-repo" {
  name                 = "clarusway/swarm-phonebook-p204"
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

#User Data
data "template_file" "leader-userdata" {
  template = <<EOF
    #! /bin/bash
    yum update -y
    hostnamectl set-hostname Leader-Manager
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -sL "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    docker swarm init
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.ecr-repo.repository_url}
    docker service create \
    --name=viz \
    --publish=8080:8080/tcp \
    --constraint=node.role==manager \
    --mount=type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    dockersamples/visualizer
    yum install -y git
    docker build --force-rm -t "${aws_ecr_repository.ecr-repo.repository_url}:latest" ${local.GITHUB_REPO}#main
    docker push ${aws_ecr_repository.ecr-repo.repository_url}:latest
    mkdir -p /home/ec2-user/swarm-phonebook
    cd /home/ec2-user/swarm-phonebook 
    curl -o docker-compose.yml -L ${local.GITHUB_URL}docker-compose.yml
    curl -o init.sql -L ${local.GITHUB_URL}init.sql
    export ECR_REPO=${aws_ecr_repository.ecr-repo.repository_url}
    envsubst < docker-compose.yml > docker-compose.yaml
    docker stack deploy --with-registry-auth -c ./docker-compose.yaml swarm-phonebook
  EOF

}

data "template_file" "manager-userdata" {
  template = <<EOF
    #! /bin/bash
    yum update -y
    hostnamectl set-hostname Manager
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -sL "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    yum install python3 -y
    amazon-linux-extras install epel -y
    yum install python-pip -y
    pip3 install ec2instanceconnectcli
    aws ec2 wait instance-status-ok --instance-ids ${aws_instance.instance-leader-manager.id}
    eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
    --region ${data.aws_region.current.name} ${aws_instance.instance-leader-manager.id} docker swarm join-token manager | grep -i 'docker')"
  EOF

}

data "template_file" "worker-userdata" {
  template = <<EOF
   #! /bin/bash
    yum update -y
    hostnamectl set-hostname Worker
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -sL "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    yum install python3 -y
    amazon-linux-extras install epel -y
    yum install python-pip -y
    pip3 install ec2instanceconnectcli
    aws ec2 wait instance-status-ok --instance-ids ${aws_instance.instance-leader-manager.id}
    eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
    --region ${data.aws_region.current.name} ${aws_instance.instance-leader-manager.id} docker swarm join-token worker | grep -i 'docker')"
  EOF

}