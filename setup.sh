#!/bin/bash
# DISCLAIMER OF WARRANTIES AND LIMITATION OF LIABILITY
# The software is supplied "as is" and all use is at your own risk.  Peak Performance Systems disclaims
# all warranties of any kind, either express or implied, as to the software, including, but not limited to,
# implied warranties of fitness for a particular purpose, merchantability or non - infringement of proprietary
# rights.  Neither this agreement nor any documentation furnished under it is intended to express or imply
# any warranty that the operation of the software will be uninterrupted, timely, or error - free.  Under no
# circumstances shall Peak Performance Systems be liable to any user for direct, indirect, incidental,
# consequential, special, or exemplary damages, arising from or relating to this agreement, the software, or
# user#s use or misuse of the softwares.  Such limitation of liability shall apply whether the damages arise
# from the use or misuse of the software (including such damages incurred by third parties), or errors of
# the software.                         


function msg() {
local type="$1"
local msg="$2"
local now=$(date +"%Y.%m.%d-%H:%M:%S")

	type=`echo $type | awk '{ printf("%-7s\n",$1) }'`
	echo "${type} : ${now} : ${msg}"
}

function flag_abort() {
local f=$1

msg FATAL "${FUNCNAME} triggering abort"

if ( ! touch $f >> $LOG 2>&1 )
then
	msg FATAL "${FUNCNAME} failed to trigger abort."
	return 1
fi

return 0

}

function check_abort_flag() {
local f=$1

if [ -f $f ]
then
	msg FATAL "${FUNCNAME} discovered abort flag."
	return 0
fi

return 1
}

function test_mysql_utilities () {
local exe=""

for exe in mysql
do 
	if ( ! type $exe >> $LOG 2>&1 )
	then
		msg FATAL "Please validate your environment. Mysql is not executable in current \$PATH"
		return 1
	fi
done

return 0
}

function test_conn() {
local constring="$*"
local ret=0

msg NOTIFY ""
msg NOTIFY ""
msg NOTIFY ""
msg NOTIFY "Test connectivity with: mysql $constring"
msg NOTIFY ""
msg NOTIFY ""

mysql $constring -e 'SELECT version();' 

ret=$?

return $ret
}

function slob_tabs_report() {
local constring="$*"
local ret=0
local outfile="${WORK_DIR}/slob_data_load_summary.txt"
#global WORK_DIR
 
if ( ! cat /dev/null > $outfile 2>&1 )
then
	msg FATAL "Cannot create ${outfile}."
	return 1
fi

mysql $constring -t <<EOF > ${outfile}

SELECT concat(table_schema,'.',table_name) "schema.table_name",
    concat(round(table_rows/1000000,2),'M') rows,
    concat(round(data_length/(1024*1024*1024),2),'G') DATA,
    concat(round(index_length/(1024*1024*1024),2),'G') idx,
    concat(round((data_length+index_length)/(1024*1024*1024),2),'G') total_size,
    round(index_length/data_length,2) idxfrac 
FROM information_schema.TABLES 
WHERE table_name = 'cf1'
ORDER BY table_schema;

EOF

ret=$?
return $ret
}

function drop_users(){
local constring="$1"
local num_processed=0
local x=1

for (( x=1 ; x < 4096 ; x++ ))
do
        echo "DROP DATABASE user${x};" >> drop_databases_users.sql
        echo "DROP USER user${x}@'localhost', user${x}@'%';" >> drop_databases_users.sql
done

mysql $constring -vvv < drop_databases_users.sql 2>&1 | tee -a /tmp/XX |  grep -i "Query OK" | wc -l  | while read num_processed
do
	msg NOTIFY "Deleted `expr ${num_processed} / 2` SLOB schemas."
done

return 0
}

