#!/usr/bin/env bash

set -eou pipefail

sudo apt-get install software-properties-common
sudo apt-add-repository -y ppa:ansible/ansible
sudo apt-get update
sudo apt-get install -y ansible
sudo apt-get install -y git
sudo apt-get install -y tree

echo Clone terraform repository
git clone git@github.com:Miyurz/terraform-infra.git
