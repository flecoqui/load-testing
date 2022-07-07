FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-20.04 

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
# Steps below not required as reusing devcontainer image
# RUN groupadd --gid $USER_GID $USERNAME \
#    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

RUN apt-get update \
    && apt-get install -y gnupg software-properties-common ffmpeg wget 

# apt stuff
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    # install missing packages
    && mkdir -p /usr/share/man/man1 \
    && apt-get install -y sudo git curl make procps lsb-release vim jq\
    # add sudo support
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    # install azure-cli
    && curl -sL https://aka.ms/InstallAzureCLIDeb  | bash 

# install python3 and pip3
RUN apt-get update \
    && apt-get install -y python3-pip 

# install .Net 6.0 SDK
RUN wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
RUN dpkg -i packages-microsoft-prod.deb
RUN apt-get update \
    && apt-get install -y apt-transport-https \
    && apt-get install -y dotnet-sdk-6.0

# install Azure Function Core Tools
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
RUN mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
RUN echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list
RUN apt-get update && apt-get install azure-functions-core-tools-4


# install npm
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest 

# install typescript
RUN npm install -g typescript \
    && npm install -g webpack \
    && npm install -g webpack-cli \
    && npm install -g uglifyjs-webpack-plugin \
    && npm install -g @types/jquery \
    && npm install -g http-server \
    && npm install -g eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin \
    && npm install -g forever
    
# Install Docker CLI
RUN apt-get update \
    && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    dnsutils
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

RUN echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN  apt-get update \
      && apt-get install -y docker-ce-cli

# install shellcheck
RUN apt-get install -y shellcheck

# now everything from here uses the normal user
USER $USERNAME

# configure az cli to automatically install extension
RUN az config set extension.use_dynamic_install=yes_without_prompt

# back to default shell
SHELL ["/bin/sh", "-c"]

CMD [ "sleep", "infinity" ]