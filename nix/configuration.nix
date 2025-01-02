{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  environment.etc = {
    profile = {
      text = ''
        fastfetch
      '';
    };
  };

  boot.loader.grub = {
    enable = true;
    version = 2;                                            # Specify GRUB version
    devices = [ "" ];
  };
  boot.loader.efi.canTouchEfiVariables = true;
  

  networking.hostName = "Nixerv";                           # Set hostname for the system
  networking.domain = "Nixerv.home";                        # Replace with your domain if applicable
  networking.networkmanager.enable = true;                  # Enable NetworkManager for easier network configuration
  #networking.firewall.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";                       # Set system locale
  i18n.supportedLocales = [ "en_US.UTF-8" ];                # Add supported locales

  services.xserver.xkb = {                                  # Keyboard layout configuration
    layout = "us";
    variant = "";
  };
  #console.keyMap = "us";                                   # Comment above if you want to revoke X totally, I guess?

  nixpkgs.config.allowUnfree = true;                        # Allow installation of unfree packages

  environment.systemPackages = with pkgs; [                 # System-wide packages
    vim
    wget
    fastfetch
    git
    htop
  ];

  services.openssh = { 
    enable = true;
    ports = [ 22 ];
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  #services.xserver.enable = false;
  #services.journald.extraConfig = {
  #  "SystemMaxUse" = "50M";                                # Limit journald logs to 500MB
  #};


  time.timeZone = "UTC";                                    # Set timezone (change to your desired timezone)
  #system.autoUpgrade = {
  #  enable = true;
  #  schedule = "weekly";
  #};
  system.stateVersion = "24.11";                            # Ensure compatibility with the NixOS release version
  #systemd.swap.enable = true;

}
