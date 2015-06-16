#!/bin/bash
docker run -e SYNC_DELETE=1 --volumes-from=createrepodata -t muccg/createrepo:latest uploadrepo $1
