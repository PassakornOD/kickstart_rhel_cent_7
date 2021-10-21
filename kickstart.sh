#!/bin/bash

##======================
# define variables
##======================
EDITOR=vim
PASSWD=/etc/passwd
RED='\033[0;41;30m'
STD='\033[0;0;39m'

##======================
# user defined function
##======================
pause(){
    read -p "Press [Enter] key to continue..." fackEnterKey
}

option_one(){
    read -p "Please chose mountpoint for repository : " mountpoint
    read -p "Please enter host ip : " ip_host

    oct_1=`echo ${ip_host} |cut -d "." -f 1` 
    oct_2=`echo ${ip_host} |cut -d "." -f 2` 
    oct_3=`echo ${ip_host} |cut -d "." -f 3` 
    oct_4=`echo ${ip_host} |cut -d "." -f 4` 

    ip_subnet="${oct_1}.${oct_2}.${oct_3}.0"
    ip_start="${oct_1}.${oct_2}.${oct_3}.200"
    ip_end="${oct_1}.${oct_2}.${oct_3}.220"
    ip_gw="${oct_1}.${oct_2}.${oct_3}.1"


    echo -e "Copy ISO to localhost...."
    Mount_iso $mountpoint

    echo -e "Configure repository...."
    ConfigureRepofile $mountpoint

    echo -e "install package..."
    echo -e "- install dhcpd...."
    InstallPackage dhcp
    echo -e "- install tftp server...."
    InstallPackage tftp-server

    InstallPackage syslinux


    protocol="ftp"
    repo=${protocol}://${ip_host}/pub${mountpoint}/
    ks=${protocol}://${ip_host}/pub${mountpoint}${mountpoint}_gui.cfg
    path_proto=/var/ftp/pub${mountpoint}
    pg=vsftpd

    echo -e "- install ${protocol}...."
    InstallPackage $pg
    echo -e "Confgiure PXE Boot"
    PXEboot $mountpoint $path_proto
    ConfigPxelinux $mountpoint $repo $ks
    ConfigEFI $mountpoint $repo $ks
    echo -e "Confgiure dhcp server"
    ConfigDHCP $ip_host $ip_subnet $ip_gw $ip_start $ip_end

    Copy_iso $mountpoint $path_proto

    echo -e "start and enable service"
    StartService dhcpd.service
    StartService tftp.service
    StartService $pg
    echo -e "allow firewall"
    AllowFirewall
    pause
}

change_repos(){

    read -p "Please chose mountpoint for repository : " mountpoint

    echo -e "Copy ISO to localhost...."
    Mount_iso $mountpoint

    protocol="ftp"
    repo=${protocol}://${ip_host}/pub${mountpoint}/
    ks=${protocol}://${ip_host}/pub${mountpoint}${mountpoint}_gui.cfg
    path_proto=/var/ftp/pub${mountpoint}
    pg=vsftpd

    PXEboot $mountpoint $path_proto
    ConfigPxelinux $mountpoint $repo $ks
    ConfigEFI $mountpoint $repo $ks



}
one(){
    echo "one() called"
    pause
}
two(){
    echo "two() called"
    pause
}
three(){
    echo "three() called"
    pause
}

# function to display menus
show_meuns(){
    clear
    echo "#######################################"
    echo "          KICKSTART MENU               "
    echo "#######################################"
    echo "1. Install and setup PXEBOOT server"
    echo "2. change protocol transfer(http/ftp)"
    echo "3. Add PXEBOOT server"
    echo "4. Exit"
    
}

read_oper(){
    local choice
    read -p "Enter choice [ 1 -4 ] " choice
    case $choice in 
        1) option_one ;;
        2) two ;;
        3) three ;;
        4) exit 0;;
        *) echo -e "${RED}Error ...${STD}" && sleep 2
    esac
}


##############################################################################################################################
##                                                                                                                          ##
##                                               function for PXE boot                                                      ##
##                                                                                                                          ##
##############################################################################################################################

 #Copy CentOS/RHEL ISO
Mount_iso(){
    
    mountpoint=$1
    if [ `mount|grep iso|wc -l` == 1 ]
    then
        umount $(mount|grep iso |awk '{print $1}')
    fi
    if [ -d ${mountpoint} ]
    then
        rm -rf $mountpoint
    fi
       

    mkdir $mountpoint
    mount /dev/sr0 $mountpoint
}

