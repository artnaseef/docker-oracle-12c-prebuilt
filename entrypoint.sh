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

if [ -z "$CHARACTER_SET" ]; then
	if [ "${USE_UTF8_IF_CHARSET_EMPTY}" == "true" ]; then
		export CHARACTER_SET="AL32UTF8"
	fi
fi

if [ -n "$CHARACTER_SET" ]; then
	export CHARSET_MOD="NLS_LANG=.$CHARACTER_SET"
	export CHARSET_INIT="-characterSet $CHARACTER_SET"
fi

echo "XE:$ORACLE_HOME:N" >> /etc/oratab
chown oracle:dba /etc/oratab
chmod 664 /etc/oratab
rm -rf /u01/app/oracle-product/12.1.0/xe/dbs
ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs

#Startup Database
su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
su oracle -c 'echo startup\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'

if [ "$WEB_CONSOLE" == "true" ]
then
	echo 'Starting web management console'
	su oracle -c 'echo EXEC DBMS_XDB.sethttpport\(8080\)\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
else
	echo 'Disabling web management console'
	su oracle -c 'echo EXEC DBMS_XDB.sethttpport\(0\)\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
fi


##
## Run the initialization scripts, if available and not already run
##
if [ -d "/docker-entrypoint-initdb.d" ]
then
	TAG_FILE="/docker-entrypoint-initdb.d/.import-complete"
	if [ ! -f "${TAG_FILE}" ]
	then
		echo "Starting import from '/docker-entrypoint-initdb.d':"
		/exec-db-scripts.sh "/docker-entrypoint-initdb.d"

		# Mark the import as complete
		date >> "${TAG_FILE}"
	else
		echo "Skipping import from  '/docker-entrypoint-initdb.d' as import already run"
		echo "Remove ${TAG_FILE} to reset"
	fi
fi

##
## Run the every-boot startup scripts, if any
##
if [ -d "/docker-startup-scripts.d" ]
then
	echo "Starting import from '/docker-startup-scripts.d':"
	/exec-db-scripts.sh "/docker-startup-scripts.d"
fi


##
## STARTED!
##
echo "Database ready to use. Enjoy! ;)"


##
## Workaround for graceful shutdown.
##
while [ "$END" == '' ]
do
	sleep 1
	trap "su oracle -c 'echo shutdown immediate\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'" INT TERM
done
