#!/bin/bash
export LANG=C

USE_RAMDISK=true
CLEAN_ON_EXIT=false
NPROC=$1
TPROC=$2

[ -n "$NPROC" ] || NPROC=$(nproc)
[ -n "$TPROC" ] || TPROC=1
[ -n "$MNT" ] || MNT="/mnt"
[ -n "$GCC" ] || GCC="6.4.0"

cleanup() {
  sudo rm -rf $MNT/ramdisk/*
  sudo umount $MNT/ramdisk
}
if $CLEAN_ON_EXIT; then
  trap "cleanup" SIGHUP SIGINT SIGTERM EXIT
fi

echo "Install required packages"
if which apt-get &>/dev/null; then
 sudo apt-get install build-essential
elif which dnf &>/dev/null; then
 sudo dnf install -y @development-tools
else
	echo "NOTE: I don't know how to install dev tools packages here, I hope you set everything up in advance. Keep going..."
fi

if $USE_RAMDISK; then
  echo "Create compressed ramdisk"
  sudo mkdir -p $MNT/ramdisk || exit 1
  sudo modprobe zram num_devices=1 || exit 1
  echo 64G | sudo tee /sys/block/zram0/disksize || exit 1
  sudo mkfs.ext4 -q -m 0 -b 4096 -O sparse_super -L zram /dev/zram0 || exit 1
  sudo mount -o relatime,nosuid,discard /dev/zram0 $MNT/ramdisk/ || exit 1
  sudo mkdir -p $MNT/ramdisk/workdir || exit 1
  sudo chmod 777 $MNT/ramdisk/workdir || exit 1
  cp buildloop.sh $MNT/ramdisk/workdir/buildloop.sh || exit 1
  cd $MNT/ramdisk/workdir || exit 1
  mkdir tmpdir || exit 1
  export TMPDIR="$PWD/tmpdir"
fi

echo "Download GCC sources"
wget ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-$GCC/gcc-$GCC.tar.gz || exit 1

echo "Extract GCC sources"
tar -zxf gcc-$GCC.tar.gz || exit 1

echo "Download prerequisites"
(cd gcc-$GCC/ && ./contrib/download_prerequisites)

[ -d 'buildloop.d' ] && rm -r 'buildloop.d'
mkdir -p buildloop.d || exit 1

echo "cat /proc/cpuinfo | grep -i -E \"(model name|microcode)\""
cat /proc/cpuinfo | grep -i -E "(model name|microcode)"
echo "sudo dmidecode -t memory | grep -i -E \"(rank|speed|part)\" | grep -v -i unknown"
sudo dmidecode -t memory | grep -i -E "(rank|speed|part)" | grep -v -i unknown
echo "uname -a"
uname -a
echo "cat /proc/sys/kernel/randomize_va_space"
cat /proc/sys/kernel/randomize_va_space

# start journal process in different working directory
pushd /
  journalctl -kf | sed 's/^/[KERN] /' &
popd
echo "Using ${NPROC} parallel processes"

START=$(date +%s)
for ((I=0;$I<$NPROC;I++)); do
  (./buildloop.sh "loop-$I" "$TPROC" "$GCC" || echo "TIME TO FAIL: $(($(date +%s)-${START})) s") | sed "s/^/\[loop-${I}\] /" &
  sleep 1
done

wait
