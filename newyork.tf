variable "vpc_availability_zone_new_york" {
  type        = list(string)
  description = "Availability zone"
  default     = ["us-east-1a", "us-east-1c"]
}
variable "region" {
  default = ["new_york"]
}

variable "hub_regions" {
  default = "tokyo"
}
################################
// vpc
################################
resource "aws_vpc" "new_york" {
    cidr_block = "10.231.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true
    provider  = aws.new_york
    tags = {
        Name = "New York VPC"
    }
}
################################
// subnets
################################
resource "aws_subnet" "public_subnet_new_york" {
  vpc_id            = aws_vpc.new_york.id
  count             = length(var.vpc_availability_zone_new_york)
  cidr_block        = cidrsubnet(aws_vpc.new_york.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_new_york, count.index)
  provider  = aws.new_york
  tags = {
    Name = "New York Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_new_york" {
  vpc_id            = aws_vpc.new_york.id
  count             = length(var.vpc_availability_zone_new_york)
  cidr_block        = cidrsubnet(aws_vpc.new_york.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_new_york, count.index)
  provider  = aws.new_york
  tags = {
    Name = "New York Private Subnet${count.index + 1}",
  }
}

################################
//3. Create internet gateway and attach it to the vpc
################################
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.new_york.id
  provider  = aws.new_york
  tags = {
    Name = "new_york Internet Gateway",
  }
}
################################
//4. RT for the public subnet
################################
resource "aws_route_table" "new_york_route_table_public_subnet" {
  vpc_id = aws_vpc.new_york.id
  provider  = aws.new_york

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}
################################
//5. Association between RT and IG
################################
resource "aws_route_table_association" "public_subnet_association" {
  route_table_id = aws_route_table.new_york_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_new_york))
  subnet_id      = element(aws_subnet.public_subnet_new_york[*].id, count.index)
  provider  = aws.new_york
}

################################
//6. EIP
################################
resource "aws_eip" "new_york_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
  provider  = aws.new_york
}

################################
//7. Nat Gateway
################################
resource "aws_nat_gateway" "new_york_nat_gateway" {
  subnet_id     = element(aws_subnet.private_subnet_new_york[*].id, 0)
  allocation_id = aws_eip.new_york_eip.id
  depends_on    = [aws_internet_gateway.internet_gateway]
  provider  = aws.new_york
  tags = {
    Name = "new_york NAT Gateway",
  }
}

################################
//8. RT for private Subnet
################################
resource "aws_route_table" "new_york_route_table_private_subnet" {
   # for_each = toset(var.regions)
  vpc_id = aws_vpc.new_york.id
  provider  = aws.new_york

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.new_york_nat_gateway.id
  }
  route {
    cidr_block = "10.230.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local.id
  } 

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

################################
//9. RT Association Private
################################
resource "aws_route_table_association" "new_york_private_subnet_association" {
  route_table_id = aws_route_table.new_york_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_new_york))
  subnet_id      = element(aws_subnet.private_subnet_new_york[*].id, count.index)
  provider  = aws.new_york
}

################################
//10. Security Groups
################################
resource "aws_security_group" "new_york_alb_sg" {
  name        = "new_york-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider = aws.new_york

  vpc_id = aws_vpc.new_york.id

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
    Name = "new_york-alb-sg"
  }
}


//2. Security Group For EC2

resource "aws_security_group" "new_york_ec2_sg" {
  name        = "new_york-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider = aws.new_york

  vpc_id = aws_vpc.new_york.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.new_york_alb_sg.id]

  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "new_york-ec2-sg"
  }
}

################################
//11. Application Loadbalancer
################################
// Create The Application Load Balancer
resource "aws_lb" "new_york_app_lb" {
  name               = "new-york-app-lb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.new_york_alb_sg.id]
  subnets            = aws_subnet.public_subnet_new_york[*].id
  depends_on         = [aws_internet_gateway.internet_gateway]
  provider = aws.new_york
}

################################
//12. Target Group
################################
// Create A Target Group
resource "aws_lb_target_group" "new_york_alb_ec2_tg" {
  name     = "new-york-web-server-tg"
  port     = 80
  protocol = "HTTP"
  #target_type = "instance"
  vpc_id = aws_vpc.new_york.id
  provider = aws.new_york
  tags = {
    Name = "new-york-alb-ec2-tg"

  }

}

################################
//13. Listeners
################################
// alb listener
resource "aws_lb_listener" "new_york_alb_listener" {
  load_balancer_arn = aws_lb.new_york_app_lb.arn
  port              = 80
  protocol          = "HTTP"
  provider = aws.new_york

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.new_york_alb_ec2_tg.arn
  }
  tags = {
    Name = "new-york-alb-listener"
  }
}

################################
//14. Launch Template
################################
// Launch template for ec2 instance
resource "aws_launch_template" "new_york_ec2_launch_template" {
  name          = "new_york-ec2-launch-template"
  image_id      = "ami-0453ec754f44f9a4a"
  instance_type = "t2.micro"
  provider = aws.new_york

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.new_york_ec2_sg.id]
  }

  user_data = filebase64("userdata.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "new_york-ec2-web-server"
    }
  }
}

################################
//15. Auto Scaling Group
################################
// Create Auto Scaling Group
resource "aws_autoscaling_group" "new_york_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "new_york-web-server-asg"
  target_group_arns   = [aws_lb_target_group.new_york_alb_ec2_tg.arn]
  vpc_zone_identifier = aws_subnet.private_subnet_new_york[*].id
  provider = aws.new_york

  launch_template {
    id      = aws_launch_template.new_york_ec2_launch_template.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}

