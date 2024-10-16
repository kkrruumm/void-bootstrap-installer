#!/bin/bash

failure() {
    echo "Command has failed. Installation halted."
    exit 1
}

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "x86_64" ]; then
    echo "Unknown CPU architecture. Cannot continue."
    exit 1
fi

if [ -z "$1" ] || ! echo "$1" | grep ".tar.xz" ; then
    echo "Expected Void Linux tarball as an argument. Did you forget to provide the path to your Void tarball? Cannot continue."
    echo "Expected command: ./installer.sh /path/to/void-tarball.tar.xz"
    exit 1
fi

cat <<-__EOF__

Enter the disk you would like to install Void Linux to:

Example: sda

$(lsblk -d -o NAME,SIZE,TYPE -e7)
__EOF__

read targetDisk

targetDisk="/dev/$targetDisk"

cat <<__EOF__

Enter the filesystem you would like to use for the root partition:

Valid options: 'ext4' 'xfs'
__EOF__

read rootFilesystem

cat <<__EOF__

Would you like to have a swap partition? (y/n)
__EOF__

read swapPrompt

if [ "$swapPrompt" == "Y" ] || [ "$swapPrompt" == "y" ]; then
    cat <<__EOF__

How large would you like your swap partition to be?

Example: 4G
__EOF__
    
    read swapSize
fi

cat <<__EOF__

Enter the privilege escalation tool you would like to use: 

Valid options: 'doas' 'sudo'
__EOF__

read suTool

cat <<__EOF__

Enter your timezone:

Example: Europe/Berlin
__EOF__

read timezonePrompt

cat <<__EOF__

If you would like to create a non-root user, enter your username here. You will be prompted for your password later.

Otherwise, enter 'skip'
__EOF__

read createUser

if [ "$createUser" != "skip" ]; then
    cat <<__EOF__

Should the new user be a superuser? (y/n)
__EOF__

    read superUserPrompt
fi

cat <<__EOF__

Would you like to enable SSH? (y/n)
__EOF__

read sshPrompt

if [ "$sshPrompt" == "Y" ] || [ "$sshPrompt" == "y" ]; then
    cat <<__EOF__

Would you like to enable root SSH login? (y/n)
__EOF__

    read rootSSHPrompt

    cat <<__EOF__

Would you like to provide a public SSH key to log in with instead of using a password? (y/n)
__EOF__

read provideSSHKeyPrompt

    if [ "$provideSSHKeyPrompt" == "Y" ] || [ "$provideSSHKeyPrompt" == "y" ]; then
        cat <<__EOF__

Please paste in the contents of your PUBLIC ssh key (.pub file):
__EOF__
        
        read providedSSHKey
    fi
fi

cat <<__EOF__

Enter your hostname:
__EOF__

read hostnameInput

cat <<__EOF__

WARNING: The data on the chosen disk $targetDisk will be destroyed if you proceed.

Confirm your installation options:

Disk: $targetDisk
Root filesystem: $rootFilesystem
Create swap: $swapPrompt
Swap size: $swapSize
SU choice: $suTool
Timezone: $timezonePrompt
Create user: $createUser
Superuser for created user: $superUserPrompt
Enable SSH: $sshPrompt
Enable root SSH: $rootSSHPrompt
Provided SSH key?: $provideSSHKeyPrompt
Hostname: $hostnameInput

If all looks good, you may enter 'install' to proceed.
Otherwise, you may enter 'exit' to close the installer.

__EOF__

read confirmationPrompt

