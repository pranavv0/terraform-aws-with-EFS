provider "aws" {
  region     = "ap-south-1"
  profile    = "ver2"
}






variable "key" {
	default = "webkey"
}

variable "s3OriginId" {
	default = "webS3OriginId"
}
variable "bucketName" {
	default = "webb00"
}






//CREATING KEY
resource "tls_private_key" "webtls" {
  algorithm   = "RSA"
  rsa_bits    = "4096"
}


//KEY IMPORTING
resource "aws_key_pair" "webkey" {
  depends_on=[tls_private_key.webtls]
  key_name   = var.key
  public_key = tls_private_key.webtls.public_key_openssh
}


//SAVING PRIVATE
resource "local_file" "webfile" {
  depends_on = [tls_private_key.webtls]

  content  = tls_private_key.webtls.private_key_pem
  filename = "$(var.key).pem"
  file_permission= 0400
}



//CREATING VPC
resource "aws_vpc" "webvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true
  assign_generated_ipv6_cidr_block = true
  tags = {
    Name = "webvpc"
  }
}


//INTERNET GATEWAY
resource "aws_internet_gateway" "webgw" {
depends_on = [ aws_vpc.webvpc  ]
  vpc_id = aws_vpc.webvpc.id

  tags = {
    Name = "webgw"
  }
}

//ROUTE RULE
resource "aws_route" "webr" {
depends_on = [ aws_vpc.webvpc ,  aws_internet_gateway.webgw ]

  route_table_id            = aws_vpc.webvpc.default_route_table_id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.webgw.id
  }


// ADDING RULE TO SECURITY
resource "aws_default_security_group" "websg1" {
depends_on = [
    aws_vpc.webvpc
  ]
  vpc_id = aws_vpc.webvpc.id

  ingress {
    description = "ssh"
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http"
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
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
    Name = "WebSG"
  }
}


//CREATING SUBNET
resource "aws_subnet" "websub" {

depends_on = [
    aws_vpc.webvpc
  ]

  availability_zone= "ap-south-1b"
  vpc_id     = aws_vpc.webvpc.id
  cidr_block = "10.0.0.0/16"
  map_public_ip_on_launch = true

  tags = {
    Name = "websub"
  }
}


//AMI ID

data "aws_ami" "webami" {
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

 filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
 filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20200408"]
  }
 owners = ["099720109477"]
}

//INSTANCE

resource "aws_instance" "webapp" {
depends_on = [ aws_vpc.webvpc , aws_subnet.websub ]
  ami             = data.aws_ami.webami.id
  instance_type   = "t2.micro"
  key_name        = var.key
  vpc_security_group_ids = ["${aws_vpc.webvpc.default_security_group_id}"]
  subnet_id = aws_subnet.websub.id

  root_block_device {
        volume_type     = "gp2"
        volume_size     = 10
        delete_on_termination   = true
    }
  tags = {
    Name = "WebServer"
  }
}


//connection
resource "null_resource" "rempty"  {

depends_on = [ aws_volume_attachment.webatt ]
  connection {    
      type     = "ssh"    
      user     = "ubuntu"    
      private_key = file("C:/Users/patha/Downloads/ec2.pem")    
      host     = aws_instance.webapp.public_ip  
  }   


   provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install apache2 -y",
      "sudo mkfs.ext4  /dev/xvdh -y",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo systemctl restart apache2",
      "sudo systemctl enable apache2",
      "sudo apt-get install git -y",
      "sudo git clone https://github.com/pranavv0/web.git /var/www/html/"
    ]
 // when    = destroy
 // inline  = [
  //    "sudo umount /var/www/html" 
  //]
  }
}
//EFS
resource "aws_efs_file_system" "webefs" {
    depends_on = [aws_default_security_group.websg1, aws_instance.webapp  ]
    creation_token = “efs”
    tags = {
    Name = “webefs”
    }
}
resource "aws_efs_mount_target" "mount_efs" {
    depends_on = [aws_efs_file_system.webefs]
    file_system_id = aws_efs_file_system.webefs.id
    subnet_id = aws_subnet.websub.id
    security_groups=[aws_default_security_group.websg1.id]
}
resource "null_resource" "cluster" {
    depends_on = [
    aws_efs_file_system.webefs,
    ]
    connection {    
      type     = "ssh"    
      user     = "ubuntu"    
      private_key = file("C:/Users/patha/Downloads/ec2.pem")    
      host     = aws_instance.webapp.public_ip  
  }   

provisioner "remote-exec" {
inline = [“sudo echo ${aws_efs_file_system.webefs.dns_name}:/var/www/html efs defaults._netdev 0 0>>sudo /etc/fstab”,
“sudo mount ${aws_efs_file_system.efs_plus.dns_name}:/var/www/html/”,
“sudo rm -rf /var/www/html/”,
“sudo git clone https://github.com/pranavv0/web.git /var/www/html/“
   ]
  }
}



