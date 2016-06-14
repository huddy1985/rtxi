#! /bin/bash

#
# The Real-Time eXperiment Interface (RTXI)
# Copyright (C) 2011 Georgia Institute of Technology, University of Utah, Weill Cornell Medical College
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#	Created by Yogi Patel <yapatel@gatech.edu> 2014.1.31
#

if ! id | grep -q root; then
  echo "Must run script as root; try again with sudo ./install_rt_kernel.sh"
  exit
fi

# Export environment variables
echo  "----->Setting up variables"
export linux_version=4.1.18
export linux_tree=/opt/linux-$linux_version

export xenomai_version=3.0.2
export xenomai_root=/opt/xenomai-$xenomai_version

export scripts_dir=`pwd`

export build_root=/opt/build
export opt=/opt

rm -rf $build_root
rm -rf $linux_tree
rm -rf $xenomai_root
mkdir $build_root

if [ $? -eq 0 ]; then
	echo  "----->Environment configuration complete"
else
	echo  "----->Environment configuration failed"
	exit
fi

# Download and extract a vanilla Linux kernel and Xenomai 
echo  "----->Downloading Linux kernel"
cd $opt
if [[ "$linux_version" =~ "3." ]]; then 
	wget --no-check-certificate https://www.kernel.org/pub/linux/kernel/v3.x/linux-$linux_version.tar.xz
elif [[ "$linux_version" =~ "4." ]]; then
	wget --no-check-certificate https://www.kernel.org/pub/linux/kernel/v4.x/linux-$linux_version.tar.xz
else
	echo "Kernel specified in the \$linux_version variable needs to be 3.x or 4.x"
	exit 1
fi

tar xf linux-$linux_version.tar.xz

echo  "----->Downloading Xenomai"
wget --no-check-certificate http://xenomai.org/downloads/xenomai/stable/xenomai-$xenomai_version.tar.bz2
tar xf xenomai-$xenomai_version.tar.bz2

if [ $? -eq 0 ]; then
	echo  "----->Downloads complete"
else
	echo  "----->Downloads failed"
	exit
fi

# Patch kernel
echo  "----->Patching kernel"
cd $linux_tree
$xenomai_root/scripts/prepare-kernel.sh --arch=x86 --adeos=$xenomai_root/kernel/cobalt/arch/x86/patches/ipipe-core-$linux_version-x86-?.patch --linux=$linux_tree
yes "" | make localmodconfig
make menuconfig

if [ $? -eq 0 ]; then
	echo  "----->Patching complete"
else
	echo  "----->Patching failed"
	exit
fi

# Compile kernel
echo  "----->Compiling kernel"
cd $linux_tree
export CONCURRENCY_LEVEL=$(nproc)
fakeroot make-kpkg --initrd --append-to-version=-xenomai-$xenomai_version --revision $(date +%Y%m%d) kernel-image kernel-headers modules

if [ $? -eq 0 ]; then
	echo  "----->Kernel compilation complete."
else
	echo  "----->Kernel compilation failed."
	exit
fi

# Install compiled kernel
echo  "----->Installing compiled kernel"
cd $opt
sudo dpkg -i linux-image-$linux_version-xenomai-$xenomai_version*.deb
sudo dpkg -i linux-headers-$linux_version-xenomai-$xenomai_version*.deb

if [ $? -eq 0 ]; then
	echo  "----->Kernel installation complete"
else
	echo  "----->Kernel installation failed"
	exit
fi

# Update
echo  "----->Updating boot loader about the new kernel"
cd $linux_tree
sudo update-initramfs -u -k all
sudo update-grub

if [ $? -eq 0 ]; then
	echo  "----->Boot loader update complete"
else
	echo  "----->Boot loader update failed"
	exit
fi

# Install Xenomai libraries
echo  "----->Installing user libraries"
if [ -d "/usr/xenomai" ]; then
	mv /usr/xenomai /usr/xenomai-$(date +%F_%T)
fi
cd $build_root
$xenomai_root/configure --with-core=cobalt --enable-pshared --enable-smp --enable-x86-vsyscall --enable-dlopen-libs
make -s
sudo make install

if [ $? -eq 0 ]; then
	echo  "----->User library installation complete"
else
	echo  "----->User library installation failed"
	exit
fi

# Setting up user permissions. You may want to revisit this section, as the 
# user that runs this script is technically root. 
echo  "----->Setting up user/group"
sudo groupadd xenomai
sudo usermod -aG xenomai `whoami`

if [ $? -eq 0 ]; then
	echo  "----->Group setup complete"
else
	echo  "----->Group setup failed"
	exit
fi

# (Tell them to) restart
echo  "----->Kernel patch complete."
echo  "----->Reboot to boot into RT kernel."
