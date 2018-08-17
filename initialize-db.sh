#!/bin/bash
set -e

# Prevent owner issues on mounted folders, if desired
if [ "$ENABLE_OWNERSHIP_FIX" = true ] ; then
	chown -R oracle:dba /u01/app/oracle
	chown -R oracle:dba /docker-entrypoint-initdb.d/
fi

rm -f /u01/app/oracle/product
ln -s /u01/app/oracle-product /u01/app/oracle/product

#Run Oracle root scripts
/u01/app/oraInventory/orainstRoot.sh > /dev/null 2>&1
echo | /u01/app/oracle/product/12.1.0/xe/root.sh > /dev/null 2>&1 || true


echo "Database not initialized. Initializing database."

set +e
mv /u01/app/oracle-product/12.1.0/xe/dbs /u01/app/oracle/dbs
set -e

ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs

echo "Starting tnslsnr"
su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
#create DB for SID: xe
su oracle -c "$ORACLE_HOME/bin/dbca -silent -createDatabase -templateName General_Purpose.dbc -gdbname xe -sid xe -responseFile NO_VALUE $CHARSET_INIT -totalMemory $DBCA_TOTAL_MEMORY -emConfiguration LOCAL -pdbAdminPassword oracle -sysPassword oracle -systemPassword oracle"

echo "Configuring Apex console"
cd $ORACLE_HOME/apex
su oracle -c 'echo -e "0Racle$\n8080" | $ORACLE_HOME/bin/sqlplus -S / as sysdba @apxconf > /dev/null'
su oracle -c 'echo -e "${ORACLE_HOME}\n\n" | $ORACLE_HOME/bin/sqlplus -S / as sysdba @apex_epg_config_core.sql > /dev/null'
su oracle -c 'echo -e "ALTER USER ANONYMOUS ACCOUNT UNLOCK;" | $ORACLE_HOME/bin/sqlplus -S / as sysdba > /dev/null'
echo "Database initialized. Please visit http://#containeer:8080/em http://#containeer:8080/apex for extra configuration if needed"
