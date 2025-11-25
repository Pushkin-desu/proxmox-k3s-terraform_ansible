variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "template_vm_id" {
  type        = number
  description = "VMID cloud-init шаблона (например 9000)"
}

variable "datastore" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_gateway" {
  type = string
  description = "Шлюз подсети"
}

variable "ssh_public_key" {
  type        = string
  description = "Полный публичный ключ (ssh-ed25519 AAAA...)"
}

variable "ssh_user" {
  type    = string
  default = "user"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "vlan_id" {
  type    = number
  default = 0
}

variable "cluster_nodes" {
  type = list(object({
    name        = string
    vmid        = number
    target_node = string
    cores       = number
    memory      = number   # MB (4096 = 4GB)
    ip          = string   # CIDR: 192.168.17.60/24
    role        = string   # "master" | "worker"
    datastore   = string   # можно "" чтобы использовать var.datastore
  }))
}