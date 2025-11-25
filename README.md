# HOMELab K3s Mini Cluster in Proxmox: Terraform + Ansible Deploy

## Требования
- Proxmox VE 8 и выше
- Linux host с ansible, terraform, git, ssh (LXC, VM или baremetal)
- Свободный диапазон адресов для VM
- API Token на Proxmox с PVEAdmin или custom ролями
- SSH-ключ

---

## Примечание
В каталоге ansible есть плейбуки snapshot-create.yml и snapshot-rollback.yml

Они предназначены для массового создания Снапшотов и возращения к ним. Дабы вы всегда могли откатиться к предыдущему шагу.

Использование:
```bash
ansible-playbook -i ansible/hosts ansible/snapshot-create.yml -e snapshot_name=<Имя_снапшота>

ansible-playbook -i ansible/hosts ansible/snapshot-rollback.yml -e snapshot_name=<Имя_снапшота>
```

Также есть плейбуки для запуска всех ВМ кластера и остановки, а также получение статуса ВМ.
Использовал для интеграции с ТГ ботом (управление кластером с любого устройства)
```bash
ansible-playbook -i ansible/hosts ansible/cluster-start.yml

ansible-playbook -i ansible/hosts ansible/cluster-stop.yml

ansible-playbook -i ansible/hosts ansible/cluster-status.yml
```

---
## Шаг 1. Как получить API токен для Proxmox

1. **Зайдите в Proxmox Web UI** под root правами.
2. Перейдите в раздел `Datacenter` -> `Permissions` -> `API Tokens`.
3. Нажмите `Add`:
   - **User:** выберите существующего пользователя (например, `root@pam` или выделенного `terraform@pam`).  
   - **Token ID:** укажите любое короткое имя (например, `terraform`).  
   - **Privilege separation:** ОТМЕНЯТЬ НЕ НУЖНО.
   - **Permissions:** Минимум роль PVEAdmin на целевые ноды или пул, или точечно на API-операции для infra.
4. Сохраните TOKEN ID и SECRET (SECRET увидите однократно).
5. В дальнейшем:
   - `proxmox_api_token_id` = user@pam!tokenid  (например `root@pam!terraform`)
   - `proxmox_api_token_secret` = ваш secret

---

## Промежуточный этап
Разворачивать ПО будем с linux машины, в моём случае был LXC Debian 12.

1) Проверьте наличие у вас SSH ключа, без него не будет доступа к образу
Для генерации ключа выполните:
```bash
ssh-keygen
```
В консоли будет путь к приватному и публичному ключу, запомните путь к приватной части, а также скопируйте содержимое pub файла, например 
```bash
cat /root/.ssh/id_ed25519.pub
```
2) Установите Terraform 
```bash
apt update 

apt install -y gpg curl wget software-properties-common lsb_release

wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

apt update

apt install -y terraform
```
3) Установите Ansible
```bash
apt -y install ansible-core
```

4) Скопируйте репозиторий 
```bash
cd /opt

git clone https://github.com/Pushkin-desu/proxmox-k3s-terraform_ansible.git

cd proxmox-k3s-terraform_ansible

```

## Шаг 2. Как создать cloud‑init шаблон (Ubuntu образ)

Выполняется на нужном Proxmox узле (pve1, pve2...)
Хранилище указано local-lvm, сеть vmbr0. Измените на свои значения.

```bash
# 1. Установите утилиту для работы с img образами
apt-get update
apt-get install libguestfs-tools -y

# 2. Скачайте cloud образ
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img

# 3. Добавим Guest агент, можно добавить своё ПО
virt-customize -a focal-server-cloudimg-amd64.img --install qemu-guest-agent

# 4. Создайте новую VM (например vmid 9000)
qm create 9000 --name ubuntu-cloud-init-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# 5. Переименуем образ
mv focal-server-cloudimg-amd64.img focal-server-cloudimg-amd64.qcow2

# 6. Импортируйте диск
qm importdisk 9000 focal-server-cloudimg-amd64.qcow2 local-lvm

# 7. Назначьте диск VM
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# 8. Добавьте cloud-init drive
qm set 9000 --ide2 local-lvm:cloudinit

# 9. Укажите порядок загрузки и диск
qm set 9000 --boot c --bootdisk scsi0

# 10. Настраиваем VM
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent 1

# 11. Перейдите в настройки Шаблона VM.
# а) Проверьте вкладку Hardware, верно ли указаны настройки ЦП, ОЗУ, Сети
# б) На вкладке cloud-init укажите Имя пользователя и SSH Public Key, обязательно

# 12. Преобразуем в Шаблон
qm template 9000

```

