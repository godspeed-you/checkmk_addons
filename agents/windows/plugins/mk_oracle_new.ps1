<#
.SYNOPSIS
    This script gets a lot of data regarding oracle databases and oracle
    automatic storage management (ASM). The output of this script is fully
    compatible to the official oracle plugin for windows as it is provided
    by the official checkmk software package.
.DESCRIPTION
    File Name: mk_oracle_new.ps1 Author: Marcel Arentz / tribe29 GmbH
.INPUTS
    None. You cannot pipe objects into this script.
.OUTPUTS
    System.String. This script returns a string with soem checkmk specific
    syntax. Each section is started by <<<$SectionName>>>. Each section
    uses a unique separator like "|" (pipe) or " " (space).
.EXAMPLE
    C:\ProgramData\checkmk\service\plugins\mk_oracle_new.ps1
    <<<oracle_instance>>>
    SID1|11.2.0.4.0|OPEN|ALLOWED|STARTED|33019795|2910985342|ARCHIVELOG|PRIMARY|NO|SID
.LINK
    https://github.com/godspeed-you/checkmk_addons
#>


####################################################################################
################ Declare the function for the queries ##############################
####################################################################################

################################################################################
# SQL for Performance information
################################################################################

Function sql_performance {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
     if ($DBVERSION -gt 101000) {
        $query_performance = @'
        prompt <<<oracle_performance:sep(124)>>>;
        select upper(i.INSTANCE_NAME)
                   ||'|'|| 'sys_time_model'
                   ||'|'|| S.STAT_NAME
                   ||'|'|| Round(s.value/1000000)
            from v$instance i,
                 v$sys_time_model s
            where s.stat_name in('DB time', 'DB CPU')
            order by s.stat_name;
            select upper(i.INSTANCE_NAME)
                   ||'|'|| 'buffer_pool_statistics'
                   ||'|'|| b.name
                   ||'|'|| b.db_block_gets
                   ||'|'|| b.db_block_change
                   ||'|'|| b.consistent_gets
                   ||'|'|| b.physical_reads
                   ||'|'|| b.physical_writes
                   ||'|'|| b.FREE_BUFFER_WAIT
                   ||'|'|| b.BUFFER_BUSY_WAIT
            from v$instance i, V$BUFFER_POOL_STATISTICS b;
            select upper(i.INSTANCE_NAME)
                   ||'|'|| 'librarycache'
                   ||'|'|| b.namespace
                   ||'|'|| b.gets
                   ||'|'|| b.gethits
                   ||'|'|| b.pins
                   ||'|'|| b.pinhits
                   ||'|'|| b.reloads
                   ||'|'|| b.invalidations
            from v$instance i, V$librarycache b;

'@
        Write-Output $query_performance
    }
}

################################################################################
# SQL for Tablespace information
################################################################################

Function sql_tablespaces {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_tablespace = @'
        prompt <<<oracle_tablespaces:sep(124)>>>;
            SET SERVEROUTPUT ON feedback off
            DECLARE
                type x is table of varchar2(20000) index by pls_integer;
                xx x;
            begin
                begin
                    execute immediate 'select upper(decode(vp.con_id, null, d.NAME,d.NAME
                ||''.''||vp.name))
                || ''|'' || dbf.file_name
                || ''|'' || dbf.tablespace_name
                || ''|'' || dbf.fstatus
                || ''|'' || dbf.AUTOEXTENSIBLE
                || ''|'' || dbf.blocks
                || ''|'' || dbf.maxblocks
                || ''|'' || dbf.USER_BLOCKS
                || ''|'' || dbf.INCREMENT_BY
                || ''|'' || dbf.ONLINE_STATUS
                || ''|'' || dbf.BLOCK_SIZE
                || ''|'' || decode(tstatus,''READ ONLY'', ''READONLY'', tstatus)
                || ''|'' || dbf.free_blocks
                || ''|'' || dbf.contents
                || ''|'' || i.version
        from v$database d
        join v$instance i on 1=1
        join (
                select f.con_id, f.file_name, f.tablespace_name, f.status fstatus, f.AUTOEXTENSIBLE,
                f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY,
                f.ONLINE_STATUS, t.BLOCK_SIZE, t.status tstatus, nvl(sum(fs.blocks),0) free_blocks, t.contents
                from cdb_data_files f
                join cdb_tablespaces t on f.tablespace_name = t.tablespace_name
                                      and f.con_id = t.con_id
                left outer join cdb_free_space fs on f.file_id = fs.file_id
                                                 and f.con_id = fs.con_id
                group by f.con_id, f.file_name, f.tablespace_name, f.status, f.autoextensible,
                f.blocks, f.maxblocks, f.user_blocks, f.increment_by, f.online_status,
                t.block_size, t.status, t.contents
        ) dbf on 1=1
        left outer join v$pdbs vp on dbf.con_id = vp.con_id
        where d.database_role = ''PRIMARY'''
                    bulk collect into xx;
                    if xx.count >= 1 then
                        for i in 1 .. xx.count loop
                            dbms_output.put_line(xx(i));
                        end loop;
                    end if;
                exception
                    when others then
                        for cur1 in (select upper(name) name from  v$database) loop
                            dbms_output.put_line(cur1.name || '| Debug (121) 1: ' ||sqlerrm);
                        end loop;
                end;
            END;
/
            DECLARE
                type x is table of varchar2(20000) index by pls_integer;
                xx x;
            begin
                begin
                    execute immediate 'select upper(decode(dbf.con_id, null, d.NAME, dbf.name))
                || ''|'' || dbf.file_name
                || ''|'' || dbf.tablespace_name
                || ''|'' || dbf.fstatus
                || ''|'' || dbf.AUTOEXTENSIBLE
                || ''|'' || dbf.blocks
                || ''|'' || dbf.maxblocks
                || ''|'' || dbf.USER_BLOCKS
                || ''|'' || dbf.INCREMENT_BY
                || ''|'' || dbf.ONLINE_STATUS
                || ''|'' || dbf.BLOCK_SIZE
                || ''|'' || decode(tstatus,''READ ONLY'', ''READONLY'', tstatus)
                || ''|'' || dbf.free_blocks
                || ''|'' || ''TEMPORARY''
                || ''|'' || i.version
        FROM v$database d
        JOIN v$instance i ON 1 = 1
        JOIN (
            SELECT vp.name,
                vp.con_id,
                f.file_name,
                t.tablespace_name,
                f.status fstatus,
                f.autoextensible,
                f.blocks,
                f.maxblocks,
                f.user_blocks,
                f.increment_by,
                ''ONLINE'' online_status,
                t.block_size,
                t.status tstatus,
                f.blocks - nvl(SUM(tu.blocks),0) free_blocks,
                t.contents
            FROM cdb_tablespaces t
            JOIN (
                SELECT vp.con_id
                      ,d.name || ''.''|| vp.name name
                FROM v$containers vp
                JOIN v$database d ON 1 = 1
                WHERE d.cdb = ''YES''
                  AND vp.con_id <> 2
                UNION ALL
                SELECT 0
                      ,name
                FROM v$database
            ) vp ON t.con_id = vp.con_id
            LEFT OUTER JOIN cdb_temp_files f ON t.con_id = f.con_id
                AND t.tablespace_name = f.tablespace_name
            LEFT OUTER JOIN gv$tempseg_usage tu ON f.con_id = tu.con_id
                AND f.tablespace_name = tu.tablespace
                AND f.RELATIVE_FNO = tu.SEGRFNO#
            WHERE t.contents = ''TEMPORARY''
            GROUP BY vp.name,
                vp.con_id,
                f.file_name,
                t.tablespace_name,
                f.status,
                f.autoextensible,
                f.blocks,
                f.maxblocks,
                f.user_blocks,
                f.increment_by,
                t.block_size,
                t.status,
                t.contents
        ) dbf ON 1 = 1
        WHERE d.database_role = ''PRIMARY'''
                    bulk collect into xx;
                    if xx.count >= 1 then
                        for i in 1 .. xx.count loop
                            dbms_output.put_line(xx(i));
                        end loop;
                    end if;
                exception
                    when others then
                        for cur1 in (select upper(name) name from  v$database) loop
                            dbms_output.put_line(cur1.name || '| Debug (121) 2: ' ||sqlerrm);
                        end loop;
                end;
            END;
