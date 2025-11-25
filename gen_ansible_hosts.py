#!/usr/bin/env python3
import subprocess
import json
import os

def ssh_update_known_hosts(ip):
    print(f"updating known_hosts for {ip} ...")
    subprocess.run(["ssh-keygen", "-R", ip], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        keyscan = subprocess.check_output(["ssh-keyscan", "-T", "5", ip], stderr=subprocess.DEVNULL)
        with open(os.path.expanduser("~/.ssh/known_hosts"), "a") as kh:
            kh.write(keyscan.decode())
        print(f"added host key для {ip}")
    except Exception as e:
        print(f"error for {ip}: {e}")

user = input("Введите ansible_user [user]: ") or "user"
keyfile = input("Введите путь до ansible_ssh_private_key_file [/root/.ssh/id_rsa]: ") or "/root/.ssh/id_rsa"

tf_json = subprocess.check_output(["terraform", "-chdir=terraform", "output", "-json", "nodes_with_roles"])
nodes = json.loads(tf_json)

masters = []
workers = []
for name, meta in nodes.items():
    if meta["role"] == "master":
        masters.append(meta["ip"])
    elif meta["role"] == "worker":
        workers.append(meta["ip"])

if not masters:
    raise SystemExit("no one Master in terraform output nodes_with_roles.")

master_ip = masters[0]

print("\n--- Updating known_hosts ---")
for ip in masters + workers:
    ssh_update_known_hosts(ip)

os.makedirs("ansible", exist_ok=True)
hosts_content = [
    "[k3s_masters]",
    *masters,
    "",
    "[k3s_workers]",
    *workers,
    "",
    "[all:vars]",
    "ansible_python_interpreter=/usr/bin/python3",
    f"ansible_user={user}",
    f"ansible_ssh_private_key_file={keyfile}"
]

with open("ansible/hosts", "w") as f:
    f.write("\n".join(hosts_content) + "\n")

print("ansible/hosts created:")
print(open("ansible/hosts").read())

gv_path = "ansible/group_vars"
os.makedirs(gv_path, exist_ok=True)
all_yml = f'''k3s_version: "v1.31.6+k3s1"
k3s_master_ip: "{master_ip}"
k3s_tls_sans:
  - "{{{{ k3s_master_ip }}}}"
k3s_server_args:
  - "--disable traefik"
  - "--write-kubeconfig-mode 644"
  - "--tls-san {{{{ k3s_master_ip }}}}"
  - "--node-ip {{{{ ansible_host | default(k3s_master_ip) }}}}"
k3s_agent_args: []
'''
with open(os.path.join(gv_path, "all.yml"), "w") as f:
    f.write(all_yml)

print("ansible/group_vars/all.yml created:")
print(open(os.path.join(gv_path, "all.yml")).read())