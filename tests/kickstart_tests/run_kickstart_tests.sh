#!/bin/bash
#
# Copyright (C) 2014  Red Hat, Inc.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions of
# the GNU General Public License v.2, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY expressed or implied, including the implied warranties of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.  You should have received a copy of the
# GNU General Public License along with this program; if not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.  Any Red Hat trademarks that are incorporated in the
# source code or documentation are not subject to the GNU General Public
# License and may only be used or replicated with the express permission of
# Red Hat, Inc.
#
# Red Hat Author(s): Chris Lumens <clumens@redhat.com>

# Have to be root to run this test, as it requires creating disk images.
if [[ ${EUID} != 0 ]]; then
   exit 77
fi

# The boot.iso location can come from one of two different places:
# (1) $TEST_BOOT_ISO, if this script is being called from "make check"
# (2) The command line, if this script is being called directly.
if [[ "${TEST_BOOT_ISO}" != "" ]]; then
    IMAGE=${TEST_BOOT_ISO}
elif [[ $# != 0 ]]; then
    IMAGE=$1
    shift
fi

if [[ ! -e "${IMAGE}" ]]; then
    echo "Required boot.iso does not exist; skipping."
    exit 77
fi

run() {
    tmpdir=$1
    ks=$2

    ksfile=$(prepare ${ks} ${tmpdir})
    if [[ $? != 0 ]]; then
        echo Test prep failed: ${ksfile}
        return 1
    fi

    kargs=$(kernel_args)
    if [[ ${kargs} != "" ]]; then
        kargs="--kernel-args ${kargs}"
    fi

    livemedia-creator ${kargs} \
                      --make-disk \
                      --iso "${IMAGE}" \
                      --ks ${ksfile} \
                      --tmp ${tmpdir} \
                      --logfile ${tmpdir}/livemedia.log \
                      --title Fedora \
                      --project Fedora \
                      --releasever 22 \
                      --ram 2048 \
                      --vcpus 2 \
                      --vnc vnc
    if [[ $? != 0 ]]; then
        echo $(grep CRIT ${tmpdir}/virt-install.log)
        return 1
    elif [[ -f ${tmpdir}/livemedia.log ]]; then
        img=$(grep disk_img ${tmpdir}/livemedia.log | cut -d= -f2)
        trimmed=${img## }

        if [[ ! -f ${trimmed} ]]; then
            echo Disk image ${trimmed} does not exist.
            return 1
        fi

        validate ${trimmed}
        if [[ $? != 0 ]]; then
            echo FAILED
            return 1
        elif [[ "${result}" != "SUCCESS" ]]; then
            echo ${result}
            return 1
        fi
    fi

    echo SUCCESS
    return 0
}

status=0
for t in kickstart_tests/*sh; do
    # Skip this file, and also provide a way to skip tests by only running
    # those that are executable.
    if [[ $t == "kickstart_tests/run_kickstart_tests.sh"  || ! -x $t ]]; then
        continue
    fi

    ks=${t/.sh/.ks}
    . $t

    echo ${ks}
    echo ==============================

    # qemu user needs to be able to read the directory.
    tmpdir=$(mktemp -d --tmpdir=/var/tmp)
    chmod 755 ${tmpdir}

    run ${tmpdir} ${ks}
    if [[ $? = 1 ]]; then
        status=1
    fi

    rm -rf ${tmpdir}
    unset kernel_args prep validate
done

exit ${status}