#!/bin/bash

# Create a log pipe so non root can write to stdout
mkfifo -m 600 /tmp/logpipe
cat <> /tmp/logpipe 1>&2 &
chown -R nginx:nginx /tmp/logpipe

# Disable Strict Host checking for non interactive git clones
mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [ ! -z "$SSH_KEY" ]; then
    echo $SSH_KEY > /root/.ssh/id_rsa.base64
    base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    unset SSH_KEY
fi

# Add new relic if key is present
if [ ! -z "$NEW_RELIC_LICENSE_KEY" ]; then
    newrelic-install install || exit 1
    nrsysmond-config --set license_key=${NEW_RELIC_LICENSE_KEY} || exit 1
    echo -e "\n[program:nrsysmond]\ncommand=nrsysmond -c /etc/newrelic/nrsysmond.cfg -l /dev/stdout -f\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
    unset NEW_RELIC_LICENSE_KEY
else
    if [ -f /etc/php/7.1/fpm/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/fpm/conf.d/20-newrelic.ini
    fi
    if [ -f /etc/php/7.1/cli/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/cli/conf.d/20-newrelic.ini
    fi
    /etc/init.d/newrelic-daemon stop
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
    unset GIT_EMAIL
fi

if [ ! -z "$GIT_NAME" ]; then
    git config --global user.name "$GIT_NAME"
    git config --global push.default simple
fi

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
                unset GIT_PERSONAL_TOKEN
                unset GIT_USERNAME
            fi
        else
            if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
                git clone $GIT_REPO /var/www/html/ || exit 1
            else
                git clone https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /var/www/html || exit 1
                unset GIT_PERSONAL_TOKEN
                unset GIT_USERNAME
            fi
        fi
        unset GIT_REPO
    fi
fi

if [ -d "/adaptions" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /adaptions/*

    # run scripts in number order
    for i in `ls /adaptions/`; do /adaptions/$i ; done
fi

if [ -f /var/www/html/app/config/parameters.yml.dist ]; then
    echo "    k8s_build_id: $PS_BUILD_ID" >> /var/www/html/app/config/parameters.yml.dist
fi

# Composer
if [ -f /var/www/html/composer.json ]; then
cat > /var/www/html/app/config/config_prod.yml <<EOF
imports:
    - { resource: config.yml }
monolog:
    handlers:
        main:
            type: stream
            path:  "/tmp/logpipe"
            level: error
EOF


    if [ ! -z "$CONSUL_ENVIRONMENT" ]; then
cat > /var/www/html/app/config/parameters.yml <<EOF
parameters:
    consul_uri: https://$CONSUL_USERNAME:$CONSUL_PASSWORD@$CONSUL_URL
    consul_sections: ['$CONSUL_ENVIRONMENT/common', '$CONSUL_ENVIRONMENT/$CONSUL_APPLICATION']
EOF
    fi

    cd /var/www/html
    mkdir -p /var/www/html/var
    /usr/bin/composer run-script build-parameters
fi

# Always chown webroot for better mounting
chown -R nginx:nginx /var/www/html

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
