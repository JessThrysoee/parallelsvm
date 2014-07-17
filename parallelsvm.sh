#!/bin/bash -e
#
# Unattended Kickstart install of minimal CentOS server in Parallels VM.
#
# Parallels Tools is installed.
#
# Zeroconf (a.k.a. rendezvous, a.k.a. bonjour) is enabled for easy ssh access on the
# .local domain, e.g. with HOSTNAME=centos it is immediately possible to login
# from OS X with 'ssh centos.local -l root'.
#

#-----------------------------------------------------------------------------------------------

##
##
##
function main() {
   local SCRIPT_NAME=${0##*/}
   local PARALLELSVM_RC=parallelsvm.rc

   cd $PWD

   # create rc file
   if [ "$1" = "init" ]
   then
      create_parallelsvm_rc
      exit
   fi
   source_parallelsvm_rc

   init_env
   create_workspace
   trap delete_workspace EXIT

   # create VM
   if [ "$1" = "create" ]
   then
      if vm_exists
      then
         start_vm

      elif vm_template_exists
      then
         create_vm_from_template

      else
         create_vm_from_iso
      fi

   # create template of VM
   elif [ "$1" = "template" ]
   then
      clone_vm_to_template "$2"

   # start VM
   elif [ "$1" = "start" ]
   then
      start_vm

   # stop VM
   elif [ "$1" = "stop" ]
   then
      stop_vm

   # kill VM
   elif [ "$1" = "kill" ]
   then
      kill_vm

   # delete VM
   elif [ "$1" = "delete" ]
   then
      delete_vm

   # bash shell in VM
   elif [ "$1" = "shell" ]
   then
      shell_vm

   # umount ISO files from VM
   elif [ "$1" = "umount" ]
   then
      umount_isos

   # cleanup ISO files
   elif [ "$1" = "cleanup" ]
   then
      delete_isos

   else
      echo "usage: $SCRIPT_NAME ACTION [OPTIONS]"
      echo ""
      echo "       ACTIONS:"
      echo "                init"
      echo "                create"
      echo "                template [--force]"
      echo ""
      echo "                start"
      echo "                stop"
      echo "                kill"
      echo "                delete"
      echo "                shell"
      echo ""
      echo "                umount"
      echo "                cleanup"
   fi
}

##
##
##
function source_parallelsvm_rc() {

   if [ ! -e "$PARALLELSVM_RC" ]
   then
      echo "$PARALLELSVM_RC not found: call '$SCRIPT_NAME init' or change to dir containing $PARALLELSVM_RC"
      exit
   fi

   . "$PARALLELSVM_RC"
}

##
##
##
function create_parallelsvm_rc() {

   cat > "$PARALLELSVM_RC" <<"EOF"
HOSTNAME=centos
VM_NAME="$HOSTNAME (CentOS 7)"
VM_CPUS=1
VM_MEMSIZE=512

# find mirror at "http://mirror.centos.org/centos/7/isos/x86_64/CentOS-7.0-1406-x86_64-Minimal.iso"
## TODO beta iso (EPEL repo is also beta)
DISTRO_ISO_URL="http://buildlogs.centos.org/centos/7/isos/x86_64/CentOS-7.0-1406-x86_64-Minimal.iso"

PARALLELS_TOOLS_ISO="/Applications/Parallels Desktop.app/Contents/Resources/Tools/prl-tools-lin.iso"
EOF
}

##
##
##
function create_vm() {
   prlctl create "$VM_NAME" --ostype linux --dst $VM_DIR
   prlctl set    "$VM_NAME" --on-shutdown close
   prlctl set    "$VM_NAME" --cpus $VM_CPUS
   prlctl set    "$VM_NAME" --memsize $VM_MEMSIZE

   prlctl set    "$VM_NAME" --device-del net0
   prlctl set    "$VM_NAME" --device-del cdrom0

   prlctl set    "$VM_NAME" --device-add cdrom --enable --image "$DISTRO_ISO"
   prlctl set    "$VM_NAME" --device-add cdrom --enable --image "$KICKSTART_ISO"
   prlctl set    "$VM_NAME" --device-add cdrom --enable --image "$PARALLELS_TOOLS_ISO"
   prlctl set    "$VM_NAME" --device-add net   --enable --type bridged
   prlctl start  "$VM_NAME"
}

##
##
##
function vm_exists() {
   prlctl list "$VM_TEMPLATE_NAME" > /dev/null 2>&1
}

##
##
##
function vm_template_exists() {
   test -e "$VM_TEMPLATE_PATH"
}

##
##
##
function create_vm_from_iso() {
   is_parallels_sdk_installed

   fetch_distro_iso
   ## TODO no checksums for beta iso
   #checksum_distro_iso

   make_kickstart_cfg
   make_kickstart_iso

   create_vm

   make_parallels_send_kickstart_boot_option
   call_parallels_send_kickstart_boot_option

   kickstart_wait
   umount_isos_message
}

##
##
##
function create_vm_from_template() {
   prlctl register "$VM_TEMPLATE_PATH" \
      && prlctl create "$VM_NAME" --ostemplate "$VM_TEMPLATE_NAME" --dst "$VM_DIR"
   prlctl unregister "$VM_TEMPLATE_NAME"
}

##
##
##
function clone_vm_to_template() {
   if [ "$1" = "--force" ]
   then
      rm -rf "$VM_TEMPLATE_PATH"
   fi
   prlctl clone "$VM_NAME" --name "$VM_TEMPLATE_NAME" --template --dst "$VM_TEMPLATE_DIR"
   prlctl unregister "$VM_TEMPLATE_NAME"
}

##
##
##
function start_vm() {
   prlctl start "$VM_NAME"
}

##
##
##
function stop_vm() {
   prlctl stop "$VM_NAME"
}

##
##
##
function kill_vm() {
   prlctl stop "$VM_NAME" --kill
}

##
##
##
function delete_vm() {
   kill_vm
   prlctl delete "$VM_NAME"
}

##
##
##
function kickstart_wait() {
   printf "\nKickstarting "
   while ! prlctl exec "$VM_NAME" true 2> /dev/null
   do
      printf "."
      sleep 10
   done
   printf "\n"
}

##
##
##
function shell_vm() {
   prlctl enter "$VM_NAME"
}

##
##
##
function umount_isos() {
   prlctl set "$VM_NAME" --device-set cdrom0 --disconnect
   prlctl set "$VM_NAME" --device-del cdrom1
   prlctl set "$VM_NAME" --device-del cdrom2
}

##
##
##
function umount_isos_message() {
   printf "\n%s %s\n\n\t%s\n\n"\
      "Optional:"\
      "Disconnect ISOs and remove extra cdrom devices used by the installation by stopping the VM and running:"\
      "$SCRIPT_NAME --umount"
}

##
##
##
function init_env() {
   VM_DIR="$PWD/.vm"

   VM_TEMPLATE_DIR="$PWD/.vm_template"
   VM_TEMPLATE_NAME="${VM_NAME}_template"
   VM_TEMPLATE_PATH="${VM_TEMPLATE_DIR}/${VM_TEMPLATE_NAME}.pvm"

   TMP_DIR="$PWD/.tmp"
   KICKSTART_DIR="$TMP_DIR/kickstart"

   ISO_DIR="$PWD/.iso"
   DISTRO_ISO="$ISO_DIR/${DISTRO_ISO_URL##*/}"
   KICKSTART_ISO="$ISO_DIR/kickstart.iso"
}

##
##
##
function create_workspace() {
   mkdir -p "$VM_DIR"
   mkdir -p "$VM_TEMPLATE_DIR"

   mkdir -p "$TMP_DIR"

   mkdir -p "$ISO_DIR"
   mkdir -p "$KICKSTART_DIR"
}

##
##
##
function delete_workspace() {
   rm -rf "$TMP_DIR"
}

##
##
##
function delete_isos() {
   rm -f "$DISTRO_ISO"
   rm -f "$KICKSTART_ISO"
}

##
##
##
function fetch_distro_iso() {
   if [ ! -e "$DISTRO_ISO" ]
   then
      curl -o "$DISTRO_ISO" "$DISTRO_ISO_URL"
   fi
}

##
##
##
function checksum_distro_iso() {
   local mirror_sum=$(curl -s ${DISTRO_ISO_URL%/*}/md5sum.txt |\
      grep ${DISTRO_ISO_URL##*/} | awk '{print $1}')

   local local_sum=$(md5 -q $DISTRO_ISO)

   if [ "$mirror_sum" != "$local_sum" ]
   then
      echo "checksum error -- try cleaning up with '$SCRIPT_NAME --cleanup'"
      exit
   fi
}

##
##
##
function is_parallels_sdk_installed() {
   if ! python -c 'import prlsdkapi' 2> /dev/null
   then
      echo "'Parallels Virtualization SDK' is not installed. Get it from http://www.parallels.com/downloads/desktop/"
      exit
   fi
}

##
##
##
function call_parallels_send_kickstart_boot_option() {
    python $TMP_DIR/parallels_send_kickstart_boot_option "$VM_NAME" "I"$'\t'" ks=cdrom:/dev/sr1:/ks.cfg"
}

##
##
##
function make_parallels_send_kickstart_boot_option() {
   cat > "$TMP_DIR/parallels_send_kickstart_boot_option" <<EOF
#!/usr/bin/env python

import sys
import prlsdkapi

if len(sys.argv) != 3:
   print "Usage  : parallels_send_kickstart_boot_option '<VM_NAME>' '<KICKSTART_BOOT_OPTION>'"
   print "Example: parallels_send_kickstart_boot_option 'CentOS VM' 'ks=http://127.0.0.1:1234/ks.cfg'"
   exit()

vm_name=sys.argv[1]
kickstart_boot_option = sys.argv[2]

prlsdk = prlsdkapi.prlsdk
consts = prlsdkapi.prlsdk.consts
#print consts.ScanCodesList

prlsdk.InitializeSDK(consts.PAM_DESKTOP_MAC)
server = prlsdkapi.Server()
login_job=server.login_local()
login_job.wait()

vm_list_job = server.get_vm_list()
result= vm_list_job.wait()

vm_list = [result.get_param_by_index(i) for i in range(result.get_params_count())]
vm = [vm for vm in vm_list if vm.get_name() == vm_name]

if not vm:
   vm_names = [vm.get_name() for vm in vm_list]
   print "ERROR: Failed to find VM with name '%s' in:" % vm_name
   for name in vm_names:
      print "'" + name + "'"
   exit()

vm = vm[0]

vm_io = prlsdkapi.VmIO()
try:
     vm_io.connect_to_vm(vm).wait()
except prlsdkapi.PrlSDKError, e:
     print "ERROR: %s" % e
     exit()

press = consts.PKE_PRESS
release = consts.PKE_RELEASE
shift_left = consts.ScanCodesList['SHIFT_LEFT']
enter = consts.ScanCodesList['ENTER']
timeout = 5

for c in kickstart_boot_option:
   shift = False

   if c == " ":
      c = consts.ScanCodesList['SPACE']
   elif c == "\t":
      c = consts.ScanCodesList['TAB']
   elif c == "/":
      c = consts.ScanCodesList['SLASH']
   elif c == "=":
      c = consts.ScanCodesList['PLUS']
   elif c == ".":
      c = consts.ScanCodesList['GREATER']
   elif c == ":":
      shift = True
      c = consts.ScanCodesList['COLON']
   else:
      c = consts.ScanCodesList[c.upper()]

   if shift:
      vm_io.send_key_event(vm, shift_left, press, timeout)
   vm_io.send_key_event(vm, c, press, timeout)
   vm_io.send_key_event(vm, c, release, timeout)
   if shift:
      vm_io.send_key_event(vm, shift_left, release, timeout)

vm_io.send_key_event(vm, enter, press, timeout)
vm_io.send_key_event(vm, enter, release, timeout)

vm_io.disconnect_from_vm(vm)
server.logoff()
prlsdkapi.deinit_sdk
EOF
}

##
##
##
function make_kickstart_iso() {
   rm -f "$KICKSTART_ISO"
   hdiutil makehybrid -quiet -iso -joliet -o "$KICKSTART_ISO" "$KICKSTART_DIR"
}

##
##
##
function make_kickstart_cfg() {
   cat > "$KICKSTART_DIR/ks.cfg" <<EOF
cmdline
skipx
install
cdrom

lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC

network --activate --onboot yes --device eth0 --bootproto dhcp --noipv6 --hostname $HOSTNAME

rootpw  --plaintext newroot
authconfig --enableshadow --passalgo=sha512

firewall --enabled --service=ssh,mdns,http,https --port=8080:tcp,8443:tcp
selinux --disabled

bootloader --location=mbr
zerombr
clearpart --all --initlabel
autopart

## TODO beta repo
repo --name=epel --baseurl=http://dl.fedoraproject.org/pub/epel/beta/7/x86_64/
#repo --name=epel --baseurl=http://dl.fedoraproject.org/pub/epel/7/x86_64/

reboot

%packages --nobase
@core
epel-release
%end

%post
exec < /dev/tty3 > /dev/tty3
chvt 3
echo
echo "################################"
echo "# Running Post Configuration   #"
echo "################################"
(

echo "Installing Parallels Tools..."
mount -r -o exec /dev/sr2 /mnt
/mnt/install --install-unattended-with-deps --progress
umount /mnt
echo "Note: Parallels Tools can be updated by running 'ptiagent-cmd --info'"

yum install -y\
   net-tools\
   bash-completion\
   git\
   vim\
   man\
   avahi\
   avahi-tools\
   nss-mdns\
   avahi-compat-libdns_sd\
   docker-io

systemctl enable docker || true

yum upgrade -y

) 2>&1 | /usr/bin/tee /tmp/post_install.log
chvt 1
%end

EOF
}

main "$@"


# Copyright (c) 2014, Jess Thrysoee
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation and/or
# other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
