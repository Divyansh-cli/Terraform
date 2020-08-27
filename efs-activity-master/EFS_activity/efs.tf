provider "aws" {
  region = "ap-south-1"
  profile = "mycred"
}

resource "aws_vpc" "myvpc" {
  cidr_block = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  
  tags = {
    Name = "tera-vpc"
   }    
}

resource "aws_subnet" "subnet1" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id = aws_vpc.myvpc.id
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
   Name = "public-subnet"
   }
}

resource "aws_internet_gateway" "gw" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "tera-gw"
  }
}

resource "aws_route_table" "rt" {
  depends_on = [ aws_internet_gateway.gw ]

  vpc_id = aws_vpc.myvpc.id
  
   route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
   }

     tags = {
    Name = "at_routetable"
  } 
}
resource "aws_route_table_association" "rta" {
  depends_on = [ aws_route_table.rt ]  

  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "mypublicsg" {
  name = "allow_nfs"
  vpc_id = aws_vpc.myvpc.id
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "mypublic_sg"
  }
}

resource "aws_efs_file_system" "myefsvol" {
  creation_token = "my_product"
  encrypted = true
  tags = {
    Name = "MY-EFS"
  }
}

resource "aws_efs_file_system_policy" "efs_policy" {
  
  depends_on = [ aws_efs_file_system.myefsvol ]
  
 file_system_id = aws_efs_file_system.myefsvol.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "efs-storage-read-write-permission-Policy01",
    "Statement": [
        {
            "Sid": "efs-statement-permission01",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Resource": "${aws_efs_file_system.myefsvol.arn}",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:ClientRootAccess"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
POLICY
}



resource "aws_efs_mount_target" "efsmount" {

  depends_on = [
     aws_route_table_association.rta, aws_security_group.mypublicsg, aws_efs_file_system.myefsvol
  ]
  
  file_system_id = aws_efs_file_system.myefsvol.id
  subnet_id      = aws_subnet.subnet1.id
  security_groups = [ aws_security_group.mypublicsg.id ]
}

resource "aws_instance" "myos" {


    depends_on=[ aws_security_group.mypublicsg ]

    ami= "ami-0732b62d310b80e97"
    instance_type= "t2.micro"
    key_name= "mykey12"
    subnet_id= aws_subnet.subnet1.id
    vpc_security_group_ids = [ aws_security_group.mypublicsg.id ]
    
    connection{
        type= "ssh"
        user= "ec2-user"
        private_key= file("C:/Users/Akash/Downloads/mykey12.pem")
        host= aws_instance.myos.public_ip
    }

  provisioner "remote-exec" {
        inline=["sudo yum install httpd git php amazon-efs-utils nfs-utils -y",
                "sudo systemctl restart httpd",
                "sudo systemctl enable httpd"]
    }
tags = {
      Name = "mypublicos"
  }
}

 resource "null_resource" "efs_attach" {
       depends_on = [ aws_efs_mount_target.efsmount ]
       connection{
        type= "ssh"
        user= "ec2-user"
        private_key= file("C:/Users/Akash/Downloads/mykey12.pem")
        host= aws_instance.myos.public_ip
    }
   provisioner "remote-exec"{        
            inline=[  "sudo yum install git httpd php nfs-utils -y",
                      "sudo systemctl restart httpd",
                      "sudo systemctl enable httpd",
                      "sudo mount ${aws_efs_file_system.myefsvol.dns_name}:/ /var/www/html/",
                      "sudo git clone https://github.com/Akash-droid24/efs-activity.git /var/www/html/"]
    }
}

resource "aws_s3_bucket" "s3buckettask1" {
bucket = "akash7023"
acl    = "public-read"


provisioner "local-exec" {
     command = "git clone https://github.com/Akash-droid24/efs-activity.git myimage"
      }
}

resource "aws_s3_bucket_object" "s3_object" {
  bucket = aws_s3_bucket.s3buckettask1.bucket
  key    = "d3.jpg"
  source = "myimage/d3.jpg"
  acl    = "public-read"
 depends_on = [
      aws_s3_bucket.s3buckettask1
  ]

}

locals {
  s3_origin_id = "S3-${aws_s3_bucket.s3buckettask1.bucket}"
      }





resource "aws_cloudfront_distribution" "mycloudfrontaccess" {
  
    depends_on = [
    aws_s3_bucket_object.s3_object,
  ]    

    origin {
    domain_name = "${aws_s3_bucket.s3buckettask1.bucket_regional_domain_name}"
    origin_id   = "locals.s3_origin_id"
      }
 

 enabled = true
 is_ipv6_enabled = true
 comment = "s3bucket-access"

 default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "locals.s3_origin_id"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

     viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress = true
    }
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = "locals.s3_origin_id"
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
   restrictions {
      geo_restriction {
          restriction_type = "none"
     }
   }
  tags = {
  Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "accessurl"  {
depends_on = [
    aws_cloudfront_distribution.mycloudfrontaccess,
  ]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Akash/Downloads/mykey12.pem")
    host     = aws_instance.myos.public_ip
  }
  provisioner "remote-exec" {
    inline = [
  "echo '<img src='https://${aws_cloudfront_distribution.mycloudfrontaccess.domain_name}/${aws_s3_bucket_object.s3_object.key}' width='300' height='330'>' sudo tee -a /var/www/html/teralab.html"
    ]
  }
} 

resource "null_resource" "websitedeployment"  {
depends_on = [
     null_resource.efs_attach, null_resource.accessurl
  ]

  provisioner "local-exec" {
      command = "start chrome  ${aws_instance.myos.public_ip}/teralab.html"
    }
}

resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.myos.public_ip} > PublicIp.txt"
  	}
}



