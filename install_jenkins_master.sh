#!/bin/bash

# Get the admin password from SSM parameters store and it will passeda s variable during the creation of the Terraform
admin_username="admin"
admin_password="${admin_password}"

set -x

# Install all required server dependencies needed by Jenkins and by the pipeline like kubectl, helm, docker, nodejs ...etc
function install_dependencies ()
{
  apt -y update && \
  apt install -y python3-pip xmlstarlet python python-pip && \
  apt install -y awscli && \
  apt -y update && \
  apt install -y docker.io && \
  sudo curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
  sudo chmod +x /usr/local/bin/docker-compose && \
  pip3 install --upgrade --user awscli && export PATH=/home/ubuntu/.local/bin:$PATH && \
  sudo apt install -y openjdk-8-jdk && \
  curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
  chmod +x ./kubectl && \
  sudo mv ./kubectl /usr/local/bin/kubectl && \
  curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator && \
  chmod +x ./aws-iam-authenticator && \
  mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH=$PATH:$HOME/bin && \
  echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc && \
  wget https://get.helm.sh/helm-v3.0.2-linux-amd64.tar.gz && \
  tar -zxvf helm-v3.0.2-linux-amd64.tar.gz && \
  mv linux-amd64/helm /usr/local/bin/helm && \
  apt-get install -y build-essential libtool autotools-dev automake autoconf pkg-config libssl-dev && \
  apt-get install -y software-properties-common && \
  apt-get -y update && \
  apt-get install -y nodejs npm && \
  sleep 10
}


# Install Jenkins server
function install_packages ()
{
  wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add - && \
  sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list' && \
  sudo apt -y update && \
  sudo apt install -y jenkins && \
  sudo systemctl start jenkins && \
  sudo ufw allow 8080 && \
  service jenkins start
  sleep 10
}


# Wait until Jenkins is up and running
function wait_for_jenkins()
{
  while (( 1 )); do
      echo "waiting for Jenkins to launch on port [8080] ..."
      
      nc -zv 127.0.0.1 8080
      if (( $? == 0 )); then
          break
      fi

      sleep 10
  done

  echo "Jenkins launched"
}


# Update the deafault Jenikns password with the one created by TF and storedin AWS SSM parameter store
function updating_jenkins_master_password ()
{

  # Wait till /var/lib/jenkins/users/admin* folder gets created
  sleep 10

  cd /var/lib/jenkins/users/admin*
  pwd
  while (( 1 )); do
      echo "Waiting for Jenkins to generate admin user's config file ..."

      if [[ -f "./config.xml" ]]; then
          break
      fi

      sleep 10
  done

  echo "Admin config file created"

  echo -n $admin_password'{admin}' | sha256sum > master_pass
  sed -i 's/  -//g' master_pass
  admin_pass=$(<master_pass)
  xmlstarlet -q ed --inplace -u "/user/properties/hudson.security.HudsonPrivateSecurityRealm_-Details/passwordHash" -v 'admin:'"$admin_pass" config.xml
  service jenkins restart
  sleep 10

}


# Configure Jenkins and install a full list of all needed plugins to run the pipeline, like git, github, ecr, kubernetes, docker ...etc
function configure_jenkins_server ()
{
  # Jenkins cli
  echo "installing the Jenkins cli ..."
  cp /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar /var/lib/jenkins/jenkins-cli.jar

  PASSWORD="${admin_password}"
  sleep 10

  jenkins_dir="/var/lib/jenkins"
  plugins_dir="$jenkins_dir/plugins"

  cd $jenkins_dir

  # Open JNLP port
  xmlstarlet -q ed --inplace -u "/hudson/slaveAgentPort" -v 33453 config.xml

  cd $plugins_dir || { echo "unable to chdir to [$plugins_dir]"; exit 1; }

  # List of plugins that are needed to be installed 
  plugin_list="git-client git amazon-ecr github-api kubernetes-cli kubernetes-credentials-provider kubernetes-client-api kubernetes-credentials docker-custom-build-environment kubernetes docker-plugin docker-java-api docker-compose-build-step github-oauth github MSBuild ssh-slaves workflow-aggregator ws-cleanup generic-webhook-trigger"

  # remove existing plugins, if any ... docker-java-api docker-compose-build-step 
  rm -rfv $plugin_list

  for plugin in $plugin_list; do
      echo "installing plugin [$plugin] ..."
      java -jar $jenkins_dir/jenkins-cli.jar -s http://127.0.0.1:8080/ -auth admin:$PASSWORD install-plugin $plugin
  done

  # Restart jenkins after installing plugins
  java -jar $jenkins_dir/jenkins-cli.jar -s http://127.0.0.1:8080 -auth admin:$PASSWORD safe-restart
}


# Add jenkins user to docker group so that sudo isn't required and Fix docker daemon issue
function post_install_fixes ()
{
gpasswd -a jenkins docker

usermod -a -G docker jenkins
chown jenkins:docker /var/run/docker.sock

}


# -- start the script steps in the below sequence --#

install_dependencies

install_packages

wait_for_jenkins

updating_jenkins_master_password

wait_for_jenkins

configure_jenkins_server

post_install_fixes

echo "Done"
exit 0