> Если хотите развернуть на двух нодах Proxmox — шаги надо повторить для каждого узла, либо используйте общий storage, чтобы шаблон был доступен в обеих нодах.

---
## Дальнейшие шаги выполняются снова на Linux машине (LXC Debian 13)

## Шаг 3. Подготовка переменных


## .env
Сформируйте файл .env и заполните его вашими данными
```bash
cp .env.example .env

nano .env
```

## После настройки .env обязательно выполните 
```bash
source .env
```
Иначе система не подхватит переменные

## terraform.tfvars
Пример файла `terraform.tfvars`:

```hcl
# Шаблон
template_vm_id           = 9000    # номер вашего cloud-init шаблона

# Сеть
network_bridge  = "vmbr0"
network_gateway = "192.168.1.1"

# Ваш публичный ключ
ssh_public_key = "ssh-ed25519 AAAAC3... user@host"
ssh_user = "user"

datastore      = "local-lvm"
disk_size_gb   = 30

# Описание VM (можно разнести на разные узлы)
cluster_nodes = [
  {
    name        = "k3s-master-1"
    vmid        = 4010
    target_node = "pve"
    cores       = 2
    memory      = 4096
    ip          = "192.168.1.60/24"
    role        = "master"
    datastore   = "" 
  },
  {
    name        = "k3s-master-2"
    vmid        = 4011
    target_node = "pve"
    cores       = 2
    memory      = 4096
    ip          = "192.168.1.61/24"
    role        = "master"
    datastore   = "" 
  },
  {
    name        = "k3s-worker-1"
    vmid        = 4020
    target_node = "pve"
    cores       = 2
    memory      = 4096
    ip          = "192.168.1.62/24"
    role        = "worker"
    datastore   = "" 
  },
  {
    name        = "k3s-worker-2"
    vmid        = 4021
    target_node = "pve"
    cores       = 2
    memory      = 4096
    ip          = "192.168.1.63/24"
    role        = "worker"
    datastore   = "" 
  },
  {
    name        = "k3s-worker-3"
    vmid        = 4022
    target_node = "pve"
    cores       = 2
    memory      = 4096
    ip          = "192.168.1.64/24"
    role        = "worker"
    datastore   = "" 
  }
]
```

> **ВАЖНО:** `cluster_nodes` — структура таблицей! Убедитесь, что каждый IP свободен, vmid уникален, нода (`target_node`) — верное название вашей ноды Proxmox.

---

## Шаг 4. Как запустить Terraform

1. Перейдите в папку `terraform/`
```bash
cd terraform
```
2. Инициализация:
```bash
terraform init
```
3. Проверьте план:
```bash
terraform plan
```

Убедитесь, что все VM правильно распределяются и нет ошибок по шаблону, network, datastore.
4. Применить:
```bash
terraform apply
```
Дождитесь вывода об успешном создании, получите список VM, их IP и роли.

--

## Шаг 5. Настройка Ansible и развертывание k3s

В репозитории лежит файл gen_ansible_hosts.py, он сгенерирует файлы ansible/hosts и ansible/group_vars/all.yml. А также каталог ansible/host_vars Версия K3S жёстко указана.

1. Запустите gen_ansible_hosts.py, укажите имя пользователя ВМ и путь к приватной части SSH ключа.
```bash
cd ..

python3 gen_ansible_hosts.py
```

2. Проверьте сгенерированные файлы

3. Создайте минимальный Ansible config
```bash
nano ansible.cfg
```

```
[defaults]
inventory = hosts
host_key_checking = False
stdout_callback = yaml

[ssh_connection]
pipelining = True
```

4. Запустите плейбук
```bash
ansible-playbook -i ansible/hosts ansible/install-k3s.yml
```
---

## Шаг 6. Проверка статуса кластера
Необходим kubectl
```bash
cd ..

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

```bash
export KUBECONFIG=./kubeconfig-master.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

---

## FAQ и типичные ошибки

- **Terraform не может клонировать шаблон:** Проверьте, что VM-шаблон (9000) есть на целевом узле и storage (см. “Как создать cloud-init образ”).
- **SSH не подключается:** Проверьте публичный ключ (ssh_public_key), права пользователя, статус VM в Proxmox.
- **Ansible жалуется на known_hosts:** удалите запись (`ssh-keygen -R IP`) и пересоздайте (`ssh-keyscan IP >> ~/.ssh/known_hosts`).
- **kubectl не находит nodes:** Проверьте, что k3s агент запущен, и все VM видят корректный master IP.

---

## TODO

- Протестировать пайплайн push→build→deploy (Jenkins/GitHub Actions).
- Миграция на GitOps (ArgoCD) и хранение helm values в отдельном репозитории.
- Пример секции secrets‑management.