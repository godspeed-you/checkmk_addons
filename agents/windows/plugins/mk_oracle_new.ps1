#!/usr/bin/env python                                                                                                                   
# -*- encoding: utf-8; py-indent-offset: 4 -*-

# Debugging
$DEBUG = 0
Function Print-Debug {
Param(
 [Parameter(Mandatory=$True,Position=1)]
   [string]$error_message
)
     # if debug=1 then output
     if ($DEBUG -gt 0) {
          $MYTIME=Get-Date -Format o
          echo "${MYTIME} DEBUG:${error_message}"
     }
}

Function Print-Sections {
    $sections = $SYNC_SECTIONS + $ASYNC_SECTIONS
    foreach ($section in $sections) {
        echo "<<<oracle_$section>>>"
    }
}

# Basic parameters
$OracleHome = (Get-Command sqlplus | Select-Object -ExpandProperty Definition | % {$_ -replace('bin\\sqlplus.exe','')})
add-type -path "$OracleHome\ODP.NET\managed\common\Oracle.ManagedDataAccess.dll"


#   .--Config--------------------------------------------------------------.
#   |                     ____             __ _                            |
#   |                    / ___|___  _ __  / _(_) __ _                      |
#   |                   | |   / _ \| '_ \| |_| |/ _` |                     |
#   |                   | |__| (_) | | | |  _| | (_| |                     |
#   |                    \____\___/|_| |_|_| |_|\__, |                     |
#   |                                           |___/                      |
#   +----------------------------------------------------------------------+
#   | The user can override and set variables in mk_oracle_cfg.ps1         |
#   '----------------------------------------------------------------------'

$NORMAL_ACTION_PREFERENCE="Stop"
$ErrorActionPreference = "Stop"
$run_async = $null



######## Testing config! Will be removed later
$SYNC_SECTIONS = @("instance", "sessions", "logswitches", "undostat", "recovery_area", "processes", "recovery_status", "longactivesessions", "dataguard_stats", "performance", "locks")
$ASYNC_SECTIONS = @("tablespaces", "rman", "jobs", "ts_quotas", "resumable")
$DBUSER = @("c##check_mk", "cmk", "", "10.1.2.33", "1521")
########


function Set-OraInstance($sid) {      
    return New-Object -TypeName PSObject -Property @{     
       'sync_sections' = 0
       'async_sections' = 0
       # Basic properties
       'Version' = 0
       'SID' = $sid
       'CacheTimeout' = 600
       'Port' = 1521
       'Hostname' = 'localhost'
       'Sysdba' = 0
       'Username' = 'check_mk'
       'Password' = 'myPassword'
      }
}

#.
#   .--SQL Queries---------------------------------------------------------.
#   |        ____   ___  _        ___                  _                   |
#   |       / ___| / _ \| |      / _ \ _   _  ___ _ __(_) ___  ___         |
#   |       \___ \| | | | |     | | | | | | |/ _ \ '__| |/ _ \/ __|        |
#   |        ___) | |_| | |___  | |_| | |_| |  __/ |  | |  __/\__ \        |
#   |       |____/ \__\_\_____|  \__\_\\__,_|\___|_|  |_|\___||___/        |
#   |                                                                      |
#   +----------------------------------------------------------------------+
#   | The following functions create SQL queries for ORACLE and output     |
#   | them to stdout. All queries output the database name or the instane  |
#   | name as first column.                                                |
#   '----------------------------------------------------------------------'

################################################################################
# SQL for Performance information
################################################################################
Function Get-Performance {
     return @'
          select upper(i.INSTANCE_NAME)
                     ||'|'|| 'sys_time_model'
                     ||'|'|| S.STAT_NAME
                     ||'|'|| Round(s.value/1000000)
              from v$instance i,
                   v$sys_time_model s
              where s.stat_name in('DB time', 'DB CPU')
              order by s.stat_name
'@
}

