
# Security Group to allow access to Jenkins server
resource "aws_security_group" "jenkins_security_group" {
    name = "${var.sg_info.jenkins_sg_name}"
    description = "${var.sg_info.jenkins_sg_description}"
    vpc_id = "${aws_vpc.vpc.id}"
    lifecycle { create_before_destroy = true }

    ## Engress

    #HTTPS
     ingress {
        protocol = "${var.sg_info.tcp_prot}"
        from_port = "${var.sg_info.https}"
        to_port = "${var.sg_info.https}"
        cidr_blocks = ["${var.sg_info.all}"]
      }

    #Custom TCP 8080
    ingress {
      protocol = "${var.sg_info.tcp_prot}"
      from_port = "${var.sg_info.web8080}"
      to_port = "${var.sg_info.web8080}"
      cidr_blocks = ["${var.sg_info.all}"]
    }

    #SSH
    ingress {
      protocol = "${var.sg_info.tcp_prot}"
      from_port = "${var.sg_info.ssh}"
      to_port = "${var.sg_info.ssh}"
      cidr_blocks = ["${var.sg_info.whitelisted_ssh}"]
    }

    #Egress
    egress {
      from_port = "${var.sg_info.zero}"
      to_port = "${var.sg_info.zero}"
      protocol = "${var.sg_info.both_prot}"
      cidr_blocks = ["${var.sg_info.all}"]
    }
}

# Create IAM policy and role for Jenkins role to be attached to the ec2 instance
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_policy" "jenkins_policy" {
  name        = "jenkins-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:Describe*",
        "ecr:*",
        "cloudtrail:LookupEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "role-attach" {
  role       = "${aws_iam_role.jenkins_role.name}"
  policy_arn = "${aws_iam_policy.jenkins_policy.arn}"
}


# Create Jenkins Password random string
resource "random_string" "jenkins_pass" {
  length  = 8
  number  = true
  lower   = true
  upper   = true
  special = false
}

# save Jenkins password in SSM parameter store
resource "aws_ssm_parameter" "ssm_jenkins_admin_password" {
  name  = "${var.ssm_jenkins_admin_password}"
  type  = "${var.ssm_parameter_type}"
  value = "${random_string.jenkins_pass.result}"
}


# Install Jenkins server, dependencies, set admin pass and install plugins - using userdata script
resource "template_file" "jenkins_master_user_data" {
  template = "${file("${var.files.jenkins_master}")}"
  lifecycle { create_before_destroy = true }
  vars = {
    admin_username="admin"
    admin_password="${random_string.jenkins_pass.result}"
    aws_region="${var.aws_region}"
  }
}

# IAM Profile creation
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_profile"
  roles = ["${aws_iam_role.jenkins_role.name}"]
  lifecycle { create_before_destroy = true }
}

# create the EC2 instance and attach an EIP to it
resource "aws_eip" "master_eip" {
  instance = "${aws_instance.jenkins_master.id}"
  vpc = true
  lifecycle { create_before_destroy = true }
}

resource "aws_instance" "jenkins_master" {
  ami = "${lookup(var.aws_amis, var.aws_region)}"
  subnet_id = "${aws_subnet.public_subnets[0].id}"
  instance_type = "${var.instance.ec2_size}"
  instance_initiated_shutdown_behavior = "terminate"
  iam_instance_profile = "${aws_iam_instance_profile.jenkins_profile.id}"
  key_name = "${var.instance.key_pair}"
  vpc_security_group_ids = ["${aws_security_group.jenkins_security_group.id}"]
  user_data = "${template_file.jenkins_master_user_data.rendered}"
  root_block_device {
    volume_type = "${var.instance.ebs_type}"
    volume_size = "${var.instance.ebs_size}"
    delete_on_termination = "true"
  }
  lifecycle { create_before_destroy = true }
  tags = {
    Name = "Jenkins-Server"
  }
}