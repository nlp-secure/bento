#!/bin/bash

set -e
set -x

echo "Starting pre-install step"

# Currently things just fall apart due to the IP address switch between build
# and vagrant usage...  So using a secondary IP eases the pain for the moment.
ifconfig eth0:0 172.20.254.2 netmask 255.255.255.0 up

time (
  # Important for syncing DB backups/etc
  timedatectl set-timezone America/Denver

  rpm -q epel-release || yum -y install epel-release
  rpm -q ius-release || yum -y install https://centos7.iuscommunity.org/ius-release.rpm

  yum clean all

  yum -y update

  yum -y install rsync git2u-all
  yum -y install python-chardet python-kitchen libxml2-python yum-utils epel-release-7 ius-release-2 apr apr-util perl-Error perl-Data-Dumper perl-TermReadKey git2u-core perl-Digest perl-Digest-MD5 cvs fontpackages-filesystem dejavu-fonts-common dejavu-sans-fonts fontconfig cvsps perl-Digest-SHA perl-Digest-HMAC git2u-core-doc git2u-subtree perl-YAML perl-GSSAPI perl-Authen-SASL perl-Net-LibIDN libX11-common libXau libxcb libX11 libXrender libXft perl-Mozilla-CA-20130114 pakchois perl-Net-SSLeay perl-IO-Socket-IP perl-IO-Socket-SSL perl-Net-SMTP-SSL libmodman libproxy perl-Compress-Raw-Zlib gpm-libs libsecret git2u-perl-Git git2u git2u-email git2u-p4 liblockfile perl-Net-Daemon alsa-lib perl-Compress-Raw-Bzip2 perl-IO-Compress perl-PlRPC perl-DBI perl-DBD-SQLite git2u-cvs emacs-filesystem emacs-common nettle tcl tk git2u-gitk git2u-gui trousers gnutls neon subversion-libs subversion subversion-perl git2u-perl-Git-SVN git2u-svn emacs-nox emacs-git2u git2u-all rsync python-backports python-ipaddress python-backports-ssl_match_hostname python-setuptools python2-pip socat unzip ipvsadm container-selinux containerd.io docker-ce-cli docker-ce

  echo '*  hard  core  0' > /etc/security/limits.conf
  echo 'fs.suid_dumpable = 0' > /etc/sysctl.conf
  sysctl -p

  [ -d kubespray ] || git clone https://github.com/kubernetes-sigs/kubespray.git
  cd kubespray
  git checkout v2.12.0
  git reset --hard HEAD
  rpm -q python-pip || yum -y install python-pip
  pip install --upgrade pip
  pip install -r requirements.txt

  echo "Date: "
  date +%s

  export GROUP_VARS_ALL_PATH="./inventory/sample/group_vars/all"
  export DOCKER_PATH="$GROUP_VARS_ALL_PATH/docker.yml"
  export GROUP_VARS_ALL="$GROUP_VARS_ALL_PATH/all.yml"
  export K8S_CLUSTER_PATH="./inventory/sample/group_vars/k8s-cluster/k8s-cluster.yml"

  grep '0.0.0.0:2376' "$DOCKER_PATH" || (
    sed -i'' -e 's|docker_options: >-|docker_options: >-\n  -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --experimental=true|g' "$DOCKER_PATH"
  )

  sed -i'' -e 's|.?.?.?kubeconfig_localhost: .*|kubeconfig_localhost: true|g' $K8S_CLUSTER_PATH
  sed -i'' -e 's|kube_apiserver_ip: .*|kube_apiserver_ip: 172.20.254.2|g' $K8S_CLUSTER_PATH
  sed -i'' -e 's|kube_api_pwd: .*|kube_api_pwd: test123|g' $K8S_CLUSTER_PATH
  sed -i'' -e '/.*delegate_to:/d' roles/download/tasks/download_container.yml
  sed -i'' -e '/.*delegate_facts:/d' roles/download/tasks/download_container.yml

  cat <<-'THE_END' > inventory/sample/inventory.ini
node1 ansible_connection=local ip=172.20.254.2 local_release_dir={{ansible_env.HOME}}/releases

[kube-master]
node1

[etcd]
node1

[kube-node]
node1

[k8s-cluster:children]
kube-master
kube-node

THE_END

  export HOSTS_LINE='172.20.254.2 node1 node1.local node1.localdomain node1.localdomain6'

  grep "$HOSTS_LINE" /etc/hosts || (
    echo >> /etc/hosts
    echo "$HOSTS_LINE" >> /etc/hosts
    echo >> /etc/hosts
  )

  rm -rf inventory/local
  cp -a inventory/sample inventory/local
)

cd kubespray

echo -ne "\n\n\nNext: Ansible playbook for installation"

# -vvvv for debugging
# ansible-playbook -vvvv -i inventory/local/inventory.ini cluster.yml
time ansible-playbook -i inventory/local/inventory.ini cluster.yml

usermod -G docker vagrant

echo -ne "\n\n\nNext: Ansible playbook for cleanup/packaging"
time ansible-playbook -i inventory/local/inventory.ini remove-node.yml --extra-vars "node=node1 delete_nodes_confirmation=yes"

systemctl daemon-reload
