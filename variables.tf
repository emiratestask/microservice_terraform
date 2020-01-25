
# Deploy to us-east-1 region
variable "aws_region" {
  description = "AWS region."
  default     = "us-east-1"
}

# App name
variable "tags" {
  description = "tags to propogate to all supported resources"
  type        = "map"
  default = {
    "Name" = "umsl"
  }
}

# VPC CIDR IP range
variable "vpc_cidr" {
    type    = "string"
    description = "CIDR associated with the VPC to be created"
    default = "10.0.0.0/16"
}

# Deploy VPC resources to two Availability Zones 
variable "az_count" {
  description = "the number of AZs to deploy infrastructure to"
  default     = 2
}

variable "enable_public_subnets" {
  type    = "string"
  default = "true"
}

variable "enable_private_subnets" {
  type    = "string"
  default = "true"
}

# AMI's Ubuntu 18 for Jenkins server - (HVM EBS Backed 64-bit)
variable "aws_amis" {
    default = {
        us-east-1 = "ami-04b9e92b5572fa0d1"
        us-west-1 = "ami-0dd655843c87b6930"
        us-west-2 = "ami-06d51e91cea0dac8d"
    }
}

# Security group information
variable "sg_info" {
    default = {
        jenkins_sg_name = "Jenkins_sg"
        jenkins_sg_description = "EC2 allowed ports, protocols, and IPs for Jenkins"
        https = "443"
        ssh = "22"
        web8080 = "8080"
        zero = "0"
        all = "0.0.0.0/0"
        whitelisted_ssh = "0.0.0.0/0"
        tcp_prot = "tcp"
        udp_prot = "udp"
        both_prot = "-1"
    }
}

# Instance configuration - use (test-ami) key pair created in AWS
variable "instance" {
    default = {
        key_pair = "test-ami"
        ec2_size = "t2.medium"
        ebs_type = "gp2"
        ebs_size = "30"
    }
}

# Local file to load the Jenkins userdata script
variable "files" {
    default = {
        jenkins_master = "./install_jenkins_master.sh"
    }
}

# Jenkins Admin password name to be saved in ssm
variable "ssm_jenkins_admin_password" {
  type        = "string"
  default     = "/secrets/jenkins/admin_password"
  description = "Jenkins Admin password"
}

# SSM parameter type - used for Jenkins password store
variable "ssm_parameter_type" {
  type        = "string"
  default     = "SecureString"
  description = "SSM secure string type"
}

# EKS Cluster naming prefix
variable "naming-prefix" {
  default = "eks"
}

variable "env" {
  default = "k8s"
}

# EKS version
variable "kubernetes-version" {
  description = "Kubernetes Version"
  default     = "1.14"
}

# EKS logs retention
variable "cluster-log-retention" {
  default     = 90
  description = "Number of days to retain log events"
  type        = number
}
# worker groups list
variable "worker-groups" {
  description = "List of maps with worker group configurations. All options documented at https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/local.tf"
  type        = list
}

# IAM roles list
variable "iam_roles" {
  description = "iam roles for cluster access"
  type        = list
  default = [
    "developers",
    "administrators",
  ]
}

# The AMI used for the worker nodes
variable "eks-worker-ami" {
  description = "https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html"
  type    = "string"
  default = "ami-087a82f6b78a07557"
}

# EKS worker nodes instance size
variable "worker-node-instance_type" {
  type    = "string"
  default = "t3.medium"
}
