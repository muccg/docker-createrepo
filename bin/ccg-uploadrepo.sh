#!/bin/bash
docker run --volumes-from=createrepodata -t muccg/createrepo:latest uploadrepo $1
