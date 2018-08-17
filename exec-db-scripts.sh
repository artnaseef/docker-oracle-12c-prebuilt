#!/bin/bash
set -e

import_to_db ()
{
	typeset filename="$1"

	case "$filename" in
		*.sh)     echo "[IMPORT] $0: running $f"; . "$f" ;;
		*.sql)    echo "[IMPORT] $0: running $f"; echo "exit" | su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/sqlplus -S / as sysdba @$f"; echo ;;
		*.dmp)    echo "[IMPORT] $0: running $f"; impdp $f ;;
		*)        echo "[IMPORT] $0: ignoring $f" ;;
	esac
}

impdp ()
{
	set +e
	DUMP_FILE=$(basename "$1")
	DUMP_NAME=${DUMP_FILE%.dmp} 
	cat > /tmp/impdp.sql << EOL
-- Impdp User
CREATE USER IMPDP IDENTIFIED BY IMPDP;
ALTER USER IMPDP ACCOUNT UNLOCK;
GRANT dba TO IMPDP WITH ADMIN OPTION;
-- New Scheme User
create or replace directory IMPDP as '/docker-entrypoint-initdb.d';
create tablespace $DUMP_NAME datafile '/u01/app/oracle/oradata/$DUMP_NAME.dbf' size 1000M autoextend on next 100M maxsize unlimited;
create user $DUMP_NAME identified by $DUMP_NAME default tablespace $DUMP_NAME;
alter user $DUMP_NAME quota unlimited on $DUMP_NAME;
alter user $DUMP_NAME default role all;
grant connect, resource to $DUMP_NAME;
exit;
EOL

	su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/sqlplus -S / as sysdba @/tmp/impdp.sql"
	su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/impdp IMPDP/IMPDP directory=IMPDP dumpfile=$DUMP_FILE $IMPDP_OPTIONS"
	#Disable IMPDP user
	echo -e 'ALTER USER IMPDP ACCOUNT LOCK;\nexit;' | su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/sqlplus -S / as sysdba"
	set -e
}

#####
#####
#####

SCRIPT_DIR="$1"

if [ ! -d "$SCRIPT_DIR" ]
then
	echo "Execute DB scripts requires a valid directory argument" >&2
	exit 1
fi

echo "Starting import from '$SCRIPT_DIR':"

for f in "${SCRIPT_DIR}"/*
do
	if [ -f "$f" ]
	then
		echo "found file $f"
		import_to_db "$f"
		echo
	fi
done

echo "Import finished"
