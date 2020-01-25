# Deployment steps

### The templates description:
•	provider.tf it has the main provider (AWS), and also the backend definition as S3 to save the terraform state into an S3 bucket. Also, it has a definition of a DynamoDB table to lock the state for the current user.
•	vpc.tf defines all the network resources such as the VPC, subnets, internet gateway, security groups, and NACL.
•	iam.tf has the IAM policies and roles needed for the right access for the Jenkins server and EKS cluster internally and externally, allowing only needed access for all.
•	ekscluster.tf define the resources needed to create a new EKS cluster including the IAM role and security group.
•	nodescluster.tf define the resources needed to create the worker nodes, such as the launch configuration, the Auto scaling group, IAM and SG.
•	jenkins.tf create the ec2 instance and install Jenkins server using a userdata script described below. It also generates a password and save it in AWS SSM parameter store and it’s passed to the script as an environment variable with the terraform apply script. 
•	install_jenkins_master.sh a user data script that do all the of the work needed to make Jenkins ready for deployment, it’s executing the below steps in order:

        •	install all required server dependencies needed by Jenkins and by the pipeline like kubectl, aws-authenticator, helm, docker ...etc.
        •	install Jenkins server
        •	Wait until Jenkins is up and running
        •	update the default Jenkins password with the one created by TF and stored in AWS SSM parameter store
        •	onfigure Jenkins and install a full list of all needed plugins to run the pipeline, like Git, GitHub, ecr, kubernetes, docker ...etc.
        •	Add Jenkins user to docker group so that sudo isn't required and Fix docker daemon issue.
•	variable.tf has all the variables needed for the provisioning such as: CIDR range, EKS version, AMIs, instances size and type…etc. 
•	output.tf contains the most important output values that are needed to access the cluster from the account created the terraform template, or even from other system; which are: The Kubeconfig and the Cluster ConfigMap AWS Auth.


# The deployment steps: 
•	Initialize Terraform:
  ```sh
  terraform init
```  
•	Create an execution plan and double check what will be provisioned:
  ```sh
  terraform plan
```  
•	Apply the templates to AWS:
  ```sh
  terraform apply
```  



## To access the cluster from the local machine that installed the templates and join the nodes to the cluster:
•	Setup Kubeconfig:

  ```sh
terraform output kubeconfig > ~/.kube/eks-cluster
export KUBECONFIG=~/.kube/eks-cluster
aws eks --region us-east-1 update-kubeconfig --name eks-umsl
```
•	Double check the cluster access using any kubectl command:
  ```sh
  kubectl get svc
```  
•	Once cluster is verified successfully, we have to create a configMap to add the worker nodes into the cluster:
  ```sh
  terraform output config-map-aws-auth > config-map-aws-auth.yaml
```  
•	Apply the ConfigMap aws auth YMAL file:
  ```sh
  Kubectl apply -f config-map-aws-auth.yaml
```  

•	Watch the worker nodes while joining the cluster:
  ```sh
  kubectl get no –w
```  