if [ "$confirmationPrompt" == "install" ]; then
   
    # We need to wipe out any existing VG on the chosen disk before the installer can continue, this is somewhat scuffed but works.
    deviceVG=$(pvdisplay "$targetDisk"* | grep "VG Name" | while read c1 c2; do echo $c2; done | sed 's/Name //g')

    if [ -z "$deviceVG" ]; then
        echo "Existing VG not found, no need to do anything..."
    else
        echo "DeviceVG is $deviceVG"
        echo "Existing VG found..."
        echo "Wiping out existing VG..."

        vgchange -a n "$deviceVG" || failure
        vgremove "$deviceVG" || failure
    fi

    wipefs -a "$targetDisk" || failure 

    # Create partitions
    parted "$targetDisk" mklabel gpt || failure
    parted "$targetDisk" mkpart primary 0% 500M --script || failure
    parted "$targetDisk" set 1 esp on --script || failure
    parted "$targetDisk" mkpart primary 500M 100% --script || failure

    # Set up LVM and LVM volumes
    pvcreate "$targetDisk"2 || failure
    vgcreate void "$targetDisk"2 || failure

    if [ "$swapPrompt" == "Y" ] || [ "$swapPrompt" == "y" ]; then
        lvcreate --name swap -L "$swapSize" void || failure
        mkswap /dev/void/swap || failure
    fi

    lvcreate --name root -l 100%FREE void || failure

    # Format partitions
    mkfs.vfat "$targetDisk"1 || failure
    mkfs."$rootFilesystem" "/dev/void/root" || failure

    # Mount root partition
    mount "/dev/void/root" /mnt || failure

    # Extract rootfs tarball to root partition
    tar xvf "$1" -C /mnt || failure
    
    # Mount ESP partition
    mkdir /mnt/boot/efi || failure
    mount "$targetDisk"1 /mnt/boot/efi || failure

    # Mount other important directories
    for dir in dev proc sys run; do mkdir -p /mnt/$dir ; mount --rbind /$dir /mnt/$dir ; mount --make-rslave /mnt/$dir ; done || failure

    # Copy resolv information to new system for internetz
    cp /etc/resolv.conf /mnt/etc/resolv.conf || failure

    # Symlink for timezone
    chroot /mnt /bin/bash -c "ln -s /usr/share/zoneinfo/$timezonePrompt /etc/localtime" || failure

    # Update system and install base packages
    chroot /mnt /bin/bash -c "xbps-install -Suy xbps base-system lvm2 linux" || failure

    # Add ESP to fstab
    partVar=$(blkid -o value -s UUID "$targetDisk"1)
    echo "UUID=$partVar     /boot/efi   vfat    defaults    0   0" >> /mnt/etc/fstab || failure

    # Install GRUB for target architecture
    if [ "$(uname -m)" == "x86_64" ]; then
        chroot /mnt /bin/bash -c "xbps-install -Suy grub-x86_64-efi" || failure
    elif [ "$(uname -m)" == "aarch64" ]; then
        chroot /mnt /bin/bash -c "xbps-install -Suy grub-arm64-efi" || failure
    fi

    # Install GRUB
    chroot /mnt /bin/bash -c "grub-install --efi-directory=/boot/efi" || failure

    # Reconfigure packages
    chroot /mnt /bin/bash -c "xbps-reconfigure -fa" || failure

    # Enable dhcpcd
    chroot /mnt /bin/bash -c "ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default" || failure

    # Create user
    if [ "$createUser" != "skip" ]; then
        chroot /mnt /bin/bash -c "useradd $createUser" || failure
        if [ "$superUserPrompt" == "Y" ] || [ "$superUserPrompt" == "y" ]; then
            chroot /mnt /bin/bash -c "usermod -aG wheel $createUser" || failure
        fi
        echo "Set your password for the user $createUser:"
        chroot /mnt /bin/bash -c "passwd $createUser" || failure
    fi

    echo "Set your root password:"
    chroot /mnt /bin/bash -c "passwd root" || failure
   
    # Remove sudo and install doas
    if [ "$suTool" == "doas" ]; then
        # Ignore dependence on sudo so we can remove it
        echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/ignore.conf || failure

        # Remove sudo
        chroot /mnt /bin/bash -c "xbps-remove -ROoy sudo" || failure
        chroot /mnt /bin/bash -c "xbps-install -Suy opendoas" || failure

        # Configure doas config, symlink to sudo for compatibility
        chroot /mnt /bin/bash -c "touch /etc/doas.conf" || failure
        chroot /mnt /bin/bash -c "chown -c root:root /etc/doas.conf" || failure
        chroot /mnt /bin/bash -c "chmod -c 0400 /etc/doas.conf" || failure
        chroot /mnt /bin/bash -c "ln -s $(which doas) /usr/bin/sudo" || failure
    fi

    if [ "$swapPrompt" == "Y" ] || [ "$swapPrompt" == "y" ]; then
        echo "/dev/void/swap  swap  swap    defaults              0       0" >> /mnt/etc/fstab || failure
    fi

    if [ "$superUserPrompt" == "Y" ] || [ "$superUserPrompt" == "y" ]; then
        if [ "$suTool" == "sudo" ]; then
            chroot /mnt /bin/bash -c "sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers" || failure
        elif [ "$suTool" == "doas" ]; then
            echo "permit :wheel" >> /mnt/etc/doas.conf || failure
        fi
    fi

    # Enable SSH
    if [ "$sshPrompt" == "Y" ] || [ "$sshPrompt" == "y" ]; then
        chroot /mnt /bin/bash -c "xbps-install -Suy openssh && ln -s /etc/sv/sshd /etc/runit/runsvdir/default" || failure

        if [ "$provideSSHKeyPrompt" != "Y" ] && [ "$provideSSHKeyPrompt" != "y" ]; then
            if [ "$rootSSHPrompt" == "Y" ] || [ "$rootSSHPrompt" == "y" ]; then
                chroot /mnt /bin/bash -c "sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config" || failure
            else
                chroot /mnt /bin/bash -c "sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config" || failure
            fi
        elif [ "$provideSSHKeyPrompt" == "Y" ] || [ "$provideSSHKeyPrompt" == "y" ]; then
            chroot /mnt /bin/bash -c "sed -i -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config" || failure
            chroot /mnt /bin/bash -c "sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/g' /etc/ssh/sshd_config" || failure
            chroot /mnt /bin/bash -c "sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config" || failure

            if [ "$rootSSHPrompt" == "Y" ] || [ "$rootSSHPrompt" == "y" ]; then
                mkdir /mnt/root/.ssh || failure
                touch /mnt/root/.ssh/authorized_keys || failure

                echo "$providedSSHKey" > /mnt/root/.ssh/authorized_keys || failure
            else
                chroot /mnt /bin/bash -c "sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config" || failure
            fi

            if [ "$createUser" != "skip" ]; then
                mkdir /mnt/home/"$createUser"/.ssh || failure
                touch /mnt/home/"$createUser"/.ssh/authorized_keys || failure

                echo "$providedSSHKey" > /mnt/home/"$createUser"/.ssh/authorized_keys || failure
            fi
        fi
    fi

    # Set hostname
    echo "$hostnameInput" > /mnt/etc/hostname || failure

    cat <<__EOF__
    
Installation complete.

You may chroot into the new Void system by running 'chroot /mnt' to further configure things.
Or, reboot the system by running 'reboot'.

__EOF__

    exit 0

else
    echo "Installation aborted."
    exit 0
fi