function grant() {
local user=$1
local constring="$2" 

local ret=0

mysql $constring -vvv <<EOF
create database ${user};
grant all privileges on ${user}.* to ${user}@'localhost' identified by '${user}' with grant option;
grant all privileges on ${user}.* to ${user}@'%' identified by '${user}' with grant option;
EOF

if [ "$user" != "user1" ]
then
mysql $constring -vvv <<EOF
    grant all privileges on user1.* to ${user}@'localhost';
    grant all privileges on user1.* to ${user}@'%';
EOF

fi

ret=$?

# Leave behind a cleanup script
return $ret
}

function load_base_table () {
local user=$1
local pass=$2
local ret=0

mysql -u$user -p$pass $NON_ADMIN_CONNECT_STRING <<EOF
SET autocommit = 0;
use ${user};

DELIMITER //
CREATE PROCEDURE load_base_table_data()
BEGIN
declare nrows   int default 1;
declare x   VARCHAR(128) default 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';

while nrows <= ${SCALE} DO
    INSERT INTO cf1 VALUES (nrows, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x);
    set nrows = nrows + 1;

    IF ( MOD( nrows, 1000 ) = 0 ) THEN
            COMMIT;
    END IF;

END while;
COMMIT;
END //

DELIMITER ;

call load_base_table_data();

EOF

ret=$?
return $ret

}

function load_normal_table() {
local user=$1
local pass=$2
local ret=0

mysql -u${user} -p${pass} ${NON_ADMIN_CONNECT_STRING} -vvv <<EOF
use ${user};

INSERT INTO cf1 select * from user1.cf1;

COMMIT;

EOF
ret=$?
return $ret
}

function create_table() {
local user=$1
local pass=$2
local ret=0

if [ ! -z "${INNODB_DATA_PATH}" ]
then
    create_table_clause="engine=innodb data directory='${INNODB_DATA_PATH}'"
else
    create_table_clause=""
fi

mysql -u${user} -p${pass} ${NON_ADMIN_CONNECT_STRING} <<EOF
use ${user};

CREATE TABLE cf1
(
custid int primary key, c2 VARCHAR(128), c3 VARCHAR(128) , 
c4 VARCHAR(128) , c5 VARCHAR(128) , c6 VARCHAR(128) ,
c7 VARCHAR(128) , c8 VARCHAR(128) , c9 VARCHAR(128) ,
c10 VARCHAR(128) , c11 VARCHAR(128) , c12 VARCHAR(128) ,
c13 VARCHAR(128) , c14 VARCHAR(128) , c15 VARCHAR(128) ,
c16 VARCHAR(128) , c17 VARCHAR(128) , c18 VARCHAR(128) ,
c19 VARCHAR(128) , c20 VARCHAR(128) ) ${create_table_clause};
EOF

ret=$?
return $ret
}