/
            set serverout off;

'@
        Write-Output $query_tablespace
    } elseif ($DBVERSION -gt 102000) {
        $query_tablespace = @'
          prompt <<<oracle_tablespaces:sep(124)>>>;
          SET SERVEROUTPUT ON feedback off
          DECLARE
              type x is table of varchar2(20000) index by pls_integer;
              xx x;
          begin
              begin
                  execute immediate 'select upper(i.instance_name)
                      || ''|'' || file_name ||''|''|| tablespace_name ||''|''|| fstatus ||''|''|| AUTOEXTENSIBLE
                      ||''|''|| blocks ||''|''|| maxblocks ||''|''|| USER_BLOCKS ||''|''|| INCREMENT_BY
                      ||''|''|| ONLINE_STATUS ||''|''|| BLOCK_SIZE
                      ||''|''|| decode(tstatus,''READ ONLY'', ''READONLY'', tstatus) || ''|'' || free_blocks
                      ||''|''|| contents
                      ||''|''|| iversion
                    from v$database d , v$instance i, (
                        select f.file_name, f.tablespace_name, f.status fstatus, f.AUTOEXTENSIBLE,
                        f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY,
                        f.ONLINE_STATUS, t.BLOCK_SIZE, t.status tstatus, nvl(sum(fs.blocks),0) free_blocks, t.contents,
                        (select version from v$instance) iversion
                        from dba_data_files f, dba_tablespaces t, dba_free_space fs
                        where f.tablespace_name = t.tablespace_name
                        and f.file_id = fs.file_id(+)
                        group by f.file_name, f.tablespace_name, f.status, f.autoextensible,
                        f.blocks, f.maxblocks, f.user_blocks, f.increment_by, f.online_status,
                        t.block_size, t.status, t.contents)
               where d.database_role = ''PRIMARY'''
                  bulk collect into xx;
                  if xx.count >= 1 then
                      for i in 1 .. xx.count loop
                          dbms_output.put_line(xx(i));
                      end loop;
                  end if;
              exception
                  when others then
                      for cur1 in (select upper(name) name from  v$database) loop
                          dbms_output.put_line(cur1.name || '| Debug (102) 1: ' ||sqlerrm);
                      end loop;
              end;
          END;
/

          DECLARE
              type x is table of varchar2(20000) index by pls_integer;
              xx x;
          begin
              begin
                  execute immediate 'select upper(i.instance_name)
              || ''|'' || dbf.file_name
              || ''|'' || dbf.tablespace_name
              || ''|'' || dbf.fstatus
              || ''|'' || dbf.AUTOEXTENSIBLE
              || ''|'' || dbf.blocks
              || ''|'' || dbf.maxblocks
              || ''|'' || dbf.USER_BLOCKS
              || ''|'' || dbf.INCREMENT_BY
              || ''|'' || dbf.ONLINE_STATUS
              || ''|'' || dbf.BLOCK_SIZE
              || ''|'' || decode(tstatus,''READ ONLY'', ''READONLY'', tstatus)
              || ''|'' || dbf.free_blocks
              || ''|'' || ''TEMPORARY''
              || ''|'' || i.version
       FROM v$database d
       JOIN v$instance i ON 1 = 1
       JOIN (
             SELECT vp.name,
                    f.file_name,
                    t.tablespace_name,
                    f.status fstatus,
                    f.autoextensible,
                    f.blocks,
                    f.maxblocks,
                    f.user_blocks,
                    f.increment_by,
                    ''ONLINE'' online_status,
                    t.block_size,
                    t.status tstatus,
                    f.blocks - nvl(SUM(tu.blocks),0) free_blocks,
                    t.contents
             FROM dba_tablespaces t
             JOIN ( SELECT 0
                         ,name
                   FROM v$database
                  ) vp ON 1=1
             LEFT OUTER JOIN dba_temp_files f ON t.tablespace_name = f.tablespace_name
             LEFT OUTER JOIN gv$tempseg_usage tu ON f.tablespace_name = tu.tablespace
                                                  AND f.RELATIVE_FNO = tu.SEGRFNO#
             WHERE t.contents = ''TEMPORARY''
             GROUP BY vp.name,
                      f.file_name,
                      t.tablespace_name,
                      f.status,
                      f.autoextensible,
                      f.blocks,
                      f.maxblocks,
                      f.user_blocks,
                      f.increment_by,
                      t.block_size,
                      t.status,
                      t.contents
            ) dbf ON 1 = 1'
                  bulk collect into xx;
                  if xx.count >= 1 then
                      for i in 1 .. xx.count loop
                          dbms_output.put_line(xx(i));
                      end loop;
                  end if;
              exception
                  when others then
                      for cur1 in (select upper(name) name from  v$database) loop
                          dbms_output.put_line(cur1.name || '| Debug (102) 2: ' ||sqlerrm);
                      end loop;
              end;
          END;
/
          set serverout off;

'@
        Write-Output $query_tablespace
     } elseif ($DBVERSION -gt 92000) {
        $query_tablespace = @'
          prompt <<<oracle_tablespaces:sep(124)>>>;
          select upper(d.NAME) || '|' || file_name ||'|'|| tablespace_name ||'|'|| fstatus ||'|'|| AUTOEXTENSIBLE
                  ||'|'|| blocks ||'|'|| maxblocks ||'|'|| USER_BLOCKS ||'|'|| INCREMENT_BY
                  ||'|'|| ONLINE_STATUS ||'|'|| BLOCK_SIZE
                  ||'|'|| decode(tstatus,'READ ONLY', 'READONLY', tstatus) || '|' || free_blocks
                  ||'|'|| contents
           from v$database d , (
                    select f.file_name, f.tablespace_name, f.status fstatus, f.AUTOEXTENSIBLE,
                    f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY,
                    'ONLINE' ONLINE_STATUS, t.BLOCK_SIZE, t.status tstatus, nvl(sum(fs.blocks),0) free_blocks, t.contents
                    from dba_data_files f, dba_tablespaces t, dba_free_space fs
                    where f.tablespace_name = t.tablespace_name
                    and f.file_id = fs.file_id(+)
                    group by f.file_name, f.tablespace_name, f.status, f.autoextensible,
                    f.blocks, f.maxblocks, f.user_blocks, f.increment_by, 'ONLINE',
                    t.block_size, t.status, t.contents
                    UNION
                    select f.file_name, f.tablespace_name, 'ONLINE' status, f.AUTOEXTENSIBLE,
                    f.blocks, f.maxblocks, f.USER_BLOCKS, f.INCREMENT_BY, 'TEMP',
                    t.BLOCK_SIZE, 'TEMP' status, sum(sh.blocks_free) free_blocks, 'TEMPORARY'
                    from v$thread th, dba_temp_files f, dba_tablespaces t, v$temp_space_header sh
                    WHERE f.tablespace_name = t.tablespace_name and f.file_id = sh.file_id
                    GROUP BY th.instance, f.file_name, f.tablespace_name, 'ONLINE',
                    f.autoextensible, f.blocks, f.maxblocks, f.user_blocks, f.increment_by,
                    'TEMP', t.block_size, t.status);
select * from v$instance;

'@

        Write-Output $query_tablespace
    }

}

################################################################################
# SQL for Dataguard Statistics
################################################################################

Function sql_dataguard_stats {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
     if ($DBVERSION -gt 102000) {
        $query_dataguard_stats = @'
          prompt <<<oracle_dataguard_stats:sep(124)>>>;
          SELECT upper(i.instance_name)
                 ||'|'|| upper(d.DB_UNIQUE_NAME)
                 ||'|'|| d.DATABASE_ROLE
                 ||'|'|| ds.name
                 ||'|'|| ds.value
                 ||'|'|| d.SWITCHOVER_STATUS
                 ||'|'|| d.DATAGUARD_BROKER
                 ||'|'|| d.PROTECTION_MODE
                 ||'|'|| d.FS_FAILOVER_STATUS
                 ||'|'|| d.FS_FAILOVER_OBSERVER_PRESENT
                 ||'|'|| d.FS_FAILOVER_OBSERVER_HOST
                 ||'|'|| d.FS_FAILOVER_CURRENT_TARGET
                 ||'|'|| ms.status
          FROM v$database d
          JOIN v$parameter vp on 1=1
          JOIN v$instance i on 1=1
          left outer join V$dataguard_stats ds on 1=1
          left outer join v$managed_standby ms on ms.process = 'MRP0'
          WHERE vp.name = 'log_archive_config'
          AND   vp.value is not null
          ORDER BY 1;

'@
        Write-Output $query_dataguard_stats
    } else {
        $query_dataguard_stats = @'
          prompt <<<oracle_dataguard_stats:sep(124)>>>;
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
              ORDER BY 1;

'@

        Write-Output $query_dataguard_stats
    }
}

################################################################################
# SQL for Recovery status
################################################################################

Function sql_recovery_status {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_recovery_status = @'
          prompt <<<oracle_recovery_status:sep(124)>>>;
          SELECT upper(i.instance_name)
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
                 ||'|'|| vb.STATUS
                 ||'|'|| round((sysdate-vb.TIME)*24*60*60)
          FROM V$datafile_header dh
          JOIN v$database d on 1=1
          JOIN v$instance i on 1=1
          JOIN v$backup vb on 1=1
          LEFT OUTER JOIN V$PDBS vp on dh.con_id = vp.con_id
          WHERE vb.file# = dh.file#
          ORDER BY dh.file#;

'@
        Write-Output $query_recovery_status
    } elseif ($DBVERSION -gt 101000) {
        $query_recovery_status = @'
          prompt <<<oracle_recovery_status:sep(124)>>>;
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
              ORDER BY dh.file#;

'@
        Write-Output $query_recovery_status
    } elseif ($DBVERSION -gt 92000) {
          $query_recovery_status = @'
          prompt <<<oracle_recovery_status:sep(124)>>>
          SELECT upper(d.NAME)
                     ||'|'|| d.NAME
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
              ORDER BY dh.file#;

'@

        Write-Output $query_recovery_status
    }
}

################################################################################
# SQL for RMAN Backup information
################################################################################

Function sql_rman {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_rman = @'
          prompt <<<oracle_rman:sep(124)>>>;
          select /* check_mk rman1 */ upper(name)
                 || '|'|| 'COMPLETED'
                 || '|'|| to_char(COMPLETION_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| to_char(COMPLETION_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| case when INCREMENTAL_LEVEL IS NULL
                          then 'DB_FULL'
                          else 'DB_INCR'
                          end
                 || '|'|| INCREMENTAL_LEVEL
                 || '|'|| round(((sysdate-COMPLETION_TIME) * 24 * 60), 0)
                 || '|'|| INCREMENTAL_CHANGE#
            from (select upper(i.instance_name) name
                       , bd2.INCREMENTAL_LEVEL, bd2.INCREMENTAL_CHANGE#, min(bd2.COMPLETION_TIME) COMPLETION_TIME
                  from (select bd.file#, bd.INCREMENTAL_LEVEL, max(bd.COMPLETION_TIME) COMPLETION_TIME
                        from v$backup_datafile bd
                        join v$datafile_header dh on dh.file# = bd.file#
                        where dh.status = 'ONLINE'
                          and dh.con_id <> 2
                        group by bd.file#, bd.INCREMENTAL_LEVEL
                                       ) bd
                 join v$backup_datafile bd2 on bd2.file# = bd.file#
                                           and bd2.COMPLETION_TIME = bd.COMPLETION_TIME
                 join v$database vd on vd.RESETLOGS_CHANGE# = bd2.RESETLOGS_CHANGE#
                 join v$instance i on 1=1
                 group by upper(i.instance_name)
                        , bd2.INCREMENTAL_LEVEL
                        , bd2.INCREMENTAL_CHANGE#
                 order by name, bd2.INCREMENTAL_LEVEL);

          select /* check_mk rman2 */ name
                || '|' || 'COMPLETED'
                || '|'
                || '|' || to_char(CHECKPOINT_TIME, 'yyyy-mm-dd_hh24:mi:ss')
                || '|' || 'CONTROLFILE'
                || '|'
                || '|' || round((sysdate - CHECKPOINT_TIME) * 24 * 60)
                || '|' || '0'
          from (select upper(i.instance_name) name
                      ,max(bcd.CHECKPOINT_TIME) CHECKPOINT_TIME
                from v$database d
                join V$BACKUP_CONTROLFILE_DETAILS bcd on d.RESETLOGS_CHANGE# = bcd.RESETLOGS_CHANGE#
                join v$instance i on 1=1
                group by upper(i.instance_name)
               );

          select /* check_mk rman3 */ name
                 || '|COMPLETED'
                 || '|'|| to_char(sysdate, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| to_char(completed, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|ARCHIVELOG||'
                 || round((sysdate - completed)*24*60,0)
                 || '|'
          from (
                select upper(i.instance_name) name
                     , max(a.completion_time) completed
                     , case when a.backup_count > 0 then 1 else 0 end
                from v$archived_log a, v$database d, v$instance i
                where a.backup_count > 0
                      and a.dest_id in
                      (select b.dest_id
                       from v$archive_dest b
                       where b.target = 'PRIMARY'
                         and b.SCHEDULE = 'ACTIVE'
                      )
                group by d.NAME, i.instance_name
                       , case when a.backup_count > 0 then 1 else 0 end);

'@
        Write-Output $query_rman
    } elseif ($DBVERSION -gt 102000) {
        $query_rman = @'
          prompt <<<oracle_rman:sep(124)>>>;
          select /* check_mk rman1 */ upper(name)
                 || '|'|| 'COMPLETED'
                 || '|'|| to_char(COMPLETION_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| to_char(COMPLETION_TIME, 'YYYY-mm-dd_HH24:MI:SS')
                 || '|'|| case when INCREMENTAL_LEVEL IS NULL
                          then 'DB_FULL'
                          else 'DB_INCR'
                          end
                 || '|'|| INCREMENTAL_LEVEL
                 || '|'|| round(((sysdate-COMPLETION_TIME) * 24 * 60), 0)
                 || '|'|| INCREMENTAL_CHANGE#
            from (select upper(i.instance_name) name
                       , bd2.INCREMENTAL_LEVEL, bd2.INCREMENTAL_CHANGE#, min(bd2.COMPLETION_TIME) COMPLETION_TIME
                  from (select bd.file#, bd.INCREMENTAL_LEVEL, max(bd.COMPLETION_TIME) COMPLETION_TIME
                        from v$backup_datafile bd
                        join v$datafile_header dh on dh.file# = bd.file#
                        where dh.status = 'ONLINE'
                        group by bd.file#, bd.INCREMENTAL_LEVEL
                                       ) bd
                 join v$backup_datafile bd2 on bd2.file# = bd.file#
                                           and bd2.COMPLETION_TIME = bd.COMPLETION_TIME
                 join v$database vd on vd.RESETLOGS_CHANGE# = bd2.RESETLOGS_CHANGE#
                 join v$instance i on 1=1
                 group by upper(i.instance_name)
                        , bd2.INCREMENTAL_LEVEL
                        , bd2.INCREMENTAL_CHANGE#
                 order by name, bd2.INCREMENTAL_LEVEL);

'@
        Write-Output $query_rman
    } elseif ($DBVERSION -gt 92000) {
        $query_rman = @'
          prompt <<<oracle_rman:sep(124)>>>;
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
                group by d.name, case when a.backup_count > 0 then 1 else 0 end);

'@
        Write-Output $query_rman
    }
}

################################################################################
# SQL for Flash Recovery Area information
################################################################################

Function sql_recovery_area {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 102000) {
        $query_recovery_area = @'
          prompt <<<oracle_recovery_area:sep(124)>>>;
          select upper(i.instance_name)
                 ||'|'|| round((SPACE_USED-SPACE_RECLAIMABLE)/
                           (CASE NVL(SPACE_LIMIT,1) WHEN 0 THEN 1 ELSE SPACE_LIMIT END)*100)
                 ||'|'|| round(SPACE_LIMIT/1024/1024)
                 ||'|'|| round(SPACE_USED/1024/1024)
                 ||'|'|| round(SPACE_RECLAIMABLE/1024/1024)
                 ||'|'|| d.FLASHBACK_ON
          from V$RECOVERY_FILE_DEST, v$database d, v$instance i;

'@
        Write-Output $query_recovery_area
    }
}

################################################################################
# SQL for UNDO information
################################################################################

Function sql_undostat {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_undostat = @'
          prompt <<<oracle_undostat:sep(124)>>>;
          select decode(vp.con_id, null, upper(i.INSTANCE_NAME)
                           ,upper(i.INSTANCE_NAME || '.' || vp.name))
                 ||'|'|| ACTIVEBLKS
                 ||'|'|| MAXCONCURRENCY
                 ||'|'|| TUNED_UNDORETENTION
                 ||'|'|| maxquerylen
                 ||'|'|| NOSPACEERRCNT
          from v$instance i
          join
              (select * from v$undostat
                where TUNED_UNDORETENTION > 0
               order by end_time desc
               fetch next 1 rows only
              ) u on 1=1
          left outer join v$pdbs vp on vp.con_id = u.con_id;

'@
        Write-Output $query_undostat
    } elseif ($DBVERSION -gt 102000) {
        $query_undostat = @'
          prompt <<<oracle_undostat:sep(124)>>>;
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
                  );

'@
        Write-Output $query_undostat
    } elseif ($DBVERSION -gt 92000) {
        # TUNED_UNDORETENTION and ACTIVEBLKS are not available in Oracle <=9.2!
        # we set a -1 for filtering in check_undostat
        $query_undostat = @'
          prompt <<<oracle_undostat:sep(124)>>>;
          select upper(i.INSTANCE_NAME)
                     ||'|-1'
                     ||'|'|| MAXCONCURRENCY
                     ||'|-1'
                     ||'|'|| maxquerylen
                     ||'|'|| NOSPACEERRCNT
                  from v$instance i,
                  (select * from (select *
                                  from v$undostat order by end_time desc
                                 )
                            where rownum = 1
                  );

'@
        Write-Output $query_undostat
    }
}

################################################################################
# SQL for resumable information
################################################################################

Function sql_resumable {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    $query_resumable = @'
          prompt <<<oracle_resumable:sep(124)>>>;
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
          from v$instance i;

'@
    Write-Output $query_resumable
}

################################################################################
# SQL for scheduler_jobs information
################################################################################

Function sql_jobs {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_scheduler_jobs = @'
          prompt <<<oracle_jobs:sep(124)>>>;
          SET SERVEROUTPUT ON feedback off
          DECLARE
              type x is table of varchar2(20000) index by pls_integer;
              xx x;
          begin
              begin
                  execute immediate 'SELECT upper(vp.name)
                 ||''|''|| j.OWNER
                 ||''|''|| j.JOB_NAME
                 ||''|''|| j.STATE
                 ||''|''|| ROUND((TRUNC(sysdate) + j.LAST_RUN_DURATION - TRUNC(sysdate)) * 86400)
                 ||''|''|| j.RUN_COUNT
                 ||''|''|| j.ENABLED
                 ||''|''|| NVL(j.NEXT_RUN_DATE, to_date(''1970-01-01'', ''YYYY-mm-dd''))
                 ||''|''|| NVL(j.SCHEDULE_NAME, ''-'')
                 ||''|''|| jd.STATUS
          FROM cdb_scheduler_jobs j
          JOIN ( SELECT vp.con_id
                       ,d.name || ''|'' || vp.name name
                   FROM v$containers vp
                   JOIN v$database d on 1=1
                  WHERE d.cdb = ''YES'' and vp.con_id <> 2
                    AND d.database_role = ''PRIMARY''
                    AND d.open_mode = ''READ WRITE''
                UNION ALL
                 SELECT 0, name
                   FROM v$database d
                  WHERE d.database_role = ''PRIMARY''
                    AND d.open_mode = ''READ WRITE''
           ) vp on j.con_id = vp.con_id
                       left outer join (SELECT con_id, owner, job_name, max(LOG_ID) log_id
                              FROM cdb_scheduler_job_run_details dd
                             group by con_id, owner, job_name
                           ) jm on  jm.JOB_NAME = j.JOB_NAME
                               and jm.owner=j.OWNER
                               and jm.con_id = j.con_id
          left outer join cdb_scheduler_job_run_details jd
                          on  jd.con_id = jm.con_id
                          AND jd.owner = jm.OWNER
                          AND jd.JOB_NAME = jm.JOB_NAME
                          AND jd.LOG_ID = jm.LOG_ID
          WHERE not (j.auto_drop = ''TRUE'' and REPEAT_INTERVAL is null)'
                  bulk collect into xx;
                  if xx.count >= 1 then
                      for i in 1 .. xx.count loop
                          dbms_output.put_line(xx(i));
                      end loop;
                  end if;
              exception
                  when others then
                      for cur1 in (select upper(name) name from  v$database) loop
                          dbms_output.put_line(cur1.name || '| Debug (121): ' ||sqlerrm);
                      end loop;
              end;
          END;
          /
          set serverout off;

'@
        Write-Output $query_scheduler_jobs
    } elseif ($DBVERSION -gt 102000) {
        $query_scheduler_jobs = @'
          prompt <<<oracle_jobs:sep(124)>>>;
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
                AND not (j.auto_drop = 'TRUE' and REPEAT_INTERVAL is null);

'@
        Write-Output $query_scheduler_jobs
    }
}

################################################################################
# SQL for Tablespace quotas information
################################################################################

Function sql_ts_quotas {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    $query_ts_quotas = @'
        prompt <<<oracle_ts_quotas:sep(124)>>>;
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
                  order by 1;

'@
    Write-Output $query_ts_quotas
}

################################################################################
# SQL for Oracle Version information
################################################################################

Function sql_version {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    $query_version = @'
        prompt <<<oracle_version:sep(124)>>>;
        select upper(i.INSTANCE_NAME)
        	  || '|' || banner
        	  from v$version, v$instance i
        	  where banner like 'Oracle%';

'@
    Write-Output $query_version
}

################################################################################
# SQL for sql_instance information
################################################################################

Function sql_instance {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    #if ($ORACLE_SID.substring(0,1) -eq "+") {
    if ("This" -eq "That") {
        $query_instance = @'
          prompt <<<oracle_instance:sep(124)>>>;
          select upper(i.instance_name)
                     || '|' || i.VERSION
                     || '|' || i.STATUS
                     || '|' || i.LOGINS
                     || '|' || i.ARCHIVER
                     || '|' || round((sysdate - i.startup_time) * 24*60*60)
                     || '|' || '0'
                     || '|' || 'NO'
                     || '|' || 'ASM'
                     || '|' || 'NO'
                     || '|' || i.instance_name
                from v$instance i;

'@
    } else {
        if ($DBVERSION -gt 121000) {
            $query_instance = @'
              prompt <<<oracle_instance:sep(124)>>>;
              select upper(instance_name)
                     || '|' || version
                     || '|' || status
                     || '|' || logins
                     || '|' || archiver
                     || '|' || round((sysdate - startup_time) * 24*60*60)
                     || '|' || dbid
                     || '|' || log_mode
                     || '|' || database_role
                     || '|' || force_logging
                     || '|' || name
                     || '|' || to_char(created, 'ddmmyyyyhh24mi')
                     || '|' || upper(value)
                     || '|' || con_id
                     || '|' || pname
                     || '|' || pdbid
                     || '|' || popen_mode
                     || '|' || prestricted
                     || '|' || ptotal_time
                     || '|' || precovery_status
                     || '|' || round(nvl(popen_time, -1))
                     || '|' || pblock_size
              from(
                  select i.instance_name, i.version, i.status, i.logins, i.archiver
                        ,i.startup_time, d.dbid, d.log_mode, d.database_role, d.force_logging
                        ,d.name, d.created, p.value, vp.con_id, vp.name pname
                        ,vp.dbid pdbid, vp.open_mode popen_mode, vp.restricted prestricted, vp.total_size ptotal_time
                        ,vp.block_size pblock_size, vp.recovery_status precovery_status
                        ,(cast(systimestamp as date) - cast(open_time as date))  * 24*60*60 popen_time
                    from v$instance i
                    join v$database d on 1=1
                    join v$parameter p on 1=1
                    join v$pdbs vp on 1=1
                    where p.name = 'enable_pluggable_database'
                  union all
                  select
                         i.instance_name, i.version, i.status, i.logins, i.archiver
                        ,i.startup_time, d.dbid, d.log_mode, d.database_role, d.force_logging
                        ,d.name, d.created, p.value, 0 con_id, null pname
                        ,0 pdbis, null popen_mode, null prestricted, null ptotal_time
                        ,0 pblock_size, null precovery_status, null popen_time
                    from v$instance i
                    join v$database d on 1=1
                    join v$parameter p on 1=1
                    where p.name = 'enable_pluggable_database'
                    order by con_id
                  );

'@
        } else {
            $query_instance = @'
              prompt <<<oracle_instance:sep(124)>>>;
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
                    from v$instance i, v$database d;

'@
        }
    }
    Write-Output $query_instance
}

################################################################################
# SQL for sql_sessions information
################################################################################

Function sql_sessions {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_sessions = @'
           prompt <<<oracle_sessions:sep(124)>>>;
           SELECT upper(vp.name)
                 || '|' || ltrim(COUNT(1))
                 || decode(vp.con_id
                           , 0, '|'||ltrim(rtrim(LIMIT_VALUE))||'|-1')
           FROM ( SELECT vp.con_id
                     ,i.instance_name || '.' || vp.name name
                  FROM v$containers vp
                  JOIN v$instance i ON 1 = 1
                  JOIN v$database d on 1=1
                  WHERE d.cdb = 'YES' and vp.con_id <> 2
                 UNION ALL
                  SELECT 0, instance_name
                  FROM v$instance
                ) vp
           JOIN v$resource_limit rl on RESOURCE_NAME = 'sessions'
           LEFT OUTER JOIN v$session vs ON vp.con_id = vs.con_id
           GROUP BY vp.name, vp.con_id, rl.LIMIT_VALUE
           ORDER BY 1;

'@
        Write-Output $query_sessions
    } else {
        $query_sessions = @'
          prompt <<<oracle_sessions:sep(124)>>>;
          select upper(i.instance_name)
                  || '|' || CURRENT_UTILIZATION
          from v$resource_limit, v$instance i
          where RESOURCE_NAME = 'sessions';

'@
        Write-Output $query_sessions
    }
}

################################################################################
# SQL for sql_processes information
################################################################################

Function sql_processes {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    $query_processes = @'
        prompt <<<oracle_processes:sep(124)>>>;
        select upper(i.instance_name)
                          || '|' || CURRENT_UTILIZATION
                          || '|' || ltrim(rtrim(LIMIT_VALUE))
                   from v$resource_limit, v$instance i
                   where RESOURCE_NAME = 'processes';

'@
    Write-Output $query_processes
}

################################################################################
# SQL for sql_logswitches information
################################################################################

Function sql_logswitches {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    $query_logswitches = @'
        prompt <<<oracle_logswitches:sep(124)>>>;
        select upper(i.instance_name)
                          || '|' || logswitches
                   from v$instance i ,
                        (select count(1) logswitches
                         from v$loghist h , v$instance i
                         where h.first_time > sysdate - 1/24
                         and h.thread# = i.instance_number);

'@
    Write-Output $query_logswitches
}

################################################################################
# SQL for database lock information
################################################################################

Function sql_locks {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_locks = @'
          prompt <<<oracle_locks:sep(124)>>>;
          select upper(vp.name)
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
          join gv$session bs on bs.inst_id = b.BLOCKING_INSTANCE
                             and bs.sid = b.BLOCKING_SESSION
                             and bs.con_id = b.con_id
          join ( SELECT vp.con_id
                       ,i.instance_name || '.' || vp.name name
             FROM v$containers vp
             JOIN v$instance i ON 1 = 1
             JOIN v$database d on 1=1
             WHERE d.cdb = 'YES' and vp.con_id <> 2
            UNION ALL
             SELECT 0, instance_name
             FROM v$instance
           ) vp on b.con_id = vp.con_id
          where b.BLOCKING_SESSION is not null;

          SELECT upper(i.instance_name || '.' || vp.name)
                 || '|||||||||||||||||'
            FROM v$containers vp
            JOIN v$instance i ON 1 = 1
             JOIN v$database d on 1=1
            WHERE d.cdb = 'YES' and vp.con_id <> 2
           UNION ALL
            SELECT upper(i.instance_name)
                 || '|||||||||||||||||'
            FROM v$instance i;

'@
        Write-Output $query_locks
    } elseif ($DBVERSION -gt 102000){
        $query_locks = @'
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
          where b.BLOCKING_SESSION is not null;
          select upper(i.instance_name)
                 || '|||||||||||||||||'
          from v$instance i;

'@
        Write-Output $query_locks
    }
}

Function sql_locks_old {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 101000) {
        $query_locks = @'
          prompt <<<oracle_locks:sep(124)>>>;
          SET SERVEROUTPUT ON feedback off
DECLARE
    type x is table of varchar2(20000) index by pls_integer;
    xx x;
begin
    begin
        execute immediate 'select upper(i.instance_name)
           || ''|'' || a.sid
           || ''|'' || b.serial#
           || ''|'' || b.machine
           || ''|'' || b.program
           || ''|'' || b.process
           || ''|'' || b.osuser
           || ''|'' || a.ctime
           || ''|'' || decode(c.owner,NULL,''NULL'',c.owner)
           || ''|'' || decode(c.object_name,NULL,''NULL'',c.object_name)
            from V$LOCK a, v$session b, dba_objects c, v$instance i
            where (a.id1, a.id2, a.type)
                       IN (SELECT id1, id2, type
                           FROM GV$LOCK
                           WHERE request>0
                          )
            and request=0
            and a.sid = b.sid
            and a.id1 = c.object_id (+)
            union all
            select upper(i.instance_name) || ''|||||||||''
            from  v$instance i'
        bulk collect into xx;
        if xx.count >= 1 then
            for i in 1 .. xx.count loop
                dbms_output.put_line(xx(i));
            end loop;
        end if;
    exception
        when others then
            for cur1 in (select upper(i.instance_name) instance_name from  v$instance i) loop
                dbms_output.put_line(cur1.instance_name || '|||||||||'||sqlerrm);
            end loop;
    end;
END;
/
set serverout off;

'@
        Write-Output $query_locks
    }
}

################################################################################
# SQL for long active session information
################################################################################

Function sql_longactivesessions {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
    if ($DBVERSION -gt 121000) {
        $query_longactivesessions = @'
          prompt <<<oracle_longactivesessions:sep(124)>>>;
          select upper(vp.name)
                 || '|' || s.sid
                 || '|' || s.serial#
                 || '|' || s.machine
                 || '|' || s.process
                 || '|' || s.osuser
                 || '|' || s.program
                 || '|' || s.last_call_et
                 || '|' || s.sql_id
          from v$session s
          join ( SELECT vp.con_id
                       ,i.instance_name || '.' || vp.name name
             FROM v$containers vp
             JOIN v$instance i ON 1 = 1
             JOIN v$database d on 1=1
             WHERE d.cdb = 'YES' and vp.con_id <> 2
            UNION ALL
             SELECT 0, instance_name
             FROM v$instance
               ) vp on 1=1
          where s.status = 'ACTIVE'
            and s.type != 'BACKGROUND'
            and s.username is not null
            and s.username not in('PUBLIC')
            and s.last_call_et > 60*60;

          SELECT upper(i.instance_name || '.' || vp.name)
                 || '||||||||'
            FROM v$containers vp
            JOIN v$instance i ON 1 = 1
            JOIN v$database d on 1=1
           WHERE d.cdb = 'YES' and vp.con_id <> 2
           UNION ALL
          SELECT upper(i.instance_name)
                 || '||||||||'
            FROM v$instance i;

'@
        Write-Output $query_longactivesessions
     } elseif ($DBVERSION -gt 101000) {
        $query_longactivesessions = @'
          prompt <<<oracle_longactivesessions:sep(124)>>>;
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
              from v$instance i;

'@
        Write-Output $query_longactivesessions
    }
}

################################################################################
# SQL for sql_logswitches information
################################################################################

Function sql_asm_diskgroup {
    Param(
        [Parameter(Mandatory=$true)]
        [int]$DBVERSION
    )
     if ($DBVERSION -gt 112000) {
        $query_asm_diskgroup = @'
          prompt <<<oracle_asm_diskgroup:sep(124)>>>;
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
                from v$asm_diskgroup;

'@
        Write-Output $query_asm_diskgroup
    } elseif ($DBVERSION -gt 101000) {
        $query_asm_diskgroup = @'
          prompt <<<oracle_asm_diskgroup:sep(124)>>>;
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
                     || '|' || 'N'
                     || '|' || name || '/'
                from v$asm_diskgroup;

'@
        Write-Output $query_asm_diskgroup
    }
}

####################################################################################
################ Declare some "real" functions #####################################
####################################################################################

Function Write-DebugOutput {
    Param(
        [string]$Message
    )
    $LogFile = "$MK_TEMPDIR\mk_oracle.log"
    $MyTime=Get-Date -Format o
    if (!(Test-Path -Path $LogFile)) {
        "${MyTime}: Starting new run of mk_oracle.ps1" | Set-Content $LogFile
    }
    if ($DEBUG -gt 0) {"${MyTime}: ${Message}" | Add-Content $LogFile}
}


Function Write-DummySections {
    Write-DebugOutput -Message "Write dummy sections"
    Set-Variable -Name DummySections -Value (New-Object system.collections.arraylist)
    $DummySections.Add($SYNC_SECTIONS) | Out-Null
    $DummySections.Add($ASYNC_SECTIONS) | Out-Null
    $DummySections.Add($SYNC_ASM_SECTIONS) | Out-Null
     $DummySections.Add($ASYNC_ASM_SECTIONS) | Out-Null

    ForEach($SectionType in $DummySections) {
        ForEach($Section in $SectionType) {
            Write-Output "<<<oracle_${section}>>>"
        }
    }
}

Function Get-OracleHome {
    Param(
        [PSObject]$SID
    )
    $Key="HKLM:\SYSTEM\CurrentControlSet\services\OracleService$($SID.name)"
    $Path=(Get-ItemProperty -Path $Key).ImagePath
    Return $Path.SubString(0, $Path.LastIndexOf("\")-4)
}

Function Get-DBVersion {
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$SID
    )
    Return ((Get-SqlPrefix -Type "Version") | sqlplus -L -s "$($SID.connect)")
}

Function Check-Variable {
    Param(
        [string]$MyVariable
    )
    $CheckedVariable = (Get-Variable -Name $MyVariable -ErrorAction SilentlyContinue)
    Return $CheckedVariable
}

Function New-InstanceObject {
    Return New-Object -Type PSObject -Property @{
        "name" = ""
        "user" = ""
        "password" = ""
        "privileges" = ""
        "port" = "1521"
        "hostname" = "localhost"
        "alias" = ""
        "tnsalias" = $null
        "connect" = $null
        "piggybackhost" = ""
        "sync_sections" = (New-Object system.collections.arraylist)
        "sync_asm_sections" = (New-Object system.collections.arraylist)
        "async_sections" = (New-Object system.collections.arraylist)
        "async_asm_sections" = (New-Object system.collections.arraylist)
        "monitor" = $true
        "asm" = $false
        "home" = ""
        "version" = ""
        "mk_tempdir" = ""
        "cache_age" = 600
    }
}

Function Get-SqlPrefix {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Type
    )
    if ($Type -eq "Query") {
        Return @'
            set pages 0 trimspool on;
            set linesize 1024;
            set feedback off;
            whenever OSERROR EXIT failure;
            whenever SQLERROR EXIT failure;

'@
    } elseif ($Type -eq "Version") {
        Return @'
            whenever sqlerror exit failure rollback;
            whenever oserror exit failure rollback;
            SET TRIMOUT ON
            SET TRIMSPOOL ON
            set linesize 1024
            set heading off
            set echo off
            set termout off
            set pagesize 0
            set feedback off
            select replace(version,'.','') from v$instance;
            exit;

'@
    }
}

Function Prepare-RunType {
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$SID,
        [Parameter(Mandatory=$true)]
        [string]$Type
    )
    Write-DebugOutput -Message "Prepare $Type for $($SID.name)"
    if ($SID.asm) {
        if ($Type -eq "Sync_SQLs") {
            $Sections = $SID.sync_asm_sections
        } elseif ($Type -eq "Async_SQLs") {
            $Sections = $SID.async_asm_sections
        }
    } else {
        if ($Type -eq "Sync_SQLs") {
            $Sections = $SID.sync_sections
        } elseif ($Type -eq "Async_SQLs") {
            $Sections = $SID.async_sections
        }
    }
    Return $Sections
}

Function Build-Query {
    Param(
        [Parameter(Mandatory=$true)]
        [array]$Sections,
        [Parameter(Mandatory=$true)]
        [int]$Version
    )
    $Query = ""
    ForEach ($Section in $Sections) {
        $SectionQuery = Invoke-Expression "sql_$Section -DBVERSION $Version"
        $Query = $Query + $SectionQuery
    }
    Return $Query
}

Function Get-InstanceValues {
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Instance,
        [Parameter(Mandatory=$true)]
        [PSObject]$SID,
        [Parameter(Mandatory=$true)]
        [bool]$IsASM
    )
    # Basic Values of instance
    if ($IsASM) {
        $SID.asm = $true
        $SID.name = $Instance.Name.Replace("OracleASMService", "").ToUpper()
        $SID.sync_asm_sections = $SYNC_ASM_SECTIONS
        $SID.async_asm_sections = $ASYNC_ASM_SECTIONS
        $SID.home = (Get-OracleHome -SID $SID)
        $SID.mk_tempdir = $MK_TEMPDIR
        $SID.cache_age = $CACHE_MAXAGE
        Write-DebugOutput -Message "Found ASM instance $($SID.name) with OracleHome: $($SID.home)"
        # Example: ASMUSER = @("myUser", "myPassword", "myOptionalSYSASM", "myOptionalHostname", "myOptionalPort", "myOptionalAlias")
        $SIDUSER = (Check-Variable -MyVariable "ASMUSER_$($SID.name)")
        if ($null -ne $SIDUSER.value) {
            Write-DebugOutput "Found explicit ASM connect for $($SID.name)"
            $USER = $SIDUSER
            Write-DebugOutput -Message "Using $($USER[0]) with ******** as credentials"
        } else {
            $USER = $ASMUSER
        }
    } else {
        $SID.name = $instance.Name.replace("OracleService", "").ToUpper()
        $SID.sync_sections = $SYNC_SECTIONS
        $SID.async_sections = $ASYNC_SECTIONS
        $SID.home = (Get-OracleHome -SID $SID)
        $SID.mk_tempdir = $MK_TEMPDIR
        $SID.cache_age = $CACHE_MAXAGE
        Write-DebugOutput -Message "Found DB instance $($SID.name) with OracleHome: $($SID.home)"
        # Example: DBUSER = @("myUser", "myPassword", "myOptionalSYSDBA", "myOptionalHostname", "myOptionalPort", "myOptionalAlias")
        Write-DebugOutput -Message "DBUSER: $($DBUSER[0]), ********, $($DBUSER[2])"
        $SIDUSER = (Check-Variable -MyVariable "DBUSER_$($SID.name)")
        if ($null -ne $SIDUSER.value) {
            Write-DebugOutput "Found explicit DB connect for $($SID.name)"
            $USER = $SIDUSER
            Write-DebugOutput -Message "Using $($DBUSER[0]) with ******** as credentials"
        } else {
            $USER = $DBUSER
        }

    }
    # Credentials for instances
    if ($USER) {
        $SID.user = $USER[0]
        $SID.password = $USER[1]
        if ($null -ne $USER[2] -And $USER -ne "") {
            $SID.privileges = " as $($USER[2])"
        }
        if ($null -ne $USER[3] -And $USER[3] -ne "") {
            $SID.hostname = $USER[3]
        }
        if ($null -ne $USER[4] -And $USER[4] -ne "") {
            $SID.port = $USER[4]
        }
        if ($null -ne $USER[5] -And $USER[5] -ne "") {
            $SID.alias = $USER[5]
        }
    } else {
        Write-DebugOutput "No login data provided for $($SID.name). Will not monitor this instance"
        $SID.monitor = $false
    }
    # Build connection strings for instance
    if ($IsASM) {
        $SID.tnsalias = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$($SID.hostname))(PORT=$($SID.port)))(CONNECT_DATA=(SERVICE_NAME=+ASM)(INSTANCE_NAME=$($SID.name))(UR=A)))"
        $SID.connect = "$($SID.user)/$($SID.password)@$($SID.tnsalias)$($SID.privileges)"
        $SID.version = (Get-DBVersion -SID $SID)
        Write-DebugOutput "Set '$($SID.user)/********@$($SID.tnsalias)$($SID.privileges)' as default connect for $($SID.name). ASM version is $($SID.version)"
    } else {
         $SID.tnsalias = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$($SID.hostname))(PORT=$($SID.port)))(CONNECT_DATA=(SID=$($SID.name))))"
         $SID.connect = "$($SID.user)/$($SID.password)@$($SID.tnsalias)$($SID.privileges)"
         $SID.version = (Get-DBVersion -SID $SID)
         Write-DebugOutput "Set '$($SID.user)/********@$($SID.tnsalias)$($SID.privileges)' as default connect for $($SID.name). DB Version is $($SID.version)"
    }
    Return $SID
}

Function Get-InstanceSections {
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$SID
    )
    # Check if we should not monitor this SID
    $ExcludeSections = (Check-Variable -MyVariable "EXCLUDE_$($SID.name)")
    if ($null -eq $ExcludeSections) {
        $ExcludeSections = @()
    }
    if ($ONLY_SIDS.count -ne 0 -Or $ExcludeSections.count -ne 0) {
        If ($ExcludeSections -Contains "ALL") {
            Write-DebugOutput -Message "All sections of $($SID.name) are excluded. Skipping this SID."
            $SID.monitor = $false
        } elseif ($ONLY_SIDS -Contains $SID.name) {
            Write-DebugOutput -Message "$($SID.name) is in $ONLY_SIDS."
            $SID.monitor = $false
        } elseif ($ExcludeSections.count -ge 1 -AND $SID.asm -eq $false) {
            Write-DebugOutput -Message "Remove excluded sections from $($SID.name): $ExcludeSections"
            ForEach($Section in $ExcludeSections) {
                if (!$SID.asm -And $SID.sync_sections -contains $Section) {
                    $SID = $SID | Where-Object ($_.sync_sections -ne $Section)
                } elseif ($SID.asm -And $SID.async_sections -contains $Section) {
                    $SID = $SID | Where-Object ($_.async_sections -ne $Section)
                }
            }
        } elseif ($ExcludeSections.count -ge 1 -And $SID.asm -eq $true) {
            Write-DebugOutput -Message "Remove excluded sections from $($SID.name): $ExcludeSections"
            ForEach($Section in $ExcludeSections) {
                if (!$SID.asm -And $SID.sync_asm_sections -contains $Section) {
                    $SID = $SID | Where-Object ($_.sync_asm_sections -ne $Section)
                } elseif ($SID.asm -And $SID.async_asm_sections -contains $Section) {
                    $SID = $SID | Where-Object ($_.sync_sections -ne $Section)
                }
            }
        }
    }
    Return $SID
}

####################################################################################
################ Initialize variables and environment ##############################
####################################################################################

# The following line ensures that the output of the files generated by calling
# Oracle SQLplus through Powershell are not limited to 80 character width. The
# 80 character width limit is the default
$Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size (512, 150)

Set-Variable -Name SYNC_SECTIONS -Scope Script -Value @("instance", "sessions", "logswitches", "undostat", "recovery_area", "processes", "recovery_status", "longactivesessions", "dataguard_stats", "performance")
Set-Variable -Name SYNC_ASM_SECTIONS -Scope Script -Value @("instance")
Set-Variable -Name ASYNC_SECTIONS -Scope Script -Value @("tablespaces", "rman", "jobs", "ts_quotas", "resumable", "locks")
Set-Variable -Name ASYNC_ASM_SECTIONS -Scope Script -Value @("asm_diskgroup")
Set-Variable -Name DEBUG -Scope Script -Value 0
Set-Variable -Name CACHE_MAXAGE -Scope Script -Value 600
Set-Variable -Name ONLY_SIDS -Scope Script -Value (New-Object system.collections.arraylist)

####################################################################################
################ Write dummy sections and get running instances ####################
####################################################################################

Write-DummySections

$RunningInstances=(Get-Service -Name "Oracle*Service*" -include "OracleService*", "OracleASMService*" | Where-Object {$_.status -eq "Running"})
Write-DebugOutput -Message "Found instances: $($RunningInstances.DisplayName)"

if (($RunningInstances | Measure-Object).count -eq 0) {
    Write-DebugOutput "Found no running Oracle DB instances. Ending script."
    Exit
}

####################################################################################
################ Import user config ################################################
####################################################################################

if (!$env:MK_CONFDIR) {
    Set-Variable -Name MK_CONFDIR -Value "C:\Program Files (x86)\check_mk\config"
}
if (!$env:MK_TEMPDIR) {
    Set-Variable -Name MK_TEMPDIR -Scope Script -Value "C:\Program Files (x86)\check_mk\temp"
}

Set-Variable -Name ConfigFile -Value "${MK_CONFDIR}\mk_oracle_cfg.ps1"
if (Test-Path -Path "$ConfigFile") {
    Write-DebugOutput "${ConfigFile} found, reading"
    . ${ConfigFile}
} else {
    Write-DebugOutput "${ConfigFile} not found"
}

####################################################################################
################ This is the main part of this Script ##############################
####################################################################################

# Prepare Connects to instances
Set-Variable -Name Instances -Value (New-Object system.collections.arraylist)

ForEach($Instance in $RunningInstances) {
    $SID = New-InstanceObject
    Write-DebugOutput -Message "Instance: $($Instance.name)"
    if ($Instance.name -like "OracleASMService*") {
        $SID = Get-InstanceValues -SID $SID -Instance $Instance -IsASM $true
    } else {
        $SID = Get-InstanceValues -SID $SID -Instance $Instance -IsASM $false
    }
    $SID = Get-InstanceSections -SID $SID
    # Add Instance to the list
    if ($SID.monitor) {
        Write-DebugOutput -Message "Add $($SID.name) to list of instances to connect to."
        $Instances.Add($SID) | Out-Null
    }
}

# Do the sync stuff on all instances (including ASM)
Set-Variable -Name SyncJobs -Value (New-Object system.collections.arraylist)
ForEach ($Instance in $Instances) {
    $Sections = Prepare-RunType -SID $Instance -Type "Sync_SQLs"
    Write-DebugOutput -Message "Running sync sections on $($Instance.name): $Sections"
    $SyncQuery = Build-Query -Sections $Sections -Version $Instance.version
    $SyncQuery = (Get-SqlPrefix -Type "Query") + $SyncQuery
    Start-Job -Name "$($Instance.name)-Sync" -ArgumentList $SyncQuery,$Instance -ScriptBlock {
        Param(
        [Parameter(Mandatory=$true)]
        [string]$Statement,
        [Parameter(Mandatory=$true)]
        [PSObject]$SID
    )

    $env:ORACLE_SID = $SID.name

    try {
        $QueryResult = $Statement | sqlplus -L -s "$($SID.connect)"
        if ($LastExitCode -eq 0) {
            Write-Output $QueryResult
        } else {
            $QueryResult = "$($SID.name)|FAILURE|" + ($QueryResult | Select-String -Pattern "ERROR")
            Write-Output "<<<oracle_instance:sep(124)>>>"
            Write-Output $QueryResult
        }
    } catch {
        $QueryResult = "$($SID.name)|FAILURE|" + ($QueryResult | Select-String -Pattern "ERROR")
        Write-Output "<<<oracle_instance:sep(124)>>>"
        Write-Output $QueryResult
    }
    } | Out-Null
    $SyncJobs.Add("$($Instance.name)-Sync") | Out-Null
}
Wait-Job -Name $SyncJobs | Out-Null
ForEach ($Job in $SyncJobs) {
    $Result = Receive-Job -Name "$Job"
    Write-Output $Result
    Remove-Job -Name "$Job"
}

# Do the same as above for async sections
ForEach ($Instance in $Instances) {
    if (Get-Job -Name "$($SID.name)-Async") {
        $LastRun = Get-Job -Name "$($SID.name)-Async"
    } else {
        $LastRun = $false
    }
    if ($LastRun -And $LastRun.state -ne "Running") {
        Remove-Job -Name "$($SID.name)-Async"
    }
    $Sections = Prepare-Runtype -SID $Instance -Type "Async_SQLs"
    Write-DebugOutput -Message "Running async sections on $($Instance.name): $Sections"
    $AsyncQuery = Build-Query -Sections $Sections -Version $Instance.version
    $ASyncQuery = (Get-SqlPrefix -Type "Query") + $ASyncQuery
    $OutputPath = "$MK_Tempdir\Async_SQLs.$($Instance.name).txt"
    $RunAsyncJob = $true
    if (Test-Path -Path $OutputPath) {
        $FileAge = (Get-Item $OutputPath).LastWriteTime
        $MaxAge = New-Timespan -Days 0 -Hours 0 -Minutes ($($Instance.cache_age) / 60)
        if (((Get-Date) - $FileAge) -lt $MaxAge) {
            Get-Content -Path $OutputPath
            $RunAsyncJob = $false
        }
    }
    if ($RunAsyncJob) {
        Start-Job -Name "$($Instance.name)-Async" -ArgumentList $AsyncQuery,$OutputPath,$Instance -ScriptBlock {
            Param(
                [Parameter(Mandatory=$true)]
                [string]$Statement,
                [Parameter(Mandatory=$true)]
                [string]$OutputPath,
                [Parameter(Mandatory=$true)]
                [PSObject]$SID
            )

            $env:ORACLE_SID = $SID.name

            try {
                $QueryResult = $Statement | sqlplus -L -s "$($SID.connect)"
                if ($LastExitCode -eq 0) {
                    $QueryResult | Set-Content $OutputPath
                } else {
                    $QueryResult = "$($SID.name)|FAILURE|" + ($QueryResult | Select-String -Pattern "ERROR")
                    Set-Content "<<<oracle_instance:sep(124)>>>"
                    Add-Content $QueryResult
                }
            } catch {
                $QueryResult = "$($SID.name)|FAILURE|" + ($QueryResult | Select-String -Pattern "ERROR")
                Set-Content "<<<oracle_instance:sep(124)>>>"
                Add-Content $QueryResult
            }
        }
    }
}