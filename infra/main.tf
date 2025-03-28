# Настройка провайдера
variable "YC_TOKEN" {
  type = string
}

variable "YC_CLOUD_ID" {
  type = string
}

variable "YC_FOLDER_ID" {
  type = string
}

variable "YC_ZONE" {
  type = string
}

variable "KITTYGRAM_USER" {
  type = string
}

variable "KITTYGRAM_SSH" {
  type = string
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }

  required_version = ">= 0.13"

  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }

    bucket = "terraform-state-evgen"
    region = "ru-central1"
    key    = "terraform/tf-state.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = false
  }
}

provider "yandex" {
  token     = var.YC_TOKEN
  cloud_id  = var.YC_CLOUD_ID
  folder_id = var.YC_FOLDER_ID
  zone      = var.YC_ZONE
}

resource "yandex_vpc_security_group" "web_sg" {
  name                = "web-sg"
  network_id          = "${yandex_vpc_network.network-1.id}"

  ingress {
    description       = "Allow SSH"
    protocol          = "TCP"
    port              = 22
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }

  ingress {
    description       = "Allow HTTP"
    protocol          = "TCP"
    port              = 80
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }

  egress {
    description       = "Permit ANY"
    protocol          = "ANY"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    from_port         = 0
    to_port           = 65535
  }
}

# Создание сети
resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "${var.YC_ZONE}"
  v4_cidr_blocks = ["192.168.10.0/24"]
  network_id     = "${yandex_vpc_network.network-1.id}"
}

resource "yandex_compute_instance" "vm" {
  name = "terraform-vm"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8ou6hurlbfqmi57ofd"
    }
  }

  network_interface {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    security_group_ids = [yandex_vpc_security_group.web_sg.id]
    nat       = true
  }

  metadata = {
    serial-port-enable = 1
    user-data = <<-EOF
datasource:
  Ec2:
    strict_id: false
ssh_pwauth: no
users:
  - name: ${var.KITTYGRAM_USER}
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    ssh_authorized_keys:
      - ${var.KITTYGRAM_SSH}
write_files:
  - path: "/usr/local/etc/docker-start.sh"
    permissions: "755"
    content: |
      #!/bin/bash

      # Docker
      echo "Installing Docker"
      sudo apt-get update
      sudo install -m 0755 -d /etc/apt/keyrings
      sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      sudo chmod a+r /etc/apt/keyrings/docker.asc
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

      defer: true
runcmd:
  - [su, ${var.KITTYGRAM_USER}, -c, "/usr/local/etc/docker-start.sh"]
    EOF
  }
}

resource "yandex_storage_bucket" "image_storage" {
  bucket     = "evgen-storage-${var.YC_FOLDER_ID}"
  folder_id = "${var.YC_FOLDER_ID}"
  max_size = 1073741824
}