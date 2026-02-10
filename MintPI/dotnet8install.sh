    #!/bin/bash

    # Download and install .NET 8 SDK
    echo "Downloading and installing .NET 8 SDK..."
    wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
    chmod +x dotnet-install.sh
    ./dotnet-install.sh --channel 8.0 --install-dir /opt/dotnet

    # Add .NET to PATH and set DOTNET_ROOT
    echo "Configuring environment variables..."
    echo 'export DOTNET_ROOT=/opt/dotnet' | sudo tee -a /etc/profile.d/dotnet.sh
    echo 'export PATH=$PATH:/opt/dotnet:/opt/dotnet/tools' | sudo tee -a /etc/profile.d/dotnet.sh

    echo "Installation complete. Please log out and log back in or run 'source /etc/profile.d/dotnet.sh' to apply changes."