function cr_slob_procedure() {
local user=$1
local pass=$2
local ret=0

echo "Connecting via \"mysql -u${user} -p${pass} ${NON_ADMIN_CONNECT_STRING}\" "

mysql -u${user} -p${pass} ${NON_ADMIN_CONNECT_STRING} <<EOF

use ${user};

DELIMITER //
CREATE PROCEDURE slobupdate (pv_random int, pv_work_unit int, pv_redo_stress VARCHAR(10)) 
BEGIN

IF  (pv_redo_stress = 'HEAVY')  THEN
    UPDATE cf1 SET
    c2  =  'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c3  =  'AAAAAAAABBBBBBBBAxAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c4  =  'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAA5ABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c5  =  'AAA0AAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBB4BBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c6  =  'AAAAAArABBBBBBBBAAAAAAAABBBBBBBBAAAAAAtABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c7  =  'AAA5AAAABBBBBBBtAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c8  =  'AAAAAAAABBB0BBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c9  =  'AAA0AAAABBBBBBBBAAAAAAAABrBBBBBBAAAAAArABBBBBBBBAAAAAAAABBB4BBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c10  = 'AAAAAArABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c11  = 'AAAAAAAABBBBBBBtAAAAAAAABBBBBBBBAAAAA-AABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c12  = 'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBB3BAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c13  = 'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAAB0BBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c14 =  'AAAAAAAABBBBBBBBAAAAA4AABBBBBBBBAAAAAAAABBB9BBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c15 =  'AAAAAAAABBBBBBBBAAAAAAAABB0BBBBBAAAAAAAABBBfBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c16 =  'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBrAAAAAAABBBBBBBBAA9AAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c17 =  'AAAAAAAABBBBBBBBAAA3AAAABBBBBBBBAAAAAAAABBBBBBBBAA-AAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c18 =  '3AAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c19 =  'A5AAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB',
    c20 =  'AAAAAAAABBBBBBBBAAAAAAAA0BBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBB0BBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBBBBBB'
    WHERE  custid >  ( pv_random - pv_work_unit ) AND  ( custid < pv_random);
    COMMIT;
ELSE
    UPDATE cf1 SET 
    c2  = 'AAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBB',
    c20 = 'AAAAAAAABBBBBBBBAAAAAAAA0BBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBBBBBBAAAAAAAABBBB0BBBAAAAAAAABBBBBBBBAAAAAAAABBBBB3BBAAAAAAAABBBB5BBB'
    WHERE  ( custid >  ( pv_random - pv_work_unit )) AND  (custid < pv_random);
    COMMIT;
END IF;
END //

create procedure slob(p_update_pct int, p_max_loop_iterations int, p_run_time int, p_scale int, p_work_unit int, p_redo_stress varchar(10),
p_shared_data_modulus int, p_do_update_hotspot boolean, p_hotspot_pct int, p_sleep_modulus int, p_think_tm_min float, p_think_tm_max float)
begin
declare v_num_tmp float default 0;

declare v_loop_cnt int default 0;
declare v_rowcnt int default 0;
declare v_updates int default 0;
declare v_selects int default 0;
declare v_random_block int default 1;
declare v_tmp int;
declare v_now int unsigned;
declare v_brick_wall int unsigned;

declare v_begin_time int unsigned;
declare v_end_time int unsigned;
declare v_total_time int;

declare v_do_sleeps BOOLEAN default FALSE;
declare v_loop_control BOOLEAN default FALSE;
declare v_update_quota BOOLEAN default FALSE;
declare v_select_quota BOOLEAN default FALSE;
declare v_select_only_workload BOOLEAN default FALSE;
declare v_update_only_workload BOOLEAN default FALSE;
declare v_do_update BOOLEAN default FALSE;
declare v_do_shared_data BOOLEAN default FALSE;
declare v_stop_immediate BOOLEAN default FALSE;

declare v_scratch VARCHAR(80);

IF ( p_shared_data_modulus != 0 ) THEN
    set v_do_shared_data = TRUE;
END IF;

IF ( p_sleep_modulus != 0 ) THEN
    set v_do_sleeps = TRUE;
END IF;


IF ( p_max_loop_iterations > 0 ) THEN
    set v_loop_control = TRUE ;
END IF;

IF ( p_update_pct = 0 ) THEN
    set v_select_only_workload = TRUE;
END IF; 

IF ( p_update_pct = 100 ) THEN
    set v_update_only_workload = TRUE;
END IF; 

set v_update_quota = FALSE ;
set v_select_quota = FALSE ;

set v_begin_time = UNIX_TIMESTAMP();
set v_now = v_begin_time ;
set v_brick_wall = v_now + p_run_time;

while ( v_now < v_brick_wall AND v_stop_immediate != TRUE )  DO


    IF ( v_do_sleeps = TRUE ) AND ( MOD( v_random_block, p_sleep_modulus ) = 0 ) THEN
        set v_num_tmp = FLOOR(p_think_tm_min + RAND() * (p_think_tm_max - p_think_tm_min));
        select sleep(v_num_tmp);
    END IF;

    IF  ( v_select_only_workload = TRUE ) THEN 
        -- handle case where user specified zero pct updates
        set v_do_update = FALSE;
        set v_update_quota = TRUE ;

    ELSE
        IF ( v_update_only_workload = TRUE ) THEN
            set v_do_update = TRUE;
            set v_update_quota = FALSE;
        ELSE            
            IF ( v_update_quota = FALSE ) THEN
                -- We are doing updates during this run and quota has not been met yet
                -- We still vacilate until update quota has been met
                set v_do_update = FALSE;   

                IF ( MOD(v_random_block, 2) = 0 ) THEN
                    set v_do_update = TRUE;
                END IF;
            ELSE
                -- UPDATE quota has been filled, force drain some SELECTs
                set v_do_update = FALSE; 
            END IF;
        END IF;

    END IF;
    
    IF ( v_do_update = TRUE ) THEN
        set v_updates = v_updates + 1;

        IF ( v_updates >= p_update_pct ) THEN
            set v_update_quota = TRUE; 
        END IF;

        IF ( p_do_update_hotspot = TRUE ) THEN
            set v_random_block = FLOOR(p_work_unit+1 + RAND() * (p_scale * (1 / p_hotspot_pct) - p_work_unit -1));
        ELSE
            set v_random_block = FLOOR(p_work_unit+1 + RAND() * (p_scale - p_work_unit -1));
        END IF;

        IF (v_do_shared_data = TRUE) AND ( MOD(v_loop_cnt, p_shared_data_modulus) = 0 ) THEN
            call user1.slobupdate( v_random_block, p_work_unit, p_redo_stress ); 
        ELSE
            call slobupdate( v_random_block, p_work_unit, p_redo_stress ); 
        END IF;

    ELSE
        set v_selects = v_selects + 1;     
        set v_random_block = FLOOR(p_work_unit+1 + RAND() * (p_scale - p_work_unit -1));

        IF (v_do_shared_data = TRUE) AND ( MOD(v_loop_cnt, p_shared_data_modulus) = 0 ) THEN
            SELECT COUNT(c2) INTO v_rowcnt FROM user1.cf1 WHERE ( custid > ( v_random_block - p_work_unit ) ) AND  (custid < v_random_block);
        ELSE
            SELECT COUNT(c2) INTO v_rowcnt FROM cf1 WHERE ( custid > ( v_random_block - p_work_unit ) ) AND  (custid < v_random_block);
        END IF;

    END IF ;

    IF ( v_select_only_workload != TRUE ) AND ( ( v_updates + v_selects ) >=  100 ) THEN
        set v_update_quota = FALSE;
        set v_select_quota = FALSE;    
        set v_updates = 0;
        set v_selects = 0;
    END IF;


    set v_loop_cnt = v_loop_cnt + 1 ;

    IF ( v_loop_control = TRUE ) AND  ( v_loop_cnt >= p_max_loop_iterations ) THEN
            set v_stop_immediate = TRUE ;
    END IF;

    set v_now = UNIX_TIMESTAMP();

END while;
 
set v_end_time = v_now ;
set v_total_time = v_end_time - v_begin_time ;
set v_scratch = concat(user(),  '|',  v_total_time );
select v_scratch "user|total_time";

END //

EOF

ret=$?
return $ret

}

