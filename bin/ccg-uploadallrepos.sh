#!/bin/bash
docker run --volumes-from=createrepodata -t muccg/createrepo:latest uploadallrepos
