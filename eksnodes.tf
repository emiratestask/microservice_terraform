
# Create the security groups needed for the EKS nodes to manage the cluster access
resource "aws_security_group" "eks-node" {
  name        = "eks-worker-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "eks-worker-node-sg",
     "kubernetes.io/cluster/${var.naming-prefix}-umsl", "owned"
    )
  }"
}

resource "aws_security_group_rule" "eks-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.eks-node.id}"
  source_security_group_id = "${aws_security_group.eks-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks-node.id}"
  source_security_group_id = "${aws_security_group.eks-cluster.id}"
  to_port                  = 65535
  type                     = "ingress"
}

# HPA requires 443 to be open for k8s control plane.
resource "aws_security_group_rule" "eks-node-ingress-hpa" {
  description              = "Allow HPA to receive communication from the cluster control plane"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks-node.id}"
  source_security_group_id = "${aws_security_group.eks-cluster.id}"
  to_port                  = 443
  type                     = "ingress"
}

# bootstrap script that bootstraps the worker nodes when they are launched to register Amazon EKS cluster
locals {
  eks-node-private-userdata = <<USERDATA
#!/bin/bash -xe

sudo /etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.eks-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.eks-cluster.certificate_authority.0.data}' '${var.naming-prefix}-umsl'

USERDATA
}

# The launch configuration and the Auto-Scaling Group to startup the instances and scale up/down the nodes
resource "aws_launch_configuration" "eks-private-lc" {
  iam_instance_profile        = "${aws_iam_instance_profile.eks-node.name}"
  image_id                    = "${var.eks-worker-ami}"
  instance_type               = "${var.worker-node-instance_type}"
  key_name                    = "${var.instance.key_pair}"
  name_prefix                 = "eks-private"
  security_groups             = ["${aws_security_group.eks-node.id}"]
  user_data_base64            = "${base64encode(local.eks-node-private-userdata)}"
  
  root_block_device {
    delete_on_termination = true
    volume_size = 30
    volume_type = "gp2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks-private-asg" {
  desired_capacity     = 1
  launch_configuration = "${aws_launch_configuration.eks-private-lc.id}"
  max_size             = 2
  min_size             = 1
  name                 = "eks-private"
  vpc_zone_identifier  = ["${aws_subnet.public_subnets[0].id}", "${aws_subnet.private_subnets[1].id}"]

  tag {
    key                 = "Name"
    value               = "eks-worker-private-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.naming-prefix}-umsl"
    value               = "owned"
    propagate_at_launch = true
  }
}

# Define the ASG policy
resource "aws_autoscaling_policy" "eks-cpu-policy-private" {
  name = "eks-cpu-policy-private"
  autoscaling_group_name = "${aws_autoscaling_group.eks-private-asg.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = "1"
  cooldown = "300"
  policy_type = "SimpleScaling"
}

# scaling up cloudwatch metric
resource "aws_cloudwatch_metric_alarm" "eks-cpu-alarm-private" {
  alarm_name = "eks-cpu-alarm-private"
  alarm_description = "eks-cpu-alarm-private"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "80"
  actions_enabled = "true"
  alarm_actions = ["${aws_autoscaling_policy.eks-cpu-policy-private.arn}"]
}

# scale down policy
resource "aws_autoscaling_policy" "eks-cpu-policy-scaledown-private" {
  name = "eks-cpu-policy-scaledown-private"
  autoscaling_group_name = "${aws_autoscaling_group.eks-private-asg.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = "-1"
  cooldown = "300"
  policy_type = "SimpleScaling"
}

# scale down cloudwatch metric
resource "aws_cloudwatch_metric_alarm" "eks-cpu-alarm-scaledown-private" {
  alarm_name = "eks-cpu-alarm-scaledown-private"
  alarm_description = "eks-cpu-alarm-scaledown-private"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "5"
  actions_enabled = "true"
  alarm_actions = ["${aws_autoscaling_policy.eks-cpu-policy-scaledown-private.arn}"]
}
