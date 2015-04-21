#!/bin/bash

set -e

function defaults {
    : ${SYNC_DEST="s3://repo.ccgapps.com.au"}
    : ${SYNC_REPOS_FILE="/repos.txt"}
    : ${SYNC_LOCAL_REPO_PREFIX="/data"}
    : ${SYNC_CREATED_SENTINEL="${SYNC_LOCAL_REPO_PREFIX}/.created"}

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

    if [[ -z "$SYNC_DRYRUN" ]] ; then
        SYNC_DRYRUN=""
    else
        echo "Sync will be a dry run"
        SYNC_DRYRUN="--dryrun"
    fi

    echo "SYNC_DEST is ${SYNC_DEST}"

    export SYNC_DEST SYNC_DELETE SYNC_REPOS_FILE SYNC_LOCAL_REPO_PREFIX SYNC_DRYRUN
}


function lock {
    REPO_PATH=$1
    LOCKFILE="${REPO_PATH}/lock"
    echo "Getting lock on ${LOCKFILE}"
    lockfile ${LOCKFILE}
    trap 'unlock ${REPO_PATH}' EXIT SIGINT SIGTERM SIGHUP
}


function unlock {
    REPO_PATH=$1
    LOCKFILE="${REPO_PATH}/lock"
    echo "Removing ${LOCKFILE}."
    rm -f ${LOCKFILE}
    trap - EXIT
}


function initallrepos {
    if [[ -f "${SYNC_CREATED_SENTINEL}" ]]; then
        echo "Repos already created"
        exit 1
    fi

    while read repo
    do
        initrepo ${repo}
    done < ${SYNC_REPOS_FILE}

    touch ${SYNC_CREATED_SENTINEL}
}


function initrepo {
    REPO=${1}
    LOCAL_REPO_PATH="${SYNC_LOCAL_REPO_PREFIX}/${REPO}"

    lock ${LOCAL_REPO_PATH}

    echo "init ${REPO}"
    mkdir -p ${LOCAL_REPO_PATH}
    time createrepo -s sha ${LOCAL_REPO_PATH}

    unlock ${LOCAL_REPO_PATH}
}


function updateallrepos {
    while read repo
    do
        updaterepo ${repo}
    done < ${SYNC_REPOS_FILE}
}


function updaterepo {
    REPO=${1}
    LOCAL_REPO_PATH="${SYNC_LOCAL_REPO_PREFIX}/${REPO}"

    if ! [[ -d "${LOCAL_REPO_PATH}" ]]; then
        echo "No repo ${LOCAL_REPO_PATH} found"
        exit 1
    fi

    echo "Updating ${REPO}"

    lock ${LOCAL_REPO_PATH}

    echo "Lock acquired, updating repo"
    find ${LOCAL_REPO_PATH} -name repodata | xargs -n 1 rm -rf
    time createrepo --update -s sha "${LOCAL_REPO_PATH}"

    unlock ${LOCAL_REPO_PATH}
}


function uploadallrepos {
    while read repo
    do
        uploadrepo ${repo}
    done < ${SYNC_REPOS_FILE}
}


function uploadrepo {
    REPO=${1}
    LOCAL_REPO_PATH="${SYNC_LOCAL_REPO_PREFIX}/${REPO}"

    lock ${LOCAL_REPO_PATH}

    echo "Uploading ${LOCAL_REPO_PATH} to ${SYNC_DEST}"
    time aws s3 sync \
        ${LOCAL_REPO_PATH}/ ${SYNC_DEST}/${REPO} \
        ${SYNC_DELETE} \
        ${SYNC_DRYRUN} \
        --exclude "*.sh" \
        --exclude "*.txt" \
        --exclude ".created" \
        --exclude "lock" \

    unlock ${LOCAL_REPO_PATH}
}


function downloadallrepos {
    if [[ -f "${SYNC_CREATED_SENTINEL}" ]]; then
        echo "Repos already created"
        exit 1
    fi

    while read repo
    do
        downloadrepo $repo
    done < ${SYNC_REPOS_FILE}

    touch ${SYNC_CREATED_SENTINEL}
}


# download only RPMs
function downloadrepo {
    REPO=$1
    LOCAL_REPO_PATH="${SYNC_LOCAL_REPO_PREFIX}/${REPO}"

    echo "Download ${LOCAL_REPO_PATH}"
    mkdir -p ${LOCAL_REPO_PATH}

    lock ${LOCAL_REPO_PATH}

    echo "Lock acquired, downloading repo"
    time aws s3 sync \
        ${SYNC_DEST}/${REPO} ${LOCAL_REPO_PATH} \
        ${SYNC_DELETE} \
        ${SYNC_DRYRUN} \
        --exclude "*" \
        --include "*.rpm"

    unlock ${LOCAL_REPO_PATH}
}


echo "HOME is ${HOME}"
echo "WHOAMI is `whoami`"

defaults

if [ "$1" = 'initallrepos' ]; then
    echo "[Run] Init all repos"
    initallrepos
    exit 0
fi

if [ "$1" = 'initrepo' ]; then
    echo "[Run] Init repo"
    initrepo $2
    exit 0
fi

if [ "$1" = 'downloadallrepos' ]; then
    echo "[Run] Download all repos"
    downloadallrepos
    exit 0
fi

if [ "$1" = 'downloadrepo' ]; then
    echo "[Run] Download repo"
    downloadrepo $2
    exit 0
fi

if [ "$1" = 'uploadallrepos' ]; then
    echo "[Run] Upload all repos"
    uploadallrepos
    exit 0
fi

if [ "$1" = 'uploadrepo' ]; then
    echo "[Run] Upload repo"
    uploadrepo $2
    exit 0
fi

if [ "$1" = 'updateallrepos' ]; then
    echo "[Run] Update all repos"
    updateallrepos
    exit 0
fi

if [ "$1" = 'updaterepo' ]; then
    echo "[Run] Update repo"
    updaterepo $2
    exit 0
fi

echo "[RUN]: Builtin command not provided [updaterepo|updateallrepos|initrepo|initallrepos|downloadrepo|downloadallrepos|uploadrepo|uploadallrepos]"
echo "[RUN]: $@"

exec "$@"
