#!/bin/bash


function defaults {
    : ${SYNC_DEST="s3://repo.ccgapps.com.au"}
    : ${SYNC_CREATED_SENTINEL="/data/.created"}

    if ! [[ -z "$SYNC_FORCE" ]] ; then
        echo "Sync is forced"
        rm -f ${SYNC_CREATED_SENTINEL}
    fi

    if [[ -z "$SYNC_DELETE" ]] ; then
        SYNC_DELETE=""
    else
        echo "Sync will delete at destination"
        SYNC_DELETE="--delete"
    fi

    echo "SYNC_DEST is ${SYNC_DEST}"

    export SYNC_DEST SYNC_DELETE
}


function initrepos {
    if [[ -f "${SYNC_CREATED_SENTINEL}" ]]; then
        echo "Repos already created"
        exit 0
    fi

    while read repo
    do
        echo "init /data/${repo}"
        mkdir -p /data/${repo}/CentOS/RPMS
        lockfile /data/${repo}/lock
        time createrepo -s sha /data/${repo}
        rm -f /data/${repo}/lock
    done < /repos.txt

    touch ${SYNC_CREATED_SENTINEL}
}


function updaterepo {
    # ccg
    # ccg-deps
    REPO=$1
    RELEASE=$2
    ARCH=$3

    REPO_PATH="/data/repo/${REPO}/centos/${RELEASE}/os/${ARCH}"

    if ! [[ -d "${REPO_PATH}" ]]; then
        echo "No repo ${REPO_PATH} found"
        exit 1
    fi

    echo "Updating ${REPO_PATH}"

    LOCKFILE="${REPO_PATH}/lock"
    echo "Getting lock on ${LOCKFILE}"
    lockfile ${LOCKFILE}

    echo "Lock acquired, updating repo"
    time createrepo --update -s sha "${REPO_PATH}"
    STATUS=$?

    echo "Removing ${LOCKFILE}."
    rm -f ${LOCKFILE}
}


function uploadrepo {
    #ccg-deps/
    #ccg/
    REPO=$1

    if [[ -z "${REPO}" ]]; then
        echo "No repo provided $0 REPO"
      exit 1
    fi

    # upload everything, including new indexes
    aws s3 sync \
        --dryrun \
        ${SYNC_DELETE} \
        --exclude "*.sh" \
        --exclude "*.txt" \
        --exclude ".created" \
        --exclude "lock" \
        /data/repo/${REPO}/ ${SYNC_DEST}/repo/${REPO}
}

function recoverrepos {
    if [[ -f "${SYNC_CREATED_SENTINEL}" ]]; then
        echo "Repos already created"
        exit 0
    fi

    while read repo
    do
        echo "Recover /data/${repo}"
        mkdir -p /data/${repo}/CentOS/RPMS

        LOCKFILE="/data/${repo}/lock"
        echo "Getting lock on ${LOCKFILE}"
        lockfile ${LOCKFILE}

        echo "Lock acquired, recovering repo"
        time aws s3 sync \
            ${SYNC_DEST}/${repo} /data/${repo} \
            ${SYNC_DELETE} \
            --exclude "*" \
            --include "*.rpm"

        echo "Removing ${LOCKFILE}."
        rm -f ${LOCKFILE}
    done < /repos.txt

    touch ${SYNC_CREATED_SENTINEL}
}


echo "HOME is ${HOME}"
echo "WHOAMI is `whoami`"

defaults

if [ "$1" = 'updaterepo' ]; then
    echo "[Run] Update repo"
    updaterepo $2 $3 $4
    exit ${STATUS}
fi

if [ "$1" = 'initrepos' ]; then
    echo "[Run] Init repos"
    initrepos
    exit 0
fi

if [ "$1" = 'recoverrepos' ]; then
    echo "[Run] Recover repos"
    recoverrepos
    exit 0
fi

if [ "$1" = 'uploadrepo' ]; then
    echo "[Run] Upload repo"
    uploadrepo $2
    exit 0
fi

echo "[RUN]: Builtin command not provided [updaterepo|initrepos|recoverrepos|uploadrepo]"
echo "[RUN]: $@"

exec "$@"
