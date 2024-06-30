#!/bin/bash

# Install dos2unix
sudo apt-get install -y dos2unix

# Convert the script GACS-Jammy.sh to Unix format
dos2unix GACS-Jammy.sh

# Run the script GACS-Jammy.sh
bash GACS-Jammy.sh
