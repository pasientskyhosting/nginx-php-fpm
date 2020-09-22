#!/bin/bash

function checkForFail() {
    if [ ! $? -eq 0 ]; then
        echo "Command failed"
        exit 1
    fi
}

# Disable Strict Host checking for non interactive git clones
mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

# Set podname for php
sed -i "s|{{pool_name}}|$HOSTNAME|" /usr/local/etc/php-fpm.d/www.conf
sed -i "s|{{pool_name}}|$HOSTNAME|" /usr/local/etc/php-fpm.d/www1.conf
sed -i "s|{{pool_name}}|$HOSTNAME|" /usr/local/etc/php-fpm.d/www2.conf
sed -i "s|{{pool_name}}|$HOSTNAME|" /usr/local/etc/php-fpm.d/www3.conf

# Add new relic if key is present
if [ ! -z "$NEW_RELIC_LICENSE_KEY" ]; then
    export NR_INSTALL_KEY=$NEW_RELIC_LICENSE_KEY
    newrelic-install install || exit 1

    echo "newrelic.appname = \"$PS_ENVIRONMENT-$PS_APPLICATION\"" >> /usr/local/etc/php/conf.d/newrelic.ini
    echo "newrelic.daemon.logfile = \"/proc/self/fd/2\"" >> /usr/local/etc/php/conf.d/newrelic.ini
    echo "newrelic.logfile = \"/proc/self/fd/2\"" >> /usr/local/etc/php/conf.d/newrelic.ini
    echo "newrelic.distributed_tracing_enabled = true" >> /usr/local/etc/php/conf.d/newrelic.ini
    echo "newrelic.labels = \"location:"$PS_DEPLOYMENT_DATACENTER";environment:"$PS_ENVIRONMENT"\"" >> /usr/local/etc/php/conf.d/newrelic.ini
else
    echo "NEW_RELIC_LICENSE_KEY was not provided. Removing newrelic-php5 to disable newrelic"
    apt-get purge -qy newrelic-php5
fi

if [ -d "/adaptions" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /adaptions/*

    # run scripts in number order
    for i in `ls /adaptions/`; do /adaptions/$i || exit 1; done
fi

if [ -z "$PRESERVE_PARAMS" ]; then

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
            path:  "php://stderr"
            level: error
EOF



        if [ ! -z "$PS_ENVIRONMENT" ]; then
cat > /var/www/html/app/config/parameters.yml <<EOF
parameters:
    consul_uri: $PS_CONSUL_FULL_URL
    consul_sections:
        - 'parameters/base/common.yml'
        - 'parameters/base/$PS_APPLICATION.yml'
        - 'parameters/$PS_ENVIRONMENT/common.yml'
        - 'parameters/$PS_ENVIRONMENT/$PS_APPLICATION.yml'
    env(PS_ENVIRONMENT): $PS_ENVIRONMENT
    env(PS_APPLICATION): $PS_APPLICATION
    env(PS_BUILD_ID): $PS_BUILD_ID
    env(PS_BUILD_NR): $PS_BUILD_NR
    env(PS_BASE_HOST): $PS_BASE_HOST
    env(NEW_RELIC_API_URL): $NEW_RELIC_API_URL
EOF
        fi

        cd /var/www/html
        rm -rf /var/www/html/var
        mkdir -p /var/www/html/var
        /usr/bin/composer run-script build-parameters --no-interaction
        checkForFail

        if [ -f /var/www/html/bin/console ]; then
            /var/www/html/bin/console cache:clear --no-warmup --env=prod
            checkForFail
            /var/www/html/bin/console cache:warmup --env=prod
            checkForFail
        fi

    fi

fi
