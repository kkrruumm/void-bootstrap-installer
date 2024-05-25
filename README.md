# void-bootstrap-installer
This is a very minimal script to bootstrap a minimal Void Linux system from a rootfs tarball.

This was originally written with the intention of deploying Void on Hetzner Cloud systems. 

This installer does little to no error handling or input validation, and only has around enough features to deploy a functional install.

# Instructions
```
Download your target Void rootfs tarball, and run the following:

git clone https://github.com/kkrruumm/void-bootstrap-installer
cd void-bootstrap-installer
chmod +x installer.sh
sudo ./installer.sh /path/to/root/tarball.tar.xz
Follow on-screen steps
Done.
```
# Notes
The currently supported features of this installer include:

```
-Basic disk configuration
--Option to enable or disable swap and pick the swap LV size
--Option to choose between xfs and ext4 filesystems

-Option to enable SSH
--Option to allow SSH access from the root user

-Basic user creation and configuration
-Option to change the system hostname
-Option to choose between doas and sudo
-Option to configure your timezone
```

In the case of installing on Hetzner Cloud systems, this script can be ran from Hetzners rescue system.

Having abundant features is not the point of this installer, do see my other Void installer for that.

If you have any issues, file them in the issues tracker on this page.

If you would like to request a feature, you may also file them in the issues tracker on this page, however, features that stray from the minimal nature of this will not be considered.

Pull requests to add features or fix problems are also very welcome.

If you have found this useful, do leave a star on the repository!
