FROM debian:wheezy

# persistent / runtime deps
RUN apt-get update && apt-get install -y ca-certificates curl librecode0 libsqlite3-0 libxml2 --no-install-recommends && rm -r /var/lib/apt/lists/*

# phpize deps
RUN apt-get update && apt-get install -y autoconf file g++ gcc libc-dev make pkg-config re2c --no-install-recommends && rm -r /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

RUN apt-get update && apt-get install -y apache2-mpm-prefork --no-install-recommends && rm -rf /var/lib/apt/lists/*

ENV APACHE_RUN_DIR /var/run/apache2
ENV APACHE_LOCK_DIR /var/lock/apache2
ENV APACHE_LOG_DIR /var/log/apache2

RUN rm -rf /var/www/html && mkdir -p $APACHE_LOCK_DIR $APACHE_RUN_DIR $APACHE_LOG_DIR /var/www/html && chown -R www-data:www-data $APACHE_LOCK_DIR $APACHE_RUN_DIR $APACHE_LOG_DIR /var/www/html

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist && rm -rf /etc/apache2/conf.d/* /etc/apache2/sites-enabled/*
COPY apache2.conf /etc/apache2/apache2.conf
# it'd be nice if we could not COPY apache2.conf until the end of the Dockerfile, but its contents are checked by PHP during compilation

ENV PHP_EXTRA_BUILD_DEPS apache2-prefork-dev
ENV PHP_EXTRA_CONFIGURE_ARGS --with-apxs2=/usr/bin/apxs2

ENV PHP_VERSION 5.6.7

# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
		$PHP_EXTRA_BUILD_DEPS \
		libcurl4-openssl-dev \
		libreadline6-dev \
		librecode-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		xz-utils \
	" \
	&& set -x \
	&& apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
	&& mkdir -p /usr/src/php \
	&& tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
	&& rm php.tar.xz* \
	&& cd /usr/src/php \
	&& ./configure \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		$PHP_EXTRA_CONFIGURE_ARGS \
		--disable-cgi \
		--enable-mysqlnd \
		--with-curl \
		--with-openssl \
		--with-readline \
		--with-recode \
		--with-zlib \
	&& make -j"$(nproc)" \
	&& make install \
	&& { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
	&& apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
	&& make clean

COPY docker-php-ext-* /usr/local/bin/

# Install xdebug
COPY xdebug.ini /tmp/
RUN pecl config-set php_ini $PHP_INI_DIR/php.ini \
  && touch $PHP_INI_DIR/php.ini \
  && pecl install xdebug \
  && docker-php-ext-enable xdebug \
  && cat /tmp/xdebug.ini >> $PHP_INI_DIR/conf.d/docker-php-ext-xdebug.ini \
  && rm -rf /tmp/xdebug.ini $PHP_INI_DIR/php.ini

COPY apache2-foreground /usr/local/bin/
WORKDIR /var/www/html

EXPOSE 80 9000
CMD ["apache2-foreground"]
