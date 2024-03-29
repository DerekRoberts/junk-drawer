#!/bin/bash
#
set -eux

### Target, vars

TARGET=${1:-prod}

### Backup from old PROD db

# Vars
LEADER=$(oc get cm/fom-db-ha-prod-leader -o json | jq -j '.metadata.annotations.leader')
OLD_DB=$(oc exec $LEADER -- printenv | grep APP_DATABASE | sed 's/.*=//g')

# Dump and copy down
oc exec $LEADER -- mkdir -p /tmp/dump
oc exec $LEADER -- pg_dump -U postgres -d $OLD_DB -Fc -f /tmp/dump/dump_old --no-privileges --no-tablespaces --no-owner
oc cp $LEADER:/tmp/dump .


### Restore to new prod db

# Vars
NEW_USER=$(oc exec dc/fom-$TARGET-db -- printenv | grep -i POSTGRES_USER | sed 's/.*=//g')
NEW_DB=$(oc exec dc/fom-$TARGET-db -- printenv | grep -i POSTGRES_DB | sed 's/.*=//g')
POD=$(oc exec dc/fom-$TARGET-db -- hostname)

# Copy up and restore
oc cp dump_old $POD:/tmp/
oc exec $POD -- pg_restore -d $NEW_DB /tmp/dump_old -U $NEW_USER -c --no-owner || true


### Compare

# Tables
echo "--- old ---"
oc exec $LEADER -- psql -U postgres -d $OLD_DB -c "select count (*) from pg_tables;"
echo "--- new ---"
oc exec $POD -- psql -U $NEW_USER -d $NEW_DB -c "select count (*) from pg_tables;"

# Create new db_dump and compare to old one
oc exec $POD -- pg_dump -d $NEW_DB -U $NEW_USER -Fc -f /tmp/dump_new --no-privileges --no-tablespaces --no-owner
oc exec $POD -- ls -lh /tmp/

### Cleanup

oc exec $LEADER -- rm -rf /tmp/dump
oc exec $POD -- rm /tmp/dump_new /tmp/dump_old
rm dump_old
