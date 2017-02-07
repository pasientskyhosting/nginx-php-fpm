#!/bin/bash

# Disable Strict Host checking for non interactive git clones

mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [ ! -z "$SSH_KEY" ]; then
 echo $SSH_KEY > /root/.ssh/id_rsa.base64
 base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
 webroot=$WEBROOT
 sed -i "s#root /var/www/html/web;#root ${webroot};#g" /etc/nginx/sites-available/default.conf
else
 webroot=/var/www/html
fi

# Set custom server name
if [ ! -z "$SERVERNAME" ]; then
 sed -i "s#server_name _;#server_name $SERVERNAME;#g" /etc/nginx/sites-available/default.conf
fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
 git config --global user.email "$GIT_EMAIL"
fi
if [ ! -z "$GIT_NAME" ]; then
 git config --global user.name "$GIT_NAME"
 git config --global push.default simple
fi

git config --global http.postBuffer 1048576000

# Dont pull code down if the .git folder exists
if [ ! -d "/var/www/html/.git" ]; then
 # Pull down code from git for our site!
 if [ ! -z "$GIT_REPO" ]; then
   # Remove the test index file
   rm -Rf /var/www/html/*
   if [ ! -z "$GIT_BRANCH" ]; then
     if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
       git clone -b $GIT_BRANCH $GIT_REPO /var/www/html/ || exit 1
     else
       git clone -b ${GIT_BRANCH} https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /var/www/html || exit 1
     fi
   else
     if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
       git clone $GIT_REPO /var/www/html/ || exit 1
     else
       git clone https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /var/www/html || exit 1
     fi
   fi
 fi
fi

# Composer
if [ -f /var/www/html/composer.json ];
then

cat > /var/www/html/app/config/config_prod.yml <<EOF
imports:
    - { resource: config.yml }
monolog:
    handlers:
        main:
            type: stream
            path:  "/dev/stdout"
            level: error
EOF

    cd /var/www/html
    /usr/bin/composer install --no-interaction --no-dev --optimize-autoloader
    php app/console cache:clear --env=prod
fi

# Always chown webroot for better mounting
chown -R nginx:nginx /var/www/html

# Add new relic if key is present
if [ ! -z "$NEW_RELIC_LICENSE_KEY" ]; then
    newrelic-install install || exit 1
    nrsysmond-config --set license_key=${NEW_RELIC_LICENSE_KEY} || exit 1
    echo -e "\n[program:nrsysmond]\ncommand=nrsysmond -c /etc/newrelic/nrsysmond.cfg -l /dev/stdout -f\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
fi

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
