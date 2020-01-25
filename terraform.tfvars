env                 = "k8s"
worker-groups = [
  {
    asg_max_size         = "2"
    asg_min_size         = "1"
    asg_desired_capacity = "2"
    instance_type        = "t3.medium"
    root_volume_size     = "20"
  },
]