ConfigureRepofile(){
    mountpoint=$1
    #Clear repo configure
    echo -e "clear exist repo config"
    mv /etc/yum.repos.d/*.repo /tmp/
    echo -e "clear complete\n\n"

    echo -e "disable gpgcheck in /etc/yum.conf"
    if [ `grep gpgcheck /etc/yum.conf |awk -F= '{print $2}'` != '0' ]
    then

        GPG=`grep gpgcheck /etc/yum.conf`
        sed -i "s/${GPG}/gpgcheck=0/g" /etc/yum.conf
        GPG1=`grep gpgcheck /etc/yum.conf`
        echo "Change parameter from ${GPG} to ${GPG1}"
    echo -e "************************************************\n"
    fi

    repo_id=`echo ${mountpoint}|cut -d "/" -f 2`
    cat >> /etc/yum.repos.d${mountpoint}.repo << EOF
[${repo_id}]
name=repo_${repo_id}
baseurl=file://${mountpoint}
enabled=1
gpgcheck=0
EOF
  yum clear all 
  yum repolist
}

#Configure repository
configure_repo(){
    mountpoint=$1
    #Clear repo configure
    echo -e "clear exist repo config"
    mv /etc/yum.repos.d/*.repo /tmp
    echo -e "clear complete\n\n"

    echo -e "disable gpgcheck in /etc/yum.conf"
    if [ `grep gpgcheck /etc/yum.conf |awk -F= '{print $2}'` != '0' ]
    then

        GPG=`grep gpgcheck /etc/yum.conf`
        sed -i "s/${GPG}/gpgcheck=0/g" /etc/yum.conf
        GPG1=`grep gpgcheck /etc/yum.conf`
        echo "Change parameter from ${GPG} to ${GPG1}"
    echo -e "************************************************\n"
    fi

    echo -e "configure repo"
    yum-config-manager --add-repo=file://${mountpoint}
    yum clear all
}

#install package
InstallPackage(){
    rpm=$1
    yum install -y $rpm
}

PXEboot(){
    mountpoint=$1
    path_proto=$2
    
    if [[ ( -d /var/lib/tftpboot/pxelinux.cfg ) && (-d /var/lib/tftpboot/networkboot ) ]];
    then
        rm -rf /var/lib/tftpboot/pxelinux.cfg
        rm -rf /var/lib/tftpboot/networkboot/*
    fi
    # create directory for boot label
    mkdir /var/lib/tftpboot/pxelinux.cfg
    # create directory networkboot
    mkdir -p /var/lib/tftpboot/networkboot${mountpoint}
    # create link source media
    mkdir -p $path_proto


    #Copy file pxe to tftpboot
    cp -v /usr/share/syslinux/pxelinux.0 /var/lib/tftpboot/
    cp -v /usr/share/syslinux/menu.c32 /var/lib/tftpboot/
    cp -v /usr/share/syslinux/mboot.c32 /var/lib/tftpboot/
    cp -v /usr/share/syslinux/chain.c32 /var/lib/tftpboot/

    # Copy boot image file
    cp ${mountpoint}/images/pxeboot/{initrd.img,vmlinuz} /var/lib/tftpboot/networkboot${mountpoint}

    #bootloader of UEFI
    cp ${mountpoint}/EFI/BOOT/grubx64.efi /var/lib/tftpboot

}

#Copy ISO to server
Copy_iso(){
    mount=$1
    path_proto=$2

    echo "Start copy content media"
    # Copy contents of ISO file
    cp -rpf ${mount}/* $path_proto
    echo "Done...."
}

# start and enable service
StartService(){
    services=$1
    systemctl start $services
    systemctl enable $services
}

AllowFirewall() {
  # Allow dhcp and proxy dhcp service
  firewall-cmd --permanent --add-service={dhcp,proxy-dhcp}

  # Allow tftp server service
  firewall-cmd --permanent --add-service=tftp

  # Allow FTP service
  firewall-cmd --permanent --add-service=ftp


  # reload rule firewall
  firewall-cmd --reload
}

#############################################################################################

#############################################################################################
ConfigDHCP() {
  ip_host=$1
  ip_subnet=$2
  ip_gw=$3
  ip_start=$4
  ip_end=$5

  # Configure dhcp file
  cat > /etc/dhcp/dhcpd.conf << EOF
  option space pxelinux;
  option pxelinux.magic code 208 = string;
  option pxelinux.configfile code 209 = text;
  option pxelinux.pathprefix code 210 = text;
  option pxelinux.reboottime code 211 = unsigned integer 32;
  option architecture-type code 93 = unsigned integer 16;

  subnet ${ip_subnet} netmask 255.255.255.0 {
  	option routers ${ip_gw};
  	range ${ip_start} ${ip_end};

  	class "pxeclients" {
  	  match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
  	  next-server ${ip_host};

  	  if option architecture-type = 00:07 {
  	    filename "grubx64.efi";
  	    } else {
  	    filename "pxelinux.0";
  	  }
  	}
  }
EOF
}

ConfigPxelinux() {
  mountpoint=$1
  repo=$2
  ks=$3

  ##############################Configure pxelinux file########################
  cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
    default menu.c32
    prompt 0
    timeout 60
    menu title PXE boot Menu
    label 1^) Install OS Manual
    kernel /networkboot${mountpoint}/vmlinuz
    append initrd=/networkboot${mountpoint}/initrd.img inst.repo=${repo}

    label 2^) Install OS Kickstart
    kernel /networkboot${mountpoint}/vmlinuz
    append initrd=/networkboot${mountpoint}/initrd.img inst.repo=${repo} ks=${ks}

    label ^3) Install CentOS 8 x64 with Local Repo using VNC
    kernel ${mountpoint}/vmlinuz
    append  initrd=${mountpoint}/initrd.img inst.ks=${ks} inst.vnc inst.vncpassword=password
EOF
}

ConfigEFI() {
  mountpoint=$1
  repo=$2
  ks=$3
  ##############################Configure EFI file########################
  cat > /var/lib/tftpboot/grub.cfg << EOF
    set timeout=20

    menuentry 'Install OS Manual' {
        linuxefi /networkboot${mountpoint}/vmlinuz inst.repo=${repo}
        initrdefi /networkboot${mountpoint}/initrd.img
    }

    menuentry 'Install OS Kickstart' {
        linuxefi /networkboot${mountpoint}/vmlinuz inst.repo=${repo} inst.ks=${ks}
        initrdefi /networkboot${mountpoint}/initrd.img
    }

    menuentry 'Install OS Kickstart with VNC' {
        linuxefi ${mountpoint}/vmlinuz inst.ks=${ks} inst.vnc inst.vncpassword=password 
        initrdefi ${mountpoint}/initrd.img
    }
EOF
}   

##############################################################################################################################
##                                                                                                                          ##
##                                               Main for PXE boot                                                           ##
##                                                                                                                          ##
##############################################################################################################################

trap '' SIGINT SIGQUIT SIGTSTP

while true
do
    show_meuns
    read_oper
done