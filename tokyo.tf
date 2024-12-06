variable "vpc_availability_zone_tokyo" {
  type        = list(string)
  description = "Availability zone"
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}
################################
// vpc
################################
resource "aws_vpc" "tokyo" {
    cidr_block = "10.230.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true
    provider  = aws.tokyo
    tags = {
        Name = "Tokyo VPC"
    }
}
################################
// subnets
################################
resource "aws_subnet" "public_subnet_tokyo" {
  vpc_id            = aws_vpc.tokyo.id
  count             = length(var.vpc_availability_zone_tokyo)
  cidr_block        = cidrsubnet(aws_vpc.tokyo.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_tokyo, count.index)
  provider  = aws.tokyo
  tags = {
    Name = "Tokyo Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_tokyo" {
  vpc_id            = aws_vpc.tokyo.id
  count             = length(var.vpc_availability_zone_tokyo)
  cidr_block        = cidrsubnet(aws_vpc.tokyo.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_tokyo, count.index)
  provider  = aws.tokyo
  tags = {
    Name = "Tokyo Private Subnet${count.index + 1}",
  }
}

################################
//3. Create internet gateway and attach it to the vpc
################################
resource "aws_internet_gateway" "internet_gateway_tokyo" {
  vpc_id = aws_vpc.tokyo.id
  provider  = aws.tokyo
  tags = {
    Name = "tokyo Internet Gateway",
  }
}
################################
//4. RT for the public subnet
################################
resource "aws_route_table" "tokyo_route_table_public_subnet" {
  vpc_id = aws_vpc.tokyo.id
  provider  = aws.tokyo

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway_tokyo.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}
################################
//5. Association between RT and IG
################################
resource "aws_route_table_association" "public_subnet_association_tokyo" {
  route_table_id = aws_route_table.tokyo_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_tokyo))
  subnet_id      = element(aws_subnet.public_subnet_tokyo[*].id, count.index)
  provider  = aws.tokyo
}

################################
//6. EIP
################################
resource "aws_eip" "tokyo_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
  provider  = aws.tokyo
}

################################
//7. Nat Gateway
################################
resource "aws_nat_gateway" "tokyo_nat_gateway" {
  subnet_id     = element(aws_subnet.private_subnet_tokyo[*].id, 0)
  allocation_id = aws_eip.tokyo_eip.id
  depends_on    = [aws_internet_gateway.internet_gateway]
  provider  = aws.tokyo
  tags = {
    Name = "tokyo NAT Gateway",
  }
}

################################
//8. RT for private Subnet
################################
resource "aws_route_table" "tokyo_route_table_private_subnet" {
  vpc_id = aws_vpc.tokyo.id
  provider  = aws.tokyo

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.tokyo_nat_gateway.id
  }
  route {
    cidr_block = "10.231.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.peer.id
  } 

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

################################
//9. RT Association Private
################################
resource "aws_route_table_association" "tokyo_private_subnet_association" {
  route_table_id = aws_route_table.tokyo_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_tokyo))
  subnet_id      = element(aws_subnet.private_subnet_tokyo[*].id, count.index)
  provider  = aws.tokyo
}

################################
//10. Security Groups
################################
resource "aws_security_group" "tokyo_alb_sg" {
  name        = "tokyo-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider = aws.tokyo

  vpc_id = aws_vpc.tokyo.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "tokyo-alb-sg"
  }
}


//2. Security Group For EC2

resource "aws_security_group" "tokyo_ec2_sg" {
  name        = "tokyo-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider = aws.tokyo

  vpc_id = aws_vpc.tokyo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.tokyo_alb_sg.id]

  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tokyo-ec2-sg"
  }
}

################################
//11. Application Loadbalancer
################################
// Create The Application Load Balancer
resource "aws_lb" "tokyo_app_lb" {
  name               = "tokyo-app-lb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.tokyo_alb_sg.id]
  subnets            = aws_subnet.public_subnet_tokyo[*].id
  depends_on         = [aws_internet_gateway.internet_gateway]
  provider = aws.tokyo
}

################################
//12. Target Group
################################
// Create A Target Group
resource "aws_lb_target_group" "tokyo_alb_ec2_tg" {
  name     = "tokyo-web-server-tg"
  port     = 80
  protocol = "HTTP"
  #target_type = "instance"
  vpc_id = aws_vpc.tokyo.id
  provider = aws.tokyo
  tags = {
    Name = "tokyo_alb_ec2_tg"

  }

}

################################
//13. Listeners
################################
// alb listener
resource "aws_lb_listener" "tokyo_alb_listener" {
  load_balancer_arn = aws_lb.tokyo_app_lb.arn
  port              = 80
  protocol          = "HTTP"
  provider = aws.tokyo

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tokyo_alb_ec2_tg.arn
  }
  tags = {
    Name = "tokyo-alb-listener"
  }
}

################################
//14. Launch Template
################################
// Launch template for ec2 instance
resource "aws_launch_template" "tokyo_ec2_launch_template" {
  name          = "tokyo-ec2-launch-template"
  image_id      = "ami-023ff3d4ab11b2525"
  instance_type = "t2.micro"
  provider = aws.tokyo

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.tokyo_ec2_sg.id]
  }

  user_data = filebase64("userdata.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "tokyo-ec2-web-server"
    }
  }
}

################################
//15. Auto Scaling Group
################################
// Create Auto Scaling Group
resource "aws_autoscaling_group" "tokyo_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "tokyo-web-server-asg"
  target_group_arns   = [aws_lb_target_group.tokyo_alb_ec2_tg.arn]
  vpc_zone_identifier = aws_subnet.private_subnet_tokyo[*].id
  provider = aws.tokyo

  launch_template {
    id      = aws_launch_template.tokyo_ec2_launch_template.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}

