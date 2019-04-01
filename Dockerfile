FROM php:7.1.27-fpm

MAINTAINER Andreas Krüger <ak@patientsky.com>

ENV composer_hash 669656bab3166a7aff8a7506b8cb2d1c292f042046c5a994c43155c0be6190fa0355160742ab2e1c88d40d5be660b410
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ENV TINI_VERSION v0.18.0

RUN apt-get update && apt-get install -y -q --install-recommends --no-install-suggests \
        dirmngr \
        gnupg2 \
        wget \
        host \
        net-tools \
        tzdata \
        ca-certificates \
        supervisor \
        libmcrypt-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libcurl4-openssl-dev \
        libmagickwand-dev \
        libmagickcore-dev \
        libssl-dev \
        librabbitmq-dev \
        zlib1g-dev \
        libicu-dev \
        g++ \
        localepurge \
        make \
        unzip \
        locales \
        pkg-config \
        git \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && wget https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini -O /tini \
    && chmod +x /tini \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ABF5BD827BD9BF62 \
    && curl https://download.newrelic.com/548C16BF.gpg | apt-key add - \
    && echo "deb http://nginx.org/packages/mainline/debian/ stretch nginx" > /etc/apt/sources.list.d/nginx.list \
    && echo "deb-src http://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list.d/nginx.list \
    && echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list \
    && composer_hash=$(wget -q -O - https://composer.github.io/installer.sig) \
    && wget https://getcomposer.org/installer -O composer-setup.php \
    && php -r "if (hash_file('SHA384', 'composer-setup.php') === '${composer_hash}') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php --install-dir=/usr/bin --filename=composer \
    && rm composer-setup.php

RUN apt-get update \
    && apt-get install -y -q --no-install-recommends --no-install-suggests \
        nginx \
        newrelic-php5 \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-configure intl \
    && docker-php-ext-configure pcntl \
    && docker-php-ext-install -j$(nproc) \
         iconv \
         mcrypt \
         gd \
         pdo_mysql \
         json \
         bcmath \
         intl \
         opcache \
         mbstring \
         xml \
         zip \
         pcntl \
    && pecl install \
         redis \
         amqp \
         igbinary \
         imagick \
    && docker-php-ext-enable \
         redis \
         amqp \
         igbinary \
         imagick

RUN cd / && mkdir -p /etc/nginx && \
    mkdir -p /var/www/app && \
    mkdir -p /run/nginx && \
    mkdir -p /var/log/supervisor && \
    rm -Rf /etc/nginx/nginx.conf && \
    mkdir -p /etc/nginx/sites-enabled/ && \
    rm -Rf /etc/nginx/sites-enabled/* && \
    rm -Rf /var/www/* && \
    mkdir /var/www/html/ && \
    echo "<?php var_dump(opcache_get_status(false)); phpinfo();" > /var/www/phpinfo.php \
    && rm /usr/local/etc/php-fpm.d/* \
    && echo "opcache.enable=1\nopcache.enable_cli=1\nopcache.consistency_checks=0\nopcache.file_cache=/tmp\nopcache.file_cache_consistency_checks=0\nopcache.validate_timestamps=0\nopcache.max_accelerated_files=32531\nopcache.memory_consumption=512\nopcache.interned_strings_buffer=8\nopcache.revalidate_freq=60\nopcache.fast_shutdown=0\nopcache.error_log=/proc/self/fd/2" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini \
    && sed -i 's/# nb_NO.UTF-8 UTF-8/nb_NO.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen nb_NO.UTF-8 \
    && sed -i "s|USE_DPKG|#USE_DPKG|" /etc/locale.nopurge && localepurge \
    && apt autoremove -y \
    && apt-get purge -y \
      g++ \
      make \
      pkg-config \
      localepurge \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# Setup nginx and supervisord
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf
ADD conf/nginx-site.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm
ADD conf/php-fpm.conf /usr/local/etc/php-fpm.d/php-fpm.conf
COPY conf/php-fpm.d/* /usr/local/etc/php-fpm.d/

# tweak php
COPY conf/php.ini /usr/local/etc/php/php.ini
COPY scripts/* /

RUN chmod 755 /start.sh && chmod 755 /setup.sh

EXPOSE 80

CMD ["/start.sh"]