################################################################################
# SQL for Tablespace information
################################################################################
Function Get-Tablespaces {
    return @'
          select upper(d.NAME) || '|' || file_name ||'|'|| tablespace_name ||'|'|| fstatus ||'|'|| AUTOEXTENSIBLE
                  ||'|'|| blocks ||'|'|| maxblocks ||'|'|| USER_BLOCKS ||'|'|| INCREMENT_BY
                  ||'|'|| ONLINE_STATUS ||'|'|| BLOCK_SIZE
                  ||'|'|| decode(tstatus,'READ ONLY', 'READONLY', tstatus) || '|' || free_blocks
                  ||'|'|| contents
                  ||'|'|| iversion
           from v$database d , (
                    select f.file_name, f.tablespace_name, f.status fstatus, f.AUTOEXTENSIBLE,
                    f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY,
                    f.ONLINE_STATUS, t.BLOCK_SIZE, t.status tstatus, nvl(sum(fs.blocks),0) free_blocks, t.contents,
                    (select version from v$instance) iversion 
                    from dba_data_files f, dba_tablespaces t, dba_free_space fs
                    where f.tablespace_name = t.tablespace_name
                    and f.file_id = fs.file_id(+)
                    group by f.file_name, f.tablespace_name, f.status, f.autoextensible,
                    f.blocks, f.maxblocks, f.user_blocks, f.increment_by, f.online_status,
                    t.block_size, t.status, t.contents
                    UNION
                    select f.file_name, f.tablespace_name, f.status, f.AUTOEXTENSIBLE,
                    f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY, 'TEMP',
                    t.BLOCK_SIZE, t.status, sum(sh.blocks_free) free_blocks, 'TEMPORARY',
                    (select version from v$instance) version
                    from v$thread th, dba_temp_files f, dba_tablespaces t, v$temp_space_header sh
                    WHERE f.tablespace_name = t.tablespace_name and f.file_id = sh.file_id
                    GROUP BY th.instance, f.file_name, f.tablespace_name, f.status,
                    f.autoextensible, f.blocks, f.maxblocks, f.user_blocks, f.increment_by,
                    'TEMP', t.block_size, t.status)
                    where d.database_role = 'PRIMARY'
'@
}

################################################################################
# SQL for Dataguard Statistics
################################################################################
Function Get-Dataguard_stats {
    return @'
          SELECT upper(d.NAME)
                     ||'|'|| upper(d.DB_UNIQUE_NAME)
                     ||'|'|| d.DATABASE_ROLE
                     ||'|'|| ds.name
                     ||'|'|| ds.value
              FROM  v$database d
              JOIN  v$parameter vp on 1=1
              left outer join V$dataguard_stats ds on 1=1
              WHERE vp.name = 'log_archive_config'
              AND   vp.value is not null
              ORDER BY 1
'@
}

################################################################################
# SQL for Recovery status
################################################################################
Function Get-Recovery_status {
    return @'
          SELECT upper(d.NAME)
                     ||'|'|| d.DB_UNIQUE_NAME
                     ||'|'|| d.DATABASE_ROLE
                     ||'|'|| d.open_mode
                     ||'|'|| dh.file#
                     ||'|'|| round((dh.CHECKPOINT_TIME-to_date('01.01.1970','dd.mm.yyyy'))*24*60*60)
                     ||'|'|| round((sysdate-dh.CHECKPOINT_TIME)*24*60*60)
                     ||'|'|| dh.STATUS
                     ||'|'|| dh.RECOVER
                     ||'|'|| dh.FUZZY
                     ||'|'|| dh.CHECKPOINT_CHANGE#
              FROM  V$datafile_header dh, v$database d, v$instance i
              ORDER BY dh.file#
'@
}

