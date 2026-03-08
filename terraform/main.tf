# --- Frontend Infrastructure (S3 + CloudFront) ---

# S3 bucket for frontend hosting
# resource "aws_s3_bucket" "frontend" {
#   bucket = "${var.project_name}-frontend-${var.environment}"
# }

# CloudFront distribution
# resource "aws_cloudfront_distribution" "s3_distribution" {
#   # ... configuration for CloudFront ...
# }


# --- Backend Infrastructure (EC2) ---

# VPC and Networking (optional but recommended)
# module "vpc" {
#   source = "terraform-aws-modules/vpc/aws"
#   # ...
# }

# EC2 instance for backend
# resource "aws_instance" "backend" {
#   ami           = "ami-xxxxxx" # Replace with valid AMI ID
#   instance_type = "t3.micro"
#
#   tags = {
#     Name = "${var.project_name}-backend"
#   }
# }


# --- Database (RDS - if you move away from Docker-local DB) ---
# resource "aws_db_instance" "postgres" {
#   # ...
# }
