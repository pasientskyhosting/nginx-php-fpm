#!/bin/bash

/setup.sh

# Make sure permissions is always right
# chown -R nginx:nginx /var/www/html

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