################################################################################
# SQL for RMAN Backup information
################################################################################
Function Get-Rman {
    return @'
          SELECT upper(d.NAME)
                 ||'|'|| a.STATUS
                 ||'|'|| to_char(a.START_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 ||'|'|| to_char(a.END_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 ||'|'|| replace(b.INPUT_TYPE, ' ', '_')
                 ||'|'|| round(((sysdate - END_TIME) * 24 * 60),0)
                 FROM V$RMAN_BACKUP_JOB_DETAILS a, v$database d,
                      (SELECT input_type, max(command_id) as command_id
                       FROM V$RMAN_BACKUP_JOB_DETAILS
                      WHERE START_TIME > sysdate-14
                        and input_type != 'ARCHIVELOG'
                        and STATUS<>'RUNNING' GROUP BY input_type) b
                 WHERE a.COMMAND_ID = b.COMMAND_ID
          UNION ALL
          select name
                 || '|COMPLETED'
                 || '|'|| to_char(sysdate, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| to_char(completed, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|ARCHIVELOG|'
                 || round((sysdate - completed)*24*60,0)
          from (
                select d.name
                     , max(a.completion_time) completed
                     , case when a.backup_count > 0 then 1 else 0 end
                from v$archived_log a, v$database d
                where a.backup_count > 0
                      and a.dest_id in
                      (select b.dest_id
                       from v$archive_dest b
                       where b.target = 'PRIMARY'
                         and b.SCHEDULE = 'ACTIVE'
                          )
                group by d.name, case when a.backup_count > 0 then 1 else 0 end)
'@
}

################################################################################
# SQL for Flash Recovery Area information
################################################################################
Function Get-Recovery_area {
    return @'
          select upper(d.NAME)
                     ||'|'|| round((SPACE_USED-SPACE_RECLAIMABLE)/
                               (CASE NVL(SPACE_LIMIT,1) WHEN 0 THEN 1 ELSE SPACE_LIMIT END)*100)
                     ||'|'|| round(SPACE_LIMIT/1024/1024)
                     ||'|'|| round(SPACE_USED/1024/1024)
                     ||'|'|| round(SPACE_RECLAIMABLE/1024/1024)
              from V$RECOVERY_FILE_DEST, v$database d
'@
}

################################################################################
# SQL for UNDO information
################################################################################
Function Get-Undostat {
    return @'
          select upper(i.INSTANCE_NAME)
                     ||'|'|| ACTIVEBLKS
                     ||'|'|| MAXCONCURRENCY
                     ||'|'|| TUNED_UNDORETENTION
                     ||'|'|| maxquerylen
                     ||'|'|| NOSPACEERRCNT
              from v$instance i,
                  (select * from (select *
                                  from v$undostat order by end_time desc
                                 )
                            where rownum = 1
                              and TUNED_UNDORETENTION > 0
                  )
'@
}

################################################################################
# SQL for resumable information
################################################################################
Function Get-Resumable {
    return @'
          select upper(i.INSTANCE_NAME)
                 ||'|'|| u.username
                 ||'|'|| a.SESSION_ID
                 ||'|'|| a.status
                 ||'|'|| a.TIMEOUT
                 ||'|'|| round((sysdate-to_date(a.SUSPEND_TIME,'mm/dd/yy hh24:mi:ss'))*24*60*60)
                 ||'|'|| a.ERROR_NUMBER
                 ||'|'|| to_char(to_date(a.SUSPEND_TIME, 'mm/dd/yy hh24:mi:ss'),'mm/dd/yy_hh24:mi:ss')
                 ||'|'|| a.RESUME_TIME
                 ||'|'|| a.ERROR_MSG
          from dba_resumable a, v$instance i, dba_users u
          where a.INSTANCE_ID = i.INSTANCE_NUMBER
          and u.user_id = a.user_id
          and a.SUSPEND_TIME is not null
          union all
          select upper(i.INSTANCE_NAME)
                 || '|||||||||'
          from v$instance i
'@
}

################################################################################
# SQL for scheduler_jobs information
################################################################################
Function Get-Jobs {
    return @'
          SELECT upper(d.NAME)
                     ||'|'|| j.OWNER
                     ||'|'|| j.JOB_NAME
                     ||'|'|| j.STATE
                     ||'|'|| ROUND((TRUNC(sysdate) + j.LAST_RUN_DURATION - TRUNC(sysdate)) * 86400)
                     ||'|'|| j.RUN_COUNT
                     ||'|'|| j.ENABLED
                     ||'|'|| NVL(j.NEXT_RUN_DATE, to_date('1970-01-01', 'YYYY-mm-dd'))
                     ||'|'|| NVL(j.SCHEDULE_NAME, '-')
                     ||'|'|| d.STATUS
              FROM dba_scheduler_jobs j, dba_scheduler_job_run_details d, v$database d
              WHERE d.owner=j.OWNER AND d.JOB_NAME=j.JOB_NAME
                AND d.LOG_ID=(SELECT max(LOG_ID) FROM dba_scheduler_job_run_details dd
                              WHERE dd.owner=j.OWNER and dd.JOB_NAME=j.JOB_NAME
                             )
'@
}

################################################################################
# SQL for Tablespace quotas information
################################################################################
Function Get-Ts_quotas {
    return @'
        select upper(d.NAME)
                 ||'|'|| Q.USERNAME
                 ||'|'|| Q.TABLESPACE_NAME
                 ||'|'|| Q.BYTES
                 ||'|'|| Q.MAX_BYTES
          from dba_ts_quotas Q, v$database d
          where max_bytes > 0
          union all
          select upper(d.NAME)
                 ||'|||'
          from v$database d
          order by 1
'@
}

################################################################################
# SQL for Oracle Version information
################################################################################
Function Get-Version {
    return @'
        select upper(i.INSTANCE_NAME)
                    || '|' || banner
            from v$version, v$instance i
            where banner like 'Oracle%'
'@
}



################################################################################
# SQL for sql_instance information
################################################################################
Function Get-Instance {
    return @'
          select upper(i.instance_name)
                     || '|' || i.VERSION
                     || '|' || i.STATUS
                     || '|' || i.LOGINS
                     || '|' || i.ARCHIVER
                     || '|' || round((sysdate - i.startup_time) * 24*60*60)
                     || '|' || DBID
                     || '|' || LOG_MODE
                     || '|' || DATABASE_ROLE
                     || '|' || FORCE_LOGGING
                     || '|' || d.name
                from v$instance i, v$database d
'@
     }

################################################################################
# SQL for sql_sessions information
################################################################################
Function Get-Sessions {
    return @'
        select upper(i.instance_name)
                  || '|' || CURRENT_UTILIZATION
           from v$resource_limit, v$instance i
           where RESOURCE_NAME = 'sessions'
'@
}

################################################################################
# SQL for sql_processes information
################################################################################
Function Get-Processes {
    return @'
        select upper(i.instance_name)
                  || '|' || CURRENT_UTILIZATION
                  || '|' || ltrim(rtrim(LIMIT_VALUE))
           from v$resource_limit, v$instance i
           where RESOURCE_NAME = 'processes'
'@
}

################################################################################
# SQL for sql_logswitches information
################################################################################
Function Get-Logswitches {
    return @'
select upper(i.instance_name)
                  || '|' || logswitches
           from v$instance i ,
                (select count(1) logswitches
                 from v$loghist h , v$instance i
                 where h.first_time > sysdate - 1/24
                 and h.thread# = i.instance_number)
'@
echo $query_logswitches
}




################################################################################
# SQL for database lock information
################################################################################
Function Get-Locks {
    return @'
        select upper(i.instance_name)
                     || '|' || b.sid
                     || '|' || b.serial#
                     || '|' || b.machine
                     || '|' || b.program
                     || '|' || b.process
                     || '|' || b.osuser
                     || '|' || b.username
                     || '|' || b.SECONDS_IN_WAIT
                     || '|' || b.BLOCKING_SESSION_STATUS
                     || '|' || bs.inst_id
                     || '|' || bs.sid
                     || '|' || bs.serial#
                     || '|' || bs.machine
                     || '|' || bs.program
                     || '|' || bs.process
                     || '|' || bs.osuser
                     || '|' || bs.username
              from v$session b
              join v$instance i on 1=1
              join gv$session bs on bs.inst_id = b.BLOCKING_INSTANCE
                                 and bs.sid = b.BLOCKING_SESSION
              where b.BLOCKING_SESSION is not null
'@
}

################################################################################
# SQL for long active session information
################################################################################
Function Get-Longactivesessions {
    return @'
          select upper(i.instance_name)
                     || '|' || s.sid
                     || '|' || s.serial#
                     || '|' || s.machine
                     || '|' || s.process
                     || '|' || s.osuser
                     || '|' || s.program
                     || '|' || s.last_call_et
                     || '|' || s.sql_id
              from v$session s, v$instance i
              where s.status = 'ACTIVE'
              and type != 'BACKGROUND'
              and s.username is not null
              and s.username not in('PUBLIC')
              and s.last_call_et > 60*60
              union all
              select upper(i.instance_name)
                     || '||||||||'
              from v$instance i
'@
}

################################################################################
# SQL for sql_logswitches information
################################################################################
Function Get-ASM_diskgroup {
    return @'
          select STATE
                     || '|' || TYPE
                     || '|' || 'N'
                     || '|' || sector_size
                     || '|' || block_size
                     || '|' || allocation_unit_size
                     || '|' || total_mb
                     || '|' || free_mb
                     || '|' || required_mirror_free_mb
                     || '|' || usable_file_mb
                     || '|' || offline_disks
                     || '|' || voting_files
                     || '|' || name || '/'
                from v$asm_diskgroup
'@
}


#.
#   .--Main----------------------------------------------------------------.
#   |                        __  __       _                                |
#   |                       |  \/  | __ _(_)_ __                           |
#   |                       | |\/| |/ _` | | '_ \                          |
#   |                       | |  | | (_| | | | | |                         |
#   |                       |_|  |_|\__,_|_|_| |_|                         |
#   |                                                                      |
#   +----------------------------------------------------------------------+
#   |  Iterate over all instances and execute sync and async sections.     |
#   '----------------------------------------------------------------------'


#########################################################
# we now call all the functions to give us the SQL output
#########################################################
# get a list of all running Oracle Instances
$running_inst = (get-service -Name "Oracle*Service*" -include "OracleService*" | Where-Object {$_.status -eq "Running"})
$running_asm = (get-service -Name "Oracle*Service*" -include "OracleASMService*" | Where-Object {$_.status -eq "Running"})
$inst_count = ($running_inst |measure-object).count
foreach ($instance in $running_inst) {
        $instance.name = $instance.name.Replace('OracleService', '')
        $instance.name = $instance.name.Replace('OracleASMService','')
}


# the following line ensures that the output of the files generated by calling
# Oracle SQLplus through Powershell are not limited to 80 character width. The
# 80 character width limit is the default
$host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size (512, 150)

if ($inst_count -eq 0) {
    Print-Sections
}
    foreach ($instance in $running_inst) {
        # Check if we should check this instance
        if ($SKIP_SIDS -ne $null) {
            if ($SKIP_SIDS -notcontains $instance) {
                Continue
            }
        } elseif ($ONLY_SIDS -ne $null) {
            if ($ONLY_SIDS -contains $instance) {
               $SID = Set-OraInstance($instance.Name)
               Print-Debug $SID
            }
        } else {
            $SID = Set-OraInstance($instance.Name)
            Print-Debug $SID
        }
        # Set connection parameters for instance
        if ($DBUSER.count -eq 0) {
            Print-Debug 'DBUSER not set!'
            Continue
        }

        $SID.Username = $DBUSER[0]
        $SID.Password = $DBUSER[1]
        if ($DBUSER[2] -Contains 'sysdba') {
            $SID.Sysdba = 1
        }
        if ($DBUSER[3] -ne $null) {
            $SID.Hostname = $DBUSER[3]
        }
        if ($DBUSER[4] -ne $null) {
            $SID.Port = $DBUSER[4]
        }
        if ($CACHE_MAXAGE -ne $null) {
            $SID.Cache = $CACHE_MAXAGE
        }

        $SID.sync_sections = $SYNC_SECTIONS
        $SID.async_sections = $ASYNC_SECTIONS
        $conn_string = 'User Id=' + $SID.Username + ';Password=' + $SID.Password
        if ($SID.Sysdba) {
            $conn_string += ';DBA Privilege=SYSDBA'
        }
        $conn_string += ';Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=' + $SID.Hostname + ')(PORT=' + $SID.Port + '))(CONNECT_DATA = (SERVER=dedicated)(SERVICE_NAME=' + $SID.SID + ')))'
        Print-Debug $conn_string

        $connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($conn_string)
        $connection.Open()
        $command = $connection.CreateCommand()
        foreach ($section in $SID.sync_sections) {
            '<<<oracle_' + $section + ':sep(124)>>>'
            $section = 'Get-' + $section
            #$command.CommandText = Get-Performance
            $command.CommandText = Invoke-Expression $section
            $reader = $command.ExecuteReader()
            while ($reader.read()) {
                $reader.GetString(0)
            }
        }
        $connection.Close()
    }

Print-Debug "Fertig!"
   
