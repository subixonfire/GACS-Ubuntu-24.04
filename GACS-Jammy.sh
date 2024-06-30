#!/bin/bash

# Cek apakah user memiliki akses root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Anda harus menjalankan script ini sebagai root."
    exit 1
fi

# Cek distribusi dan versi Ubuntu
if ! lsb_release -d | grep -q "Ubuntu 22.04"; then
    echo "Error: Script ini hanya mendukung Ubuntu 22.04 Jammy."
    exit 1
fi

# Menjalankan perintah dengan output informatif dan loading animation
function run_command {
    echo -n "$(tput bold)$1...$(tput sgr0)"
    ($2) &> /dev/null &
    pid=$!
    delay=0.75
    spin='-\|/'
    i=0
    while kill -0 $pid &>/dev/null
    do
        i=$(( (i+1) % 4 ))
        printf "\r$(tput bold)$(tput setaf 6)[ %c ] $(tput sgr0)%s" "${spin:$i:1}" "$1..."
        sleep $delay
    done
    wait $pid
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
        echo -e "\r$(tput bold)$(tput setaf 2)[ ✔ ] $(tput sgr0)$1... $(tput setaf 2)Selesai$(tput sgr0)"
    else
        echo -e "\r$(tput bold)$(tput setaf 1)[ ✘ ] $(tput sgr0)$1... $(tput setaf 1)Gagal$(tput sgr0)"
        exit 1
    fi
}

echo "$(tput bold)$(tput setaf 4)=== Memulai instalasi dan konfigurasi GenieACS ===$(tput sgr0)"

# Menjalankan update
run_command "Update apt-get" "sudo apt-get update -y"

# Menghapus pop up daemons using outdated libraries
run_command "Update needrestart.conf" "sudo sed -i 's/#\$nrconf{restart} = '"'"'i'"'"';/\$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf"

# Instalasi nodejs
run_command "Instalasi Node.js" "sudo apt install -y nodejs"

# Instalasi npm
run_command "Instalasi npm" "sudo apt install -y npm"

# Unduh dan instalasi libssl
run_command "Instalasi libssl" "wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb && sudo dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb"

# Menambahkan key MongoDB
run_command "Menambahkan key MongoDB" "curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -"

# Menambahkan repository MongoDB
run_command "Menambahkan repository MongoDB" "echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list"

# Update apt-get (sekali lagi setelah menambahkan repository)
run_command "Update apt-get" "sudo apt-get update -y"

# Instalasi MongoDB
run_command "Instalasi MongoDB" "sudo apt-get install mongodb-org -y"

# Melakukan upgrade
run_command "Melakukan upgrade" "sudo apt-get upgrade -y"

# Start MongoDB service
run_command "Start MongoDB" "sudo systemctl start mongod"

# Enable MongoDB service
run_command "Enable MongoDB" "sudo systemctl enable mongod"

# Instalasi GenieACS via npm
run_command "Instalasi GenieACS" "sudo npm install -g genieacs@1.2.13"

# Membuat user untuk GenieACS daemons
run_command "Membuat user genieacs" "sudo useradd --system --no-create-home --user-group genieacs"

# Membuat folder untuk extensions & environment
run_command "Membuat folder /opt/genieacs" "sudo mkdir -p /opt/genieacs/ext"
run_command "Menetapkan kepemilikan folder /opt/genieacs" "sudo chown genieacs:genieacs /opt/genieacs/ext"

# Menulis konfigurasi environment GenieACS
echo -e "GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-cwmp-access.log\nGENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-nbi-access.log\nGENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-fs-access.log\nGENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-ui-access.log\nGENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml\nNODE_OPTIONS=--enable-source-maps\nGENIEACS_EXT_DIR=/opt/genieacs/ext" | sudo tee /opt/genieacs/genieacs.env > /dev/null

# Membuat JWT secret
sudo node -e "console.log(\"GENIEACS_UI_JWT_SECRET=\" + require('crypto').randomBytes(128).toString('hex'))" >> /opt/genieacs/genieacs.env

# Menetapkan kepemilikan dan hak akses pada file genieacs.env
run_command "Menetapkan kepemilikan pada genieacs.env" "sudo chown genieacs:genieacs /opt/genieacs/genieacs.env"
run_command "Menetapkan hak akses pada genieacs.env" "sudo chmod 600 /opt/genieacs/genieacs.env"

# Membuat folder log dan menetapkan kepemilikan
run_command "Membuat folder log /var/log/genieacs" "sudo mkdir -p /var/log/genieacs"
run_command "Menetapkan kepemilikan pada /var/log/genieacs" "sudo chown genieacs:genieacs /var/log/genieacs"

# Konfigurasi rotasi log menggunakan logrotate
echo -e "/var/log/genieacs/*.log /var/log/genieacs/*.yaml {\n    daily\n    rotate 30\n    compress\n    delaycompress\n    dateext\n}" | sudo tee /etc/logrotate.d/genieacs > /dev/null

# Konfigurasi systemd service files for GenieACS
genieacs_services=("genieacs-cwmp" "genieacs-nbi" "genieacs-fs" "genieacs-ui")
service_files=("genieacs-cwmp.service" "genieacs-nbi.service" "genieacs-fs.service" "genieacs-ui.service")

for ((i=0; i<${#genieacs_services[@]}; i++)); do
    service_name="${genieacs_services[i]}"
    service_file="${service_files[i]}"
    echo -e "[Unit]\nDescription=GenieACS $service_name\nAfter=network.target\n\n[Service]\nUser=genieacs\nEnvironmentFile=/opt/genieacs/genieacs.env\nExecStart=/usr/local/bin/$service_name\n\n[Install]\nWantedBy=default.target" | sudo tee "/etc/systemd/system/$service_file" > /dev/null
    run_command "Membuat file systemd untuk $service_name" "sudo systemctl daemon-reload"
    run_command "Mengaktifkan dan menjalankan $service_name" "sudo systemctl enable $service_name && sudo systemctl start $service_name"
done

# Menampilkan status services
services=("mongod" "genieacs-cwmp" "genieacs-nbi" "genieacs-fs" "genieacs-ui")
for service in "${services[@]}"; do
    run_command "Pengecekan status $service" "sudo systemctl status $service"
done

echo "$(tput bold)$(tput setaf 2)=== Instalasi dan konfigurasi GenieACS selesai ===$(tput sgr0)"
