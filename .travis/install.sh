#!/bin/bash

cd source
set -ev

#install core of utplsql
time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
set feedback off
set verify off

--alter session set plsql_warnings = 'ENABLE:ALL', 'DISABLE:(5004,5018,6000,6001,6003,6009,6010,7206)';
alter session set plsql_optimize_level=0;
@install_headless.sql $UT3_OWNER $UT3_OWNER_PASSWORD
SQL

#Run this step only on second child job (12.1 - at it's fastest)
if [[ "${TRAVIS_JOB_NUMBER}" =~ \.2$ ]]; then

    #check code-style for errors
    time "$SQLCLI" $UT3_OWNER/$UT3_OWNER_PASSWORD@//$CONNECTION_STR @../development/utplsql_style_check.sql

    #test install/uninstall process
    time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
    set feedback off
    set verify off

    @uninstall_all.sql $UT3_OWNER
    declare
      v_leftover_objects_count integer;
    begin
      select sum(cnt)
        into v_leftover_objects_count
        from (select count(1) cnt from dba_objects where owner = '$UT3_OWNER'
        union all
        select count(1) cnt from dba_synonyms where table_owner = '$UT3_OWNER'
        );
      if v_leftover_objects_count > 0 then
        raise_application_error(-20000, 'Not all objects were successfully uninstalled - leftover objects count='||v_leftover_objects_count);
      end if;
    end;
    /
SQL

    time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
    set feedback off
    set verify off

    alter session set plsql_optimize_level=0;
    @install.sql $UT3_OWNER
    @create_synonyms_and_grants_for_public.sql $UT3_OWNER
SQL

fi

#additional privileges to run scripted tests
time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
set feedback on
--needed for Mystats script to work
grant select any dictionary to $UT3_OWNER;
--Needed for testing a coverage outside ut3_owner.
grant create any procedure, drop any procedure, execute any procedure to $UT3_OWNER;
SQL

#Create user that will own the tests that are relevant to internal framework
time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
set feedback off
@create_utplsql_owner.sql $UT3_TESTER $UT3_TESTER_PASSWORD $UT3_TABLESPACE
exit
SQL

#Create additional UT3$USER# to test for special characters and front end API testing
time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
set feedback off
@create_utplsql_owner.sql $UT3_USER $UT3_USER_PASSWORD $UT3_TABLESPACE
--Grant UT3 framework to min user
@create_user_grants.sql $UT3_OWNER $UT3_USER
exit
SQL

#Create additional UT3_TESTER_HELPER that will provide a functions to allow min grant test user setup test
time "$SQLCLI" sys/$ORACLE_PWD@//$CONNECTION_STR AS SYSDBA <<-SQL
set feedback off
@create_utplsql_owner.sql $UT3_TESTER_HELPER $UT3_TESTER_HELPER_PASSWORD $UT3_TABLESPACE
--needed for testing distributed transactions
grant create public database link to $UT3_TESTER_HELPER;
grant drop public database link to  $UT3_TESTER_HELPER;
set feedback on
--Needed for testing coverage outside of main UT3 schema.
grant create any procedure, drop any procedure, execute any procedure, create any type, drop any type, execute any type, under any type, select any table, update any table, insert any table, delete any table, create any table, drop any table, alter any table, select any dictionary, create any synonym, drop any synonym to $UT3_TESTER_HELPER;
grant create job to $UT3_TESTER_HELPER;
exit
SQL
