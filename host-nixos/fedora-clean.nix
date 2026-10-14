{ pkgs, ... }:

let
  machine = "fedora-clean";
  storageMount = "/mnt/ssd1to_linux";
  imageDir = "/mnt/ssd1to_linux/containers/fedora-clean";
  image = "${imageDir}/rootfs.img";
  rootfs = "/var/lib/machines/${machine}";

  mountRootfs = pkgs.writeShellScript "mount-${machine}-rootfs" ''
    set -eu
    ${pkgs.coreutils}/bin/mkdir -p ${imageDir} ${rootfs}
    if [ ! -f ${image} ]; then
      ${pkgs.coreutils}/bin/truncate -s 60G ${image}
      ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f -L ${machine} ${image}
      top=$(${pkgs.coreutils}/bin/mktemp -d /run/${machine}-top.XXXXXX)
      ${pkgs.util-linux}/bin/mount -o loop,rw,subvolid=5 ${image} "$top"
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$top/@root"
      ${pkgs.util-linux}/bin/umount "$top"
      ${pkgs.coreutils}/bin/rmdir "$top"
    fi
    if ! ${pkgs.util-linux}/bin/mountpoint -q ${rootfs}; then
      ${pkgs.util-linux}/bin/mount -o loop,rw,suid,dev,subvol=@root ${image} ${rootfs}
    fi
  '';

  prepareResolvConf = pkgs.writeShellScript "prepare-${machine}-resolv-conf" ''
    set -eu
    out="/run/nested-os/${machine}-resolv.conf"
    tmp="$out.tmp"
    ${pkgs.coreutils}/bin/mkdir -p /run/nested-os
    ${pkgs.gawk}/bin/awk '
      /^[[:space:]]*search[[:space:]]/ { print; next }
      /^[[:space:]]*options[[:space:]]/ { print; next }
      /^[[:space:]]*nameserver[[:space:]]+[0-9]+(\.[0-9]+){3}[[:space:]]*$/ { print; found = 1; next }
      END {
        if (!found) {
          print "nameserver 1.1.1.1"
          print "nameserver 9.9.9.9"
        }
      }
    ' /etc/resolv.conf > "$tmp"
    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$out"
  '';

  controlScript = pkgs.writeShellScript "${machine}-control" ''
    set -eu
    action="''${1:-}"
    case "$action" in
      start|stop|restart|status)
        exec ${pkgs.systemd}/bin/systemctl "$action" systemd-nspawn@${machine}.service
        ;;
      mount)
        exec ${mountRootfs}
        ;;
      *)
        echo "Usage: ${machine}-control {start|stop|restart|status|mount}" >&2
        exit 2
        ;;
    esac
  '';

  control = pkgs.writeShellScriptBin "${machine}-control" ''
    exec /etc/nested-os/${machine}-control "$@"
  '';
in
{
  environment.systemPackages = [ control ];

  environment.etc."nested-os/${machine}-control" = {
    source = controlScript;
    mode = "0755";
  };

  environment.etc."systemd/nspawn/${machine}.nspawn".text = ''
    [Exec]
    Boot=yes
    PrivateUsers=no
    Hostname=${machine}
    SystemCallFilter=@default @sandbox @mount @pkey

    [Files]
    Bind=/dev/fuse
    Bind=/dev/nvidia0
    Bind=/dev/nvidiactl
    Bind=/dev/nvidia-modeset
    Bind=/dev/nvidia-uvm
    Bind=/dev/nvidia-uvm-tools
    Bind=/dev/dri/renderD128
    Bind=/dev/dri/card1
    BindReadOnly=/run/opengl-driver
    BindReadOnly=/nix/store
    BindReadOnly=/run/user/1000/wayland-0:/run/host-wayland/wayland-parent
    Bind=/run/user/1000/pulse:/run/host-pulse
    BindReadOnly=/run/nested-os/${machine}-resolv.conf:/etc/resolv.conf

    [Network]
    Private=no
    VirtualEthernet=no
  '';

  systemd.services."${machine}-rootfs" = {
    description = "Montage de la racine Btrfs ${machine}";
    unitConfig.RequiresMountsFor = storageMount;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = mountRootfs;
    };
  };

  systemd.services."systemd-nspawn@${machine}" = {
    overrideStrategy = "asDropin";
    requires = [ "${machine}-rootfs.service" ];
    after = [ "${machine}-rootfs.service" ];
    serviceConfig = {
      ExecStartPre = prepareResolvConf;
      ExecStart = [
        ""
        "${pkgs.systemd}/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --settings=override --resolv-conf=off --machine=${machine} --directory=${rootfs}"
      ];
      DeviceAllow = [
        "/dev/fuse rwm"
        "/dev/nvidia0 rwm"
        "/dev/nvidiactl rwm"
        "/dev/nvidia-modeset rwm"
        "/dev/nvidia-uvm rwm"
        "/dev/nvidia-uvm-tools rwm"
        "/dev/dri/renderD128 rwm"
        "/dev/dri/card1 rwm"
      ];
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "myke" ];
      commands = [
        {
          command = "/etc/nested-os/${machine}-control";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
