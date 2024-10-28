#!/bin/bash


if [[ ! -n $1 ]]; then
    echo "arg1 is required"
    exit 1
fi


if [ ! -f $1 ]; then
    echo "arg1 ($1) must be an actual OTA file"
    exit 1
fi

KINDLE_MODEL=$2
KINDLE_VERSION="UNK"
if [ ! -n "$KINDLE_MODEL" ]; then
    if [[ "$1" =~ ^update_(.*?)_(.*?)\.bin ]]; then
        KINDLE_MODEL=${BASH_REMATCH[1]}
        KINDLE_VERSION=${BASH_REMATCH[2]}
        echo "Detected $KINDLE_MODEL version $KINDLE_VERSION"
        if [[ "$KINDLE_VERSION" =~ ^([1-9]*?)\.([1-9]*?)\.([1-9]*?):?(\.|$) ]]; then
            if [ ${BASH_REMATCH[1]} -lt 5 ] | ([ ${BASH_REMATCH[1]} -eq 5 ] && [ ${BASH_REMATCH[2]} -lt 16 ]) | ([ ${BASH_REMATCH[1]} -eq 5 ] && [ ${BASH_REMATCH[2]} -eq 16 ] && [ ${BASH_REMATCH[3]} -lt 3 ]); then
                echo "Min supported version is 5.16.3"
                exit 1
            fi
        fi
    fi
fi
if [ ! -n "$KINDLE_MODEL" ]; then
    echo "kindlemodel ($KINDLE_MODEL) must be an actual device supported by kindletool"
    exit 1
fi

echo "version=$KINDLE_VERSION" >>$GITHUB_OUTPUT
echo "model=$KINDLE_MODEL" >>$GITHUB_OUTPUT


if [ "$(id -u)" -ne 0 ] ; then
    if [ -f /usr/bin/sudo ]; then
        /usr/bin/sudo $0 $1 $2
        exit 0
    fi
    echo "You need to run this as root"
    exit 1
fi

echo "Extracting OTA update"
kindletool extract $1 unpacked > /dev/null

echo "Cleaning up sig files and update-payload.dat"
cd unpacked
find . -name "*.sig" -delete > /dev/null
ls mt8110_bellatrix
rm -rf update-payload.dat

echo "gunzipping rootfs.img.gz"
gunzip rootfs.img.gz

echo "Mounting rootfs.img"
chmod +w rootfs.img
mkdir rootfs
mount -o loop,rw,sync rootfs.img rootfs

echo "Patching upstart conf filesystems_var_local to bring back fixup"
patch -N -i ../bring_back_fixup.patch rootfs/etc/upstart/filesystems_var_local.conf

echo "Copying dispatch script"
rm -rf rootfs/usr/bin/logThis.sh
cp ../dispatch.sh rootfs/usr/bin/logThis.sh 
chmod 0755 rootfs/usr/bin/logThis.sh
chown root:root rootfs/usr/bin/logThis.sh
chattr +i rootfs/usr/bin/logThis.sh

echo "Patching kpp_sys_cmds.json to include dispatch command"
sed -e '/^{/a\' -e '    ";log" : "/usr/bin/logThis.sh",' -i "rootfs/usr/share/app/kpp_sys_cmds.json"

echo "Creating PRE_GM_DEBUGGING_FEATURES_ENABLED__REMOVE_AT_GMC flag file"
touch rootfs/PRE_GM_DEBUGGING_FEATURES_ENABLED__REMOVE_AT_GMC
chown root:root rootfs/PRE_GM_DEBUGGING_FEATURES_ENABLED__REMOVE_AT_GMC
chattr +i rootfs/PRE_GM_DEBUGGING_FEATURES_ENABLED__REMOVE_AT_GMC

echo "Creating MNTUS_EXEC flag file"
touch rootfs/MNTUS_EXEC
chown root:root rootfs/MNTUS_EXEC
chattr +i rootfs/MNTUS_EXEC

echo "Replacing OTA keystore"
cp ../updater_keys.sqsh rootfs/etc/uks.sqsh
chown root:root rootfs/etc/uks.sqsh

echo "Repacking OTA update"
umount rootfs
gzip rootfs.img
rm -rf rootfs
kindletool create recovery2 -d $KINDLE_MODEL . ../update_${KINDLE_MODEL}_${KINDLE_VERSION}_patched.bin > /dev/null

cd ..
OUTPUT="$(pwd)/update_${KINDLE_MODEL}_${KINDLE_VERSION}_patched.bin"
echo "version=$OUTPUT" >>$GITHUB_OUTPUT

echo "Finishing up"
rm -rf unpacked