terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.2"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
}

resource "proxmox_virtual_environment_pool" "k3s_pool" {
  pool_id = "k3s"
  comment = "K3s cluster resources"
}

resource "proxmox_virtual_environment_vm" "kvm" {
  for_each = { for n in var.cluster_nodes : n.name => n }

  name      = each.value.name
  vm_id     = each.value.vmid
  node_name = each.value.target_node
  pool_id   = proxmox_virtual_environment_pool.k3s_pool.pool_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = each.value.datastore != "" ? each.value.datastore : var.datastore
    size         = var.disk_size_gb
    interface    = "scsi0"
    file_format  = "raw"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = each.value.datastore != "" ? each.value.datastore : var.datastore
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.network_gateway
      }
    }
    user_account {
      username = var.ssh_user
      keys     = [var.ssh_public_key]
    }
  }
}

output "master_ips" {
  value = [
    for n in var.cluster_nodes : replace(n.ip, "/24", "") if n.role == "master"
  ]
}

output "worker_ips" {
  value = [
    for n in var.cluster_nodes : replace(n.ip, "/24", "") if n.role == "worker"
  ]
}

output "nodes_with_roles" {
  value = {
    for n in var.cluster_nodes :
    n.name => {
      ip   = replace(n.ip, "/24", "")
      role = n.role
      vmid = n.vmid
      node = n.target_node
      ds   = n.datastore != "" ? n.datastore : var.datastore
    }
  }
}