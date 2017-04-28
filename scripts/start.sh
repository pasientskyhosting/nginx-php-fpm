#!/bin/bash

/setup.sh

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
