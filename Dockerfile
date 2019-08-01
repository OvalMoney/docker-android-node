FROM openjdk:8-jdk-slim

LABEL maintainer="Fabio Todaro <ft@ovalmoney.com>"

# Initial Command run as `root`.

# make Apt non-interactive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90oval \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90oval

ENV DEBIAN_FRONTEND=noninteractive

# man directory is missing in some base images
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
RUN apt-get update -qqy \
  && mkdir -p /usr/share/man/man1 \
  && apt-get install -qqy \
    apt-utils \
    git xvfb jq \
    locales sudo openssh-client ca-certificates tar gzip parallel \
    net-tools netcat unzip zip bzip2 gnupg curl wget make

# Set timezone to UTC by default
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Use unicode
RUN locale-gen C.UTF-8 || true
ENV LANG=C.UTF-8

RUN groupadd --gid 3434 oval \
  && useradd --uid 3434 --gid oval --shell /bin/bash --create-home oval \
  && echo 'oval ALL=NOPASSWD: ALL' >> /etc/sudoers.d/50-oval \
  && echo 'Defaults    env_keep += "DEBIAN_FRONTEND"' >> /etc/sudoers.d/env_keep

### INSTALL Python ###
RUN apt-get install -qqy \
        python-dev \
        python-setuptools \
        apt-transport-https \
        lsb-release \
        gcc-multilib

### INSTALL PIP ###
ENV PYTHON_PIP_VERSION 19.2.1
# https://github.com/pypa/get-pip
ENV PYTHON_GET_PIP_URL https://github.com/pypa/get-pip/raw/404c9418e33c5031b1a9ab623168b3e8a2ed8c88/get-pip.py
ENV PYTHON_GET_PIP_SHA256 56bb63d3cf54e7444351256f72a60f575f6d8c7f1faacffae33167afc8e7609d

RUN set -ex && \
	wget -O get-pip.py "$PYTHON_GET_PIP_URL" && \
	echo "$PYTHON_GET_PIP_SHA256 *get-pip.py" | sha256sum --check --strict - && \
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		"pip==$PYTHON_PIP_VERSION" && \
	pip --version && \
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' + && \
	rm -f get-pip.py

RUN pip install --no-cache -U --upgrade-strategy eager crcmod

### SWITCH TO OVAL ###
USER oval

# Switching user can confuse Docker's idea of $HOME, so we set it explicitly
ENV HOME /home/oval

### INSTALL Google Cloud SDK ###
RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" && \
    echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

RUN sudo apt-get update -qqy && sudo apt-get install -qqy google-cloud-sdk && \
    gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true

ARG sdk_version=sdk-tools-linux-4333796.zip
ARG android_home=/opt/android/sdk

# SHA-256 92ffee5a1d98d856634e8b71132e8a95d96c83a63fde1099be3d86df3106def9

RUN sudo apt-get install --yes \
        lib32z1 lib32stdc++6 build-essential \
        libcurl4-openssl-dev libglu1-mesa libxi-dev libxmu-dev \
        libglu1-mesa-dev

### INSTALL RUBY ###
ENV RUBY_VERSION 2.6.3
RUN set -ex \
    && for key in \
      04B2F3EA654140BCC7DA1B5754C3D9E9B9515E77 \
    ; do \
      gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
      gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
      gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
    done && \
    cd /tmp/ && \
    wget -O ruby-install-0.7.0.tar.gz https://github.com/postmodern/ruby-install/archive/v0.7.0.tar.gz && \
    wget https://raw.github.com/postmodern/ruby-install/master/pkg/ruby-install-0.7.0.tar.gz.asc && \
    gpg --verify ruby-install-0.7.0.tar.gz.asc ruby-install-0.7.0.tar.gz && \
    tar -xzvf ruby-install-0.7.0.tar.gz && \
    cd ruby-install-0.7.0 && \
    sudo make install && \
    ruby-install --cleanup ruby ${RUBY_VERSION} && \
    cd ../ && rm -r ruby-install-0.7.0.tar.gz.asc ruby-install-0.7.0.tar.gz ruby-install-0.7.0 

ENV PATH ${HOME}/.rubies/ruby-${RUBY_VERSION}/bin:${PATH}
RUN echo 'gem: --env-shebang --no-rdoc --no-ri' >> ~/.gemrc && gem install bundler

