terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Variables

# Data disk configuration
variable "data_disk_count" {
  description = "Number of data disks to create"
  type        = number
  default     = 4
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Subnet 1
resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/22"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-1"
  }
}

resource "aws_route_table_association" "subnet1_assoc" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.public_rt.id
}

# Subnet 2
resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/22"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-2"
  }
}

# Subnet 3
resource "aws_subnet" "subnet3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.8.0/22"
  availability_zone       = "us-east-2c"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-3"
  }
}

# RHEL Security Group
resource "aws_security_group" "rhel_sg" {
  name        = "rhel-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rhel-sg"
  }
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat official AWS account

  filter {
    name   = "name"
    values = ["RHEL-9.*-x86_64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

variable "key_name" {
  description = "Name of existing AWS EC2 key pair"
  type        = string
  default     = "epicadmin" # CHANGE THIS to your key pair name in AWS
}

resource "aws_instance" "rhel_vm" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet1.id
  vpc_security_group_ids      = [aws_security_group.rhel_sg.id]
  associate_public_ip_address = true #set to false to disable 
  key_name                    = var.key_name
  #iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name

  # Root volume (OS disk)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 128 # GB - adjust as needed
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "epic-emr-root"
    }
  }

  tags = {
    Name = "rhel9-odb-test"
  }
  user_data = file("./cloud-init/bash_config.sh")
}

# Additional EBS volumes for RHEL VM components
# Volume 1 - Epic instnace
resource "aws_ebs_volume" "epic_disk_1" {
  availability_zone = aws_instance.rhel_vm.availability_zone
  size              = 250
  type              = "gp3"
  encrypted         = true
  lifecycle {
    ignore_changes = [ all ]
    prevent_destroy = false
  }

  tags = {
    Name        = "epic-emr-inst-disk"
    Environment = "test"
  }
}

resource "aws_volume_attachment" "epic_attach_1" {
  device_name = "/dev/sdc"
  volume_id   = aws_ebs_volume.epic_disk_1.id
  instance_id = aws_instance.rhel_vm.id
}

# Volume 2 - Epic Jornal Disk 
resource "aws_ebs_volume" "epic_disk_2" {
  availability_zone = aws_instance.rhel_vm.availability_zone
  size              = 300
  type              = "gp3"
  encrypted         = true
  lifecycle {
    ignore_changes = [ all ]
    prevent_destroy = false
  }

  tags = {
    Name        = "epic-emr-jrn-disk"
    Environment = "test"
  }
}

resource "aws_volume_attachment" "epic_attach_2" {
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.epic_disk_2.id
  instance_id = aws_instance.rhel_vm.id
  depends_on = [ aws_volume_attachment.epic_attach_1 ]
}

# Striped disks for datasets
resource "aws_ebs_volume" "striped_disk" {
  count = var.data_disk_count
  availability_zone = aws_instance.rhel_vm.availability_zone
  size = 100
  type =  "gp3"
  encrypted = true
  lifecycle {
    ignore_changes = [ all ]
    prevent_destroy = false
  }

  tags = {
    Name = "epic-data-disk-${count.index + 1}"
  }
}

# Attach data disks using count
resource "aws_volume_attachment" "striped_disk_attach" {
  count = var.data_disk_count

  device_name = "/dev/sd${element(split("", "efghijklmnopqrstuvwxyz"), count.index)}"
  volume_id = aws_ebs_volume.striped_disk[count.index].id
  instance_id = aws_instance.rhel_vm.id

  depends_on = [ 
    aws_volume_attachment.epic_attach_1,
    aws_volume_attachment.epic_attach_2
   ]
}

# Outputs
output "instance_id" {
  description = "ID of the RHEL VM instance"
  value       = aws_instance.rhel_vm.id
}

output "instance_public_ip" {
  description = "Public IP of the RHEL VM instance"
  value       = aws_instance.rhel_vm.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the RHEL VM instance"
  value       = aws_instance.rhel_vm.private_ip
}

output "rhel9_ami_id" {
  description = "AMI ID used for RHEL 9"
  value       = data.aws_ami.rhel9.id
}

output "volume_ids" {
  description = "IDs of all attached volumes"
  value = {
    disk_1  = aws_ebs_volume.epic_disk_1.id
    disk_2  = aws_ebs_volume.epic_disk_2.id
  }
}

output "data_volume_ids" {
  description = "List of all data volume IDs"
  value       = aws_ebs_volume.striped_disk[*].id
}
