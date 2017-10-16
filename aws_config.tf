
variable "region" {}
variable "shared_credentials_file" {}
variable "profile" {}
variable "role_arn" {}
variable "session_name" {}
variable "keypair" {}

variable "azs" {
  description = "Run the EC2 Instances in these Availability Zones"
  type = "list"
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "private_ips" {
  description = "Private IPs to be assigned"
  type = "list"
  default = ["172.16.10.100","172.16.10.101","172.16.10.102" ]
}

variable "vpc_cidr" {
    desription = "CIDR for the whole VPC"
    default = "${var.vpc_cidr}"
}

variable "public_subnet_cidr" {
    description = "CIDR for the Public Subnet"
    default = "${var.public_subnet_cidr}"
}

variable "private_subnet_cidr" {
    description = "CIDR for the Private Subnet"
    default = "${var.private_subnet_cidr}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  ########################################################################################
  # https://askubuntu.com/questions/53582/how-do-i-know-what-ubuntu-ami-to-launch-on-ec2 #  
  ########################################################################################
  owners = ["099720109477"] # Canonical
}

provider "aws" {
  region                  = "${var.region}"
  shared_credentials_file = "${var.shared_credentials_file}"
  profile                 = "${var.profile}"
  assume_role {
    role_arn     = "${var.role_arn}"
    session_name = "${var.session_name}"
  }
}

resource "aws_vpc" "Prometheus_Stack_VPC" {
  enable_dns_hostnames = true
  cidr_block = "${var.vpc_cidr}"
  tags {
    Name = "Prometheus-stack-vpc"
  }
}

resource "aws_internet_gateway" "Prometheus_Stack_gateway" {
    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"
}

/*
  NAT Instance
*/
resource "aws_security_group" "nat" {
    name = "vpc_nat"
    description = "Allow traffic to pass from the private subnet to the internet"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}"]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}"]
    }
    #ssh access
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    /* send to only VPC CIDR */ 
    egress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }
    egress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"

    tags {
        Name = "Security_Group_NAT"
    }
}

resource "aws_instance" "nat" {
    ami = "ami-30913f47" # this is a special ami preconfigured to do NAT
    availability_zone = "eu-west-1a"
    instance_type = "t2.micro"
    #key_name = "${var.aws_key_name}"
    vpc_security_group_ids = ["${aws_security_group.nat.id}"]
    subnet_id = "${aws_subnet.Prometheus_public_subnet.id}"
    associate_public_ip_address = true
    source_dest_check = false
    tags {
        Name = "VPC NAT"
    }
}

resource "aws_eip" "nat" {
    instance = "${aws_instance.nat.id}"
    vpc = true
}


/* Public Subnet */

resource "aws_subnet" "Prometheus_public_subnet" {
    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"
    cidr_block = "${var.public_subnet_cidr}"
    availability_zone = "us-east-2b"
    tags {
        Name = "Prometheus stack public subnet"
    }
}

resource "aws_route_table" "Prometheus_public_route_table" {
    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.Prometheus_Stack_gateway.id}"
    }
    tags {
        Name = "Prometheus stack public subnet's internet gateway"
    }
}

resource "aws_route_table_association" "Prometheus_public_route_stable_association" {
    subnet_id = "${aws_subnet.Prometheus_public_subnet.id}"
    route_table_id = "${aws_route_table.Prometheus_public_route_table.id}"
}


/*  Private Subnet */

resource "aws_subnet" "Prometheus_private_subnet" {
    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"
    cidr_block = "${var.private_subnet_cidr}"
    availability_zone = "us-east-2a"
    tags {
        Name = "Prometheus stack private subnet"
    }
}

resource "aws_route_table" "Prometheus_private_route_table" {
    vpc_id = "${aws_vpc.Prometheus_Stack_VPC.id}"
    route {
        cidr_block = "0.0.0.0/0"
        instance_id = "${aws_instance.nat.id}"
    }
    tags {
        Name = "Private Subnet"
    }
}

resource "aws_route_table_association" "Prometheus_private_route_stable_association" {
    subnet_id = "${aws_subnet.Prometheus_private_subnet.id}"
    route_table_id = "${aws_route_table.Prometheus_private_route_table.id}"
}

resource "aws_instance" "bastion" {
  subnet_id     = "${aws_subnet.Prometheus_private_subnet.id}"
  ami           = "${data.aws_ami.ubuntu.id}"
  key_name      = "${var.keypair}"
  instance_type = "t2.micro"
  associate_public_ip_address = "true"
  tags {
    Name = "Prometheus-stack-bastion"
  }
}

/*
resource "aws_network_interface" "Prometheus_Stack_Network_Interface" {
  subnet_id = "${aws_subnet.Prometheus_Stack_Subnet.id}"
  description = "Description for the network interface"
  #private_ips =  "${element(var.private_ips, count.index)}"
  #private_ips_count = 3
  tags {
    Name = "Prometheus-stack-network-interface"
  }
}
*/

resource "aws_instance" "prometheus" {
  subnet_id     = "${aws_subnet.Prometheus_public_subnet.id}"
  ami           = "${data.aws_ami.ubuntu.id}"
  key_name      = "${var.keypair}"
  instance_type = "t2.micro"
  count        = 3
  availability_zone  = "${element(var.azs, count.index)}"
  tags {
    Name = "Prometheus-stack-instance-${count.index}"
  }
}