### INSTALL ANDROID SDK ###
RUN sudo mkdir -p ${android_home} && \
    sudo chown -R oval:oval ${android_home} && \
    curl --silent --show-error --location --fail --retry 3 --output /tmp/${sdk_version} https://dl.google.com/android/repository/${sdk_version} && \
    unzip -q /tmp/${sdk_version} -d ${android_home} && \
    rm /tmp/${sdk_version}

# Set environmental variables
ENV ANDROID_HOME ${android_home}
ENV ADB_INSTALL_TIMEOUT 120
ENV PATH=${ANDROID_HOME}/emulator:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${PATH}

RUN mkdir ~/.android && echo '### User Sources for Android SDK Manager' > ~/.android/repositories.cfg

RUN yes | sdkmanager --licenses && sdkmanager --update

# Update SDK manager and install system image, platform and build tools
RUN sdkmanager \
  "tools" \
  "platform-tools" \
  "extras;android;m2repository" \
  "extras;google;m2repository" \
  "extras;google;google_play_services"

RUN sdkmanager \
  "build-tools;27.0.0" \
  "build-tools;27.0.1" \
  "build-tools;27.0.2" \
  "build-tools;27.0.3" \
  "build-tools;28.0.0" \
  "build-tools;28.0.1" \
  "build-tools;28.0.2" \
  "build-tools;28.0.3" \
  "build-tools;29.0.0"

# API_LEVEL string gets replaced by m4
RUN sdkmanager "platforms;android-28"

### SWITCH TO ROOT ###
USER root

### INSTALL GRADLE ###
ENV GRADLE_HOME /opt/gradle
ENV GRADLE_VERSION 5.5.1
ARG GRADLE_DOWNLOAD_SHA256=222a03fcf2fcaf3691767ce9549f78ebd4a77e73f9e23a396899fb70b420cd00
RUN set -o errexit -o nounset \
    && echo "Downloading Gradle" \
    && wget --no-verbose --output-document=gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
    \
    && echo "Checking download hash" \
    && echo "${GRADLE_DOWNLOAD_SHA256} *gradle.zip" | sha256sum --check - \
    \
    && echo "Installing Gradle" \
    && unzip gradle.zip \
    && rm gradle.zip \
    && mv "gradle-${GRADLE_VERSION}" "${GRADLE_HOME}/" \
    && ln --symbolic "${GRADLE_HOME}/bin/gradle" /usr/bin/gradle \
    \
    && echo "Testing Gradle installation" \
    && gradle --version

### INSTALL NODE ###
## Using node installation from https://raw.githubusercontent.com/nodejs/docker-node/526c6e618300bdda0da4b3159df682cae83e14aa/8/jessie/Dockerfile
RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node

ENV NODE_VERSION 12.4.0

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  # gpg keys listed at https://github.com/nodejs/node#release-team
  && set -ex \
  && for key in \
    4ED778F539E3634C779C87C6D7062848A1AB005C \
    B9E2F5981AA6E0CD28160D9FF13993A75599653C \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    77984A986EBC2AA786BC0F66B01FBB92821C587A \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    FD3A5288F042B6850C66B31F09FE44734EB7990E \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
  ; do \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done \
  && echo "Downloading Node" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && echo "Checking download hash" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && echo "Installing Node" \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  && echo "Testing Node installation" \
  && node --version

### INSTALL YARN ###
ENV YARN_VERSION 1.17.3

RUN set -ex \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done \
  && echo "Downloading Yarn" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && echo "Checking download hash" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && echo "Installing Yarn" \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && echo "Testing Yarn installation" \
  && yarn --version

### INSTALL AWSCLI
RUN apt-get update && \
    apt-get install -y awscli

### INSTALL WATCHMAN ###
RUN apt-get install -y \
    libssl-dev autoconf automake libtool pkg-config

RUN cd /tmp && wget -O watchman-4.9.0.tar.gz https://github.com/facebook/watchman/archive/v4.9.0.tar.gz && \
    tar -xzvf watchman-4.9.0.tar.gz && \
    cd watchman-4.9.0 && \
    ./autogen.sh && \
    ./configure --enable-lenient && \
    make && \
    make install

# Basic smoke test
RUN node --version

### SWITCH TO OVAL ###
USER oval
