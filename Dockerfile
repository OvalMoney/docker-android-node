FROM openjdk:11-jdk-slim

LABEL maintainer="Fabio Todaro <ft@ovalmoney.com>"

# Initial Command run as `root`.

# make Apt non-interactive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90oval \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90oval

ENV DEBIAN_FRONTEND=noninteractive

# Make sure PATH includes ~/.local/bin
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=839155
# This only works for root. The oval user is done near the end of this Dockerfile
RUN echo 'PATH="$HOME/.local/bin:$PATH"' >> /etc/profile.d/user-local-path.sh

# man directory is missing in some base images
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
RUN apt-get update \
  && mkdir -p /usr/share/man/man1 \
  && apt-get install -y \
    git mercurial xvfb apt jq \
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


USER oval
ENV PATH /home/oval/.local/bin:/home/oval/bin:${PATH}

CMD ["/bin/sh"]


# Now commands run as user `oval`

# Switching user can confuse Docker's idea of $HOME, so we set it explicitly
ENV HOME /home/oval

# Install Google Cloud SDK

RUN sudo apt-get update -qqy && sudo apt-get install -qqy \
        python-dev \
        python-pip \
        python-setuptools \
        apt-transport-https \
        lsb-release && \
    sudo rm -rf /var/lib/apt/lists/*

RUN sudo apt-get update && sudo apt-get install gcc-multilib && \
    sudo rm -rf /var/lib/apt/lists/* && \
    sudo pip uninstall crcmod && \
    sudo pip install --no-cache -U crcmod eager

RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" && \
    echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

RUN sudo apt-get update && sudo apt-get install -y google-cloud-sdk && \
    sudo rm -rf /var/lib/apt/lists/* && \
    gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true

ARG cmdline_tools=https://dl.google.com/android/repository/commandlinetools-linux-6609375_latest.zip
ARG android_home=/opt/android/sdk

# SHA-256 92ffee5a1d98d856634e8b71132e8a95d96c83a63fde1099be3d86df3106def9

RUN sudo apt-get update && \
    sudo apt-get install --yes \
        xvfb lib32z1 lib32stdc++6 build-essential \
        libcurl4-openssl-dev libglu1-mesa libxi-dev libxmu-dev \
        libglu1-mesa-dev && \
    sudo rm -rf /var/lib/apt/lists/*

# Install Ruby
ENV RUBY_VERSION 2.6.3
RUN sudo apt-get update && \
    cd /tmp && wget -O ruby-install-0.7.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.7.1.tar.gz && \
    tar -xzvf ruby-install-0.7.1.tar.gz && \
    cd ruby-install-0.7.1 && \
    sudo make install && \
    ruby-install --cleanup ruby ${RUBY_VERSION} && \
    rm -r /tmp/ruby-install-* && \
    sudo rm -rf /var/lib/apt/lists/*

ENV PATH ${HOME}/.rubies/ruby-${RUBY_VERSION}/bin:${PATH}
RUN echo 'gem: --env-shebang --no-rdoc --no-ri' >> ~/.gemrc && gem install bundler

# Download and install Android Commandline Tools
RUN sudo mkdir -p ${android_home}/cmdline-tools && \
    sudo chown -R oval:oval ${android_home} && \
    wget -O /tmp/cmdline-tools.zip -t 5 "${cmdline_tools}" && \
    unzip -q /tmp/cmdline-tools.zip -d ${android_home}/cmdline-tools && \
    rm /tmp/cmdline-tools.zip

# Set environmental variables
ENV ANDROID_HOME ${android_home}
ENV ADB_INSTALL_TIMEOUT 120
ENV PATH=${ANDROID_HOME}/emulator:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${PATH}

RUN mkdir ~/.android && echo '### User Sources for Android SDK Manager' > ~/.android/repositories.cfg

RUN yes | sdkmanager --licenses && yes | sdkmanager --update

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
  # 28.0.0 is failing to download from Google for some reason
  #"build-tools;28.0.0" \
  "build-tools;28.0.1" \
  "build-tools;28.0.2" \
  "build-tools;28.0.3" \
  "build-tools;29.0.0" \
  "build-tools;29.0.1" \
  "build-tools;29.0.2" \
  "build-tools;29.0.3" \
  "build-tools;30.0.0" \
  "build-tools;30.0.1" \
  "build-tools;30.0.2"

# API_LEVEL string gets replaced by m4
RUN sdkmanager "platforms;android-29"

# Verify the oval user exists before proceeding
RUN whoami

# node installations command expect to run as root
USER root

### INSTALL GRADLE ###
ENV GRADLE_HOME /opt/gradle
ENV GRADLE_VERSION 6.0.1
ARG GRADLE_DOWNLOAD_SHA256=d364b7098b9f2e58579a3603dc0a12a1991353ac58ed339316e6762b21efba44
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
RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node

ENV NODE_VERSION 12.19.0

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
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  && set -ex \
  && for key in \
    4ED778F539E3634C779C87C6D7062848A1AB005C \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
    108F52B48DB57BB0CC439B2997B01419BD92F80A \
    B9E2F5981AA6E0CD28160D9FF13993A75599653C \
  ; do \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  # smoke tests
  && node --version \
  && npm --version

### INSTALL YARN ###
ENV YARN_VERSION 1.22.10

RUN set -ex \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  # smoke test
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

USER oval
