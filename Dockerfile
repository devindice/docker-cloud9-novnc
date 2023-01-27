# Built with arch: amd64 flavor: lxde image: ubuntu:20.04
#
################################################################################
# base system
################################################################################


FROM ubuntu:22.04 as system


RUN sed -i 's#http://archive.ubuntu.com/ubuntu/#mirror://mirrors.ubuntu.com/mirrors.txt#' /etc/apt/sources.list;

# Ca-Certificates
RUN apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
        ca-certificates \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*


# built-in packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends apt-utils software-properties-common curl \
           apache2-utils man-db manpages-posix manpages-dev manpages-posix-dev \
    && apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
        supervisor nginx sudo net-tools zenity xz-utils \
        dbus-x11 x11-utils alsa-utils \
        mesa-utils libgl1-mesa-dri \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*
    
# install debs error if combine together
RUN apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
        xvfb x11vnc ttf-wqy-zenhei  \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

#RUN apt update \
#    && apt install -y gpg-agent \
#    && curl -LO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
#    && (dpkg -i ./google-chrome-stable_current_amd64.deb || apt-get install -fy) \
#    && curl -sSL https://dl.google.com/linux/linux_signing_key.pub | apt-key add \
#    && rm google-chrome-stable_current_amd64.deb \
#    && rm -rf /var/lib/apt/lists/*

# Install Desktop
RUN apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
        xubuntu-desktop gtk2-engines-murrine gnome-themes-standard gtk2-engines-pixbuf gtk2-engines-murrine arc-theme \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# tini service manager
ARG TINI_VERSION=v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /bin/tini
RUN chmod +x /bin/tini

# ffmpeg
RUN apt update \
    && apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /usr/local/ffmpeg \
    && ln -s /usr/bin/ffmpeg /usr/local/ffmpeg/ffmpeg

# python library
COPY rootfs/usr/local/lib/web/backend/requirements.txt /tmp/
RUN apt-get update \
    && dpkg-query -W -f='${Package}\n' > /tmp/a.txt \
    && apt-get install -y python3-pip python3-dev build-essential \
	&& pip3 install setuptools wheel && pip3 install -r /tmp/requirements.txt \
    && ln -s /usr/bin/python3 /usr/local/bin/python \
    && dpkg-query -W -f='${Package}\n' > /tmp/b.txt \
    && apt-get remove -y `diff --changed-group-format='%>' --unchanged-group-format='' /tmp/a.txt /tmp/b.txt | xargs` \
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* /tmp/a.txt /tmp/b.txt

# Install Additonal Packages
RUN mkdir /cloud9
COPY rootfs/cloud9/apt-requirements.txt /cloud9/apt-requirements.txt
RUN apt update \
    && grep -v '^#' /cloud9/apt-requirements.txt | xargs apt install -y -o Dpkg::Options::='--force-confold' --no-install-recommends --allow-unauthenticated \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

#RUN mkdir /workspace

# Clone and install cloud9
RUN git clone https://github.com/c9/core.git /cloud9/c9sdk
#RUN mkdir -p /cloud9/c9sdk/build /workspace/.ubuntu/.standalone
#RUN ln -sf /workspace/.ubuntu/.standalone /cloud9/c9sdk/build/standalone
#RUN /cloud9/c9sdk/scripts/install-sdk.sh
RUN cd /cloud9/c9sdk && git reset --hard
RUN wget -O user-install.sh https://raw.githubusercontent.com/c9/install/master/install.sh && mv user-install.sh /cloud9/


################################################################################
# builder
################################################################################
FROM ubuntu:20.04 as builder


RUN sed -i 's#http://archive.ubuntu.com/ubuntu/#mirror://mirrors.ubuntu.com/mirrors.txt#' /etc/apt/sources.list;


RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg patch \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# nodejs
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get install -y nodejs \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y yarn \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# build frontend
COPY web /src/web
RUN cd /src/web \
    && yarn \
    && yarn build
RUN sed -i 's#app/locale/#novnc/app/locale/#' /src/web/dist/static/novnc/app/ui.js



################################################################################
# merge
################################################################################
FROM system
LABEL maintainer="info@devindice.com"

COPY --from=builder /src/web/dist/ /usr/local/lib/web/frontend/

RUN ln -sf /usr/local/lib/web/frontend/static/websockify /usr/local/lib/web/frontend/static/novnc/utils/websockify && \
	chmod +x /usr/local/lib/web/frontend/static/websockify/run

EXPOSE 6080
EXPOSE 9999

WORKDIR /workspace
ENV HOME=/home/ubuntu \
    SHELL=/bin/bash
HEALTHCHECK --interval=30s --timeout=5s CMD curl --fail http://127.0.0.1:6079/api/health
ENTRYPOINT ["/startup.sh"]

# Install Docker
RUN groupadd -g 281 docker
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt-get update
RUN apt-get -y install nautilus menulibre python3-pip keychain python3.8-venv strace gedit gvfs-backends
RUN apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

RUN wget -O beyond-compare.deb https://www.scootersoftware.com/$(curl -sd "platform=linux" https://www.scootersoftware.com/download.php | grep amd64.deb | awk -F\" '{print $2}' | sed 's/\///g')
RUN wget -O sublime-text.deb $(curl -s https://www.sublimetext.com/download_thanks?target=x64-deb#direct-downloads | grep amd64.deb | grep url | awk -F'"' '{print $2}')
RUN wget -O sublime-merge.deb $(curl -s https://www.sublimemerge.com/download_thanks?target=x64-deb#direct-downloads | grep amd64.deb | grep url | awk -F'"' '{print $2}')
RUN wget -O chrome.deb wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb || true
RUN apt install -y ./beyond-compare.deb
RUN apt install -y ./sublime-text.deb
RUN apt install -y ./sublime-merge.deb
RUN apt install -y ./chrome.deb

RUN npm -g install sass yuglify

RUN apt -y remove thunar

# Copy files
COPY rootfs /

# Extras
RUN apt-get update \
    && apt-get install -y --no-install-recommends ansible terraform golang whiptail osmctools osmosis cron \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

#RUN rm -rf /workspace/*

RUN useradd -d /home/ubuntu -u 99 -G sudo -ms /bin/bash ubuntu
#RUN adduser ubuntu sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN chown ubuntu:ubuntu /home/ubuntu

# Install from user (not doing)
USER ubuntu
CMD /bin/bash

run bash /cloud9/user-install.sh

user root
