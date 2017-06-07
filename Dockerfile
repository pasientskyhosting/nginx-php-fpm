FROM debian:jessie-slim

MAINTAINER Andreas Krüger <ak@patientsky.com>

ENV DEBIAN_FRONTEND noninteractive
ENV composer_hash 669656bab3166a7aff8a7506b8cb2d1c292f042046c5a994c43155c0be6190fa0355160742ab2e1c88d40d5be660b410

RUN apt-get update \
    && apt-get install -y -q --no-install-recommends \
    apt-transport-https \
    lsb-release \
    wget \
    vim \
    host \
    tzdata \
    apt-utils \
    ca-certificates

RUN echo "deb http://nginx.org/packages/debian/ jessie nginx" > /etc/apt/sources.list.d/nginx.list && \
    echo "deb-src http://nginx.org/packages/debian/ jessie nginx" >> /etc/apt/sources.list.d/nginx.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ABF5BD827BD9BF62

RUN echo "deb http://packages.dotdeb.org jessie all" > /etc/apt/sources.list.d/dotdeb.list && \
    echo "deb-src http://packages.dotdeb.org jessie all" >> /etc/apt/sources.list.d/dotdeb.list && \
    wget https://www.dotdeb.org/dotdeb.gpg && apt-key add dotdeb.gpg

RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

RUN echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list && \
    wget -O- https://download.newrelic.com/548C16BF.gpg | apt-key add -

RUN apt-get update \
    && apt-get install -y -q --no-install-recommends \
    php7.1-cli \
    php7.1-fpm \
    php7.1-mysql \
    php7.1-bcmath \
    php7.1-gd \
    php7.1-curl \
    php7.1-json \
    php7.1-mcrypt \
    php7.1-cli \
    php7.1-imagick \
    php7.1-intl \
    php7.1-opcache \
    php7.1-mongodb \
    php7.1-mbstring \
    php-redis \
    php7.1-xml \
    php7.1-zip \
    php-igbinary \
    php7.1-dev \
    librabbitmq-dev \
    net-tools \
    make \
    php-pear \
    nginx \
    supervisor \
    unzip \
    newrelic-php5 \
#    newrelic-sysmond \
    locales \
    && yes '' | pecl install amqp \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

# Install no locale
RUN sed -i 's/# nb_NO.UTF-8 UTF-8/nb_NO.UTF-8 UTF-8/' /etc/locale.gen && \
    ln -s /etc/locale.alias /usr/share/locale/locale.alias && \
    locale-gen nb_NO.UTF-8

RUN mkdir -p /etc/nginx && \
    mkdir -p /var/www/app && \
    mkdir -p /run/nginx && \
    mkdir -p /var/log/supervisor && \
    rm -Rf /etc/nginx/nginx.conf && \
    mkdir -p /etc/nginx/sites-enabled/ && \
    rm -Rf /etc/nginx/sites-enabled/* && \
    rm -Rf /var/www/* && \
    mkdir /var/www/html/

# Setup nginx and supervisord
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf
ADD conf/nginx-site.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm
ADD conf/php-fpm.conf /etc/php/7.1/fpm/php-fpm.conf
ADD conf/www.conf /etc/php/7.1/fpm/pool.d/www.conf

# tweak php
ADD conf/php.ini /etc/php/7.1/fpm/conf.d/50-settings.ini
ADD conf/php.ini /etc/php/7.1/cli/conf.d/50-settings.ini

# Configure php opcode cache
ADD conf/opcache.ini /etc/php/7.1/fpm/conf.d/10-opcache.ini
ADD conf/opcache.ini /etc/php/7.1/cli/conf.d/10-opcache.ini

# Enable AMPQ plugin
RUN echo "extension=amqp.so" >> /etc/php/7.1/cli/conf.d/20-amqp.ini && \
    echo "extension=amqp.so" >> /etc/php/7.1/fpm/conf.d/20-amqp.ini

# Add errors and scripts
ADD errors/ /var/www/errors
ADD scripts/start.sh /start.sh
ADD scripts/setup.sh /setup.sh
RUN chmod 755 /start.sh && \
    chmod 755 /setup.sh

# Add composer
RUN composer_hash=$(wget -q -O - https://composer.github.io/installer.sig) && \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php -r "if (hash_file('SHA384', 'composer-setup.php') === '${composer_hash}') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
    php composer-setup.php --install-dir=/usr/bin --filename=composer && \
    php -r "unlink('composer-setup.php');"

EXPOSE 80
CMD ["/start.sh"]
