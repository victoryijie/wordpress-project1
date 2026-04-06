

# Security group for EC2
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow HTTP, SSH, and DB access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Security group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Allow MySQL access from EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # security_groups = [aws_security_group.rds_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ec2_to_rds" {
  type                     = "ingress"                           # Inbound traffic
  from_port                = 3306                                # RDS default port (MySQL example)
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id        # Target SG (RDS)
  source_security_group_id = aws_security_group.ec2_sg.id        # Source SG (EC2)
  description              = "Allow EC2 SG to access RDS SG"
}



# EC2 Instance
resource "aws_instance" "app" {
  ami           = "ami-083d8a6500c1d55d6" # Amazon Linux 2
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.ec2_sg.id]
  key_name      = "ansible" # replace with your key

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install docker -y
              service docker start
              usermod -a -G docker ec2-user

              # Run Nginx container
              docker run -d -p 80:80 --name nginx nginx

              # Run WordPress container and link to MySQL
              docker run -e WORDPRESS_DB_HOST=${aws_db_instance.wp_db.address} \
                         -e WORDPRESS_DB_USER=${aws_db_instance.wp_db.username} \
                         -e WORDPRESS_DB_PASSWORD=${aws_db_instance.wp_db.password} \
                         -e WORDPRESS_DB_NAME=${aws_db_instance.wp_db.db_name} \
                         -p 8080:80 --name wordpress wordpress
              EOF

  tags = {
    Name = "WordPressApp"
  }
}

# RDS Subnet group (private subnet)
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# RDS MySQL
resource "aws_db_instance" "wp_db" {
  identifier              = "wordpress-db"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  db_name                  = "wordpress"
  username                = "admin"
  password                = "Admin12345!" # use secure method in prod
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  publicly_accessible     = false
}