//S3

resource "aws_s3_bucket" "webb" {
  bucket = var.bucketName
  acl    = "private"

  tags = {
    Name        = "web bucket"
  }

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_object" "webimg" {
  depends_on = [aws_s3_bucket.webb]

  bucket = var.bucketName
  key    = "bholebam.jpg"
  source = "bhole.jpg"
  acl = "private"
  content_type = "image/jpg"
}

data "aws_s3_bucket_object" "webs3data" {
  depends_on = [aws_s3_bucket_object.webimg]
  bucket = var.bucketName
  key    = "bholebam.jpg"
}

resource "aws_s3_bucket_public_access_block" "webs3block" {
  depends_on = [aws_s3_bucket.webb]

  bucket = aws_s3_bucket.webb.id
  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
  ignore_public_acls = true
}



//CLOUDFRONT 

resource "aws_cloudfront_origin_access_identity" "weboai" {
  comment = "Cloudfront OAI"
}

resource "aws_cloudfront_distribution" "webS3Distribution" {
  origin {
    domain_name = aws_s3_bucket.webb.bucket_regional_domain_name
    origin_id   = var.s3OriginId

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.weboai.cloudfront_access_identity_path
    }
  }
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.s3OriginId

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    forwarded_values {
      query_string = false
    
      cookies {
        forward = "none"
      }
    }
  //  path_pattern= "*"
   }
  



price_class = "PriceClass_All"

viewer_certificate {
    cloudfront_default_certificate = true
  }

restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "webApp"


tags = {
    Environment = "WebProduction"
  }
}





//Create and update policy
data "aws_iam_policy_document" "webpolicy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.webb.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.weboai.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.webb.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.weboai.iam_arn}"]
    }
  }
}

# this will update bucket policy for distribution which we created above
resource "aws_s3_bucket_policy" "webupdate" {
  bucket = aws_s3_bucket.webb.id
  policy = data.aws_iam_policy_document.webpolicy.json


connection {    
      type     = "ssh"    
      user     = "ubuntu"    
      private_key = file("C:/Users/patha/Downloads/ec2.pem")
      host     = aws_instance.webapp.public_ip  
  }   

provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
            "echo \"<img src='http://${aws_cloudfront_distribution.webS3Distribution.domain_name}/${aws_s3_bucket_object.webimg.key}'>\" >> /var/www/html/index.html",
            "EOF"
        ]
    }
}


//Global accelarator
resource "aws_globalaccelerator_accelerator" "webgc" {
  name            = "Webaccelerator"
  ip_address_type = "IPV4"
  enabled         = true
}

resource "aws_globalaccelerator_listener" "weblistnr" {
  accelerator_arn = aws_globalaccelerator_accelerator.webgc.id
  client_affinity = "NONE"
  protocol        = "TCP"

  port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_globalaccelerator_endpoint_group" "webendp" {
  listener_arn = aws_globalaccelerator_listener.weblistnr.id
  endpoint_group_region = "ap-south-1"
  traffic_dial_percentage = "100"


  endpoint_configuration {
    endpoint_id = aws_instance.webapp.id
    weight      = 100
  }
}

resource "null_resource" "empty" {
depends_on = [ null_resource.rempty ]
       provisioner "local-exec" {
          command = "start chrome ${aws_instance.webapp.public_ip}"
       }
}
