#!/bin/bash

# Copy this file to config.sh and edit for your setup

# Pi-hole settings
PIHOLE_PASSWORD="change-me"
PIHOLE_TIMEZONE="America/Los_Angeles"
PIHOLE_UPSTREAM_DNS="1.1.1.1;8.8.8.8"

# Colima VM resources
COLIMA_CPUS=2
COLIMA_MEMORY=4

# Dashboard port (access via http://hostname:DASHBOARD_PORT/admin)
DASHBOARD_PORT=8053