function setup() {
local user=$1
local pass=$2

msg NOTIFY "Creating SLOB table for schema ${user}"

if ( ! create_table $user $pass >> $LOG 2>&1 )
then
	msg FATAL "Failed to create table for ${user}."
	return 1
fi

if [ "$user" = "user1" ]
then
	if ( ! load_base_table $user $pass >> $LOG 2>&1 )
	then
		msg FATAL "Failed to load ${user} SLOB table."
		return 1
	fi
else
	if ( ! load_normal_table $user $pass >> $LOG 2>&1 )
	then
		msg FATAL "Failed to load ${user} SLOB table."
		return 1			
	fi
fi

return 0
}

function check_bom() {
local file=""

if [ ! -f ./misc/BOM ]
then
	msg FATAL "${0}: ${FUNCNAME}: No BOM file in ./misc. Incorrect SLOB file contents."
	return 1
fi

for file in `cat ./misc/BOM | xargs echo`
do
	if [ ! -f "$file" ]
	then
		msg FATAL "${0}: ${FUNCNAME}: Missing ${file}. Incorrect SLOB file contents."
		return 1
	fi
done

return 0
}

function create_log(){
local f=$1

if ( ! cat /dev/null > $f )
then
	msg FATAL "Cannot create $LOG log file"
	exit 1
fi

return 0
}

function pre_run_cleanup() {
local f=""

for f in drop_databases_users.sql slob_data_load_summary.txt $ABORT_FLAG_FILE
do
	[[ -f $f ]] && rm -f $f
done
return 0
}



#---------- Main body

export WORK_DIR=`pwd`
export LOG=${WORK_DIR=}/cr_tab_and_load.out
export ABORT_FLAG_FILE=$WORK_DIR/.abort_slob_load


msg NOTIFY ""
msg NOTIFY "Begin SLOB setup. Checking configuration."
msg NOTIFY ""


if ( ! create_log $LOG )
then
	msg FATAL "Cannot create $LOG log file"
	exit 1
fi

if ( ! test_mysql_utilities )
then
	msg FATAL "Abort. See ${LOG}."
	exit 1
fi

if [ $# -ne 1 ] 
then
	msg FATAL "${0} Incorrect command line options."
	msg FATAL "Usage : ${0}: <number of users>" 
	exit 1
fi

export MAXUSER=`echo "$1" 2>&1 | sed 's/[^0-9]//g' 2> /dev/null`

if [ -z "$MAXUSER" ] 
then
	msg FATAL "Non-numeric value passed for number of SLOB schemas to load."
	msg FATAL "${0} Incorrect command line options."
	msg FATAL "Usage : ${0}: <number of users>" 
	exit 1
fi

if [[ "$MAXUSER" -le 0 || "$MAXUSER" -gt 4096 ]] 
then
	msg FATAL "Number of SLOB schemas must be integer and tested maximum is 4096."
	msg FATAL "Usage : ${0}: <optional: number of users (schemas)>"
	exit 1
fi

pre_run_cleanup 

LOAD_PARALLEL_DEGREE=${LOAD_PARALLEL_DEGREE:=1}
SCALE=${SCALE:=10000}

if [ -f ./slob.conf ]
then
	source ./slob.conf
else
	echo "ABORT. There is no slob.conf file in `pwd`"
	exit 1		
fi

conn_string=""
if [ ! -z "${MYSQL_HOST}" ]
then
    conn_string="-h ${MYSQL_HOST}"
fi

if [ ! -z "${MYSQL_PORT}" ]
then
    conn_string="${conn_string} -P ${MYSQL_PORT}"
fi

export ADMIN_CONNECT_STRING="-uroot -p${MYSQL_ROOT_PWD} ${conn_string}"
export NON_ADMIN_CONNECT_STRING="${conn_string}"

msg NOTIFY "Load parameters from slob.conf: "

msg NOTIFY "LOAD_PARALLEL_DEGREE == \"$LOAD_PARALLEL_DEGREE\""
msg NOTIFY "SCALE == \"$SCALE\""
msg NOTIFY "INNODB_DATA_PATH == \"$INNODB_DATA_PATH\""
msg NOTIFY "ADMIN_CONNECT_STRING == \"$ADMIN_CONNECT_STRING\""
msg NOTIFY "NON_ADMIN_CONNECT_STRING == \"$NON_ADMIN_CONNECT_STRING\""

msg NOTIFY ""
msg NOTIFY "Testing connectivity to mysql to validate slob.conf settings."
msg NOTIFY "Testing Admin connect using \"$ADMIN_CONNECT_STRING\""

if ( ! test_conn "$ADMIN_CONNECT_STRING" >> $LOG 2>&1  )
then
	msg FATAL "${0}: cannot connect to mysql."
	msg FATAL "Check $LOG log file for more information"
	msg FATAL "Please verify mysql is running and the settings"
	msg FATAL "in slob.conf are correct for your connectivity model."

	exit 1
else
	msg NOTIFY "${0}: Successful test connection: \"mysql $ADMIN_CONNECT_STRING\""
	msg NOTIFY " "	
fi

USER=""
PASS=""

cnt=1
groupcnt=0
x=0

msg NOTIFY "Dropping prior SLOB schemas."
if ( ! drop_users "$ADMIN_CONNECT_STRING" )
then
	msg FATAL "Processing the DROP USER CACADE statements to"
	msg FATAL "remove any prior SLOB schemas failed."
	exit 1
else
	msg NOTIFY "Previous SLOB schemas have been removed."
fi

msg NOTIFY "Preparing to load $MAXUSER schema(s)"

while [ $cnt -le $MAXUSER ]
do
	USER=user$cnt
	PASS=user$cnt

	if [ $cnt -eq 1 ]
	then
		if ( ! grant $USER "$ADMIN_CONNECT_STRING" >> $LOG  2>&1 )
		then
			msg FATAL "Cannot create ${USER} schema. See ${LOG}."
			exit 1
		fi

		msg NOTIFY "Loading $USER schema."
		before_load_ts=$SECONDS
		if ( ! setup $USER $PASS >> $LOG 2>&1 )
		then
			msg FATAL "Cannot load $USER schema"
			msg FATAL "See $LOG"
			exit 1
		fi

		concurrent_load_before="$SECONDS"

		msg NOTIFY "Finished loading user1 schema in $(( concurrent_load_before - before_load_ts )) seconds."
		msg NOTIFY "Beginning concurrent load phase."
	else


		if ( ! grant $USER "$ADMIN_CONNECT_STRING" >> $LOG  2>&1 )
		then
			msg FATAL "Cannot create ${USER} schema. See ${LOG}."
			exit 1
		fi

		( setup $USER $PASS >> $LOG 2>&1 || flag_abort $ABORT_FLAG_FILE ) &


		if [ $x -eq $(( LOAD_PARALLEL_DEGREE - 1 ))  ] 
		then
			(( groupcnt = $groupcnt + 1 ))
			msg NOTIFY "Waiting for background group ${groupcnt}. Loading up to user${cnt}."  
			wait 
			msg NOTIFY "Finished background group ${groupcnt}."  
			x=0
		else
			(( x = $x + 1 ))
		fi

		if ( check_abort_flag $ABORT_FLAG_FILE )
		then
			msg FATAL "Aborting SLOB setup. See ${LOG}."
			exit 1
		fi
	fi
	(( cnt = $cnt + 1 ))
done

wait

(( concurrent_load_tm = $SECONDS - $concurrent_load_before ))

msg NOTIFY "Completed concurrent data loading phase: ${concurrent_load_tm} seconds"


msg NOTIFY "Creating SLOB procedure."

x=1
for (( x=1 ; x <= ${MAXUSER} ; x++ ))
do
    cr_slob_procedure user${x} user${x} >> $LOG 2>&1
done

wait

msg NOTIFY "SLOB procedure created."

if ( slob_tabs_report "$ADMIN_CONNECT_STRING" >> $LOG 2>&1 )
then
	msg NOTIFY "Row and block counts for SLOB table(s) reported in ./slob_data_load_summary.txt"
	msg NOTIFY "Please examine ./slob_data_load_summary.txt for any possbile errors." 
else
	msg FATAL "Failed to generate SLOB table row and block count report."
	msg FATAL "See ${LOG}."
	exit 1
fi

msg NOTIFY ""
msg NOTIFY "NOTE: No errors *detected* but if ./slob_data_load_summary.txt shows errors then"
msg NOTIFY "examine ${LOG}."
echo ""

msg NOTIFY "SLOB setup complete (${SECONDS} seconds)."

exit 0

