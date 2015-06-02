#!/usr/bin/perl -w
#######################################################
# Create: P.Linux
# Function: Check MySQL Status
# Usage: Run on any computer with Perl
# License: GPL v2
# Site: PengLiXun.COM
# Modify: 
# P.Linux 2010-01-22 
#    -Create 0.1 Alpha
#
# P.Linux 2010-01-26 
#    -Update 0.2 Alpha
#    Add color
#    Add stat Monitor
#
# P.Linux 2010-01-27
#    -Update 0.3 Alpha 
#    Move all traffic infromation to one area
#    Add simple warning function using color
#
# P.Linux 2010-01-28
#    +Update 0.5 beta
#    Split more modules ,like display_stat_*(),
#    calc_stat_*() and display_vars_*()
#    Add tmp tables and queries values
#
# P.Linux 2010-02-01
#    +Update 0.9 beta
#    Add some innodb statistics
#
# P.Linux 2010-02-04
#    *Update 1.0 Release
#    Add -n control display
#    Add type 3 calc_val to calc min values
#    Test all functions
#
# P.Linux 2010-02-09
#    *Update 1.01 Release
#    Fix some small bugs
#    Use variables after check if defined
#
# P.Linux 2010-03-05
#    +Update 1.1 Release
#    Add Windows Support
#    Add Insert/Update/Delete Statics
# 
# P.Linux 2010-05-14
#    *Update 1.1.1 Release
#    Fix a bug about connect
#######################################################
# Sidney.Chen 2015-05-11
#    *Update 1.1.2 Release
#    Add InnoDB Disk Write and Log Statistics
#######################################################
use strict;
use DBI;
#use Curses;
use Switch;
use DBD::mysql;
use Getopt::Std;
use Term::ANSIColor;
use vars qw($opt_i $opt_c $opt_n $opt_d $opt_h $opt_u $opt_p);
#######################################################

# Catch Ctrl+C Quit
# 捕捉 Ctrl+C
$SIG{TERM}=$SIG{INT} = \&quit;

# Set env var from shell profile
# 为Shell设置环境变量
set_env();

# Autoflush for print
# 为打印自动刷新
$| = 1;

# Global Status Var
# 全局状态变量
my $now;
my $status_res;
my @status;
my $os_win;

# CmdLine Option vars
# 命令行参数变量
my($interval, $count, $name, $disable, $host, $user, $pwd);
my $names;
my $disables;

# Version
my $version='1.1.2 Release';

#######################################################
# Main Program
# 主程序
#######################################################

# Get CmdLine Options
# 获取命令行参数
&get_option();

# Connect to database via DBI
# 通过DBI连接数据库
my $dbconn;

eval{
    local $SIG{ALRM} = sub { die "连接数据库超时\n" };
    alarm 20;
    $dbconn = DBI->connect("DBI:mysql:host=$host", $user, $pwd, {'RaiseError' => 1}) 
    or die "Connect to MySQL database error:". DBI->errstr;
    alarm 0;
};

if($@){
    printf "Connect to MySQL database error:".$@."\n";
    exit;
}

# Do loop
# 执行循环
&do_loop();

# Disconnect from MySQL
# 从数据库断开连接
$dbconn->disconnect;

#######################################################
# Print Usage
# 打印使用方法
#######################################################
sub print_usage () {
        printf <<EOF
 NAME:
        mystat

 SYNTAX:
        mystat -i interval -c count -n statname

 FUNCTION:
        Report Status Information of MySQL

 PARAMETER:
     -i    interval interval time,default 1 seconds
     -c    count        times
     -n    name         statistics name
           contain: all,basic,innodb,myisam
                    traffic - Network Traffic
                    kbuffer - Key Buffer
                    qcache  - Query Cache
                    thcache - Thread Cache
                    tbcache - Table Cache
                    tmp     - Temporary Table
                    query   - Queries Statistics
                    select  - Select Statistics
                    sort    - Sort Statistics
                    innodb_bp - InnoDB Buffer Pool
      -d   disable      disable monitor name
           contain: var,innodb,none
      -h   Hostname
      -u   Username
      -p   Password
EOF
}

#######################################################
# Get Options
# 获取命令行参数
#######################################################
sub get_option(){
    my $rtn = getopts('i:c:n:d:h:u:p:');
    unless ( "$rtn" eq "1" ) { print_usage(); exit 1;}

    $interval=$opt_i?$opt_i:1;
    $count=$opt_c?$opt_c+1:0;
    $name=$opt_n?$opt_n:'basic';
    $disable=$opt_d?$opt_d:'none';
    $host=$opt_h?$opt_h:'';
    $user=$opt_u?$opt_u:'';
    $pwd=$opt_p?$opt_p:'';

    if($interval !~ /[0-9]/ || $count !~ /[0-9]/) { print_usage(); exit 1;}
    if(($ARGV[0] && $ARGV[0] !~ /[0-9]/) || ($ARGV[1] && $ARGV[1] !~ /[0-9]/)) { print_usage(); exit 1;}

    if($ARGV[0]){
        $interval=$ARGV[0];
    }
    if($ARGV[1]){
        $count=$ARGV[1]+1;
    }
    if($ARGV[2]){
        $name=$ARGV[2];
    }
    if($ARGV[3]){
        $disable=$ARGV[3];
    }
    if($ARGV[4]){
        $host=$ARGV[4];
    }
    if($ARGV[5]){
        $user=$ARGV[5];
    }
    if($ARGV[6]){
        $pwd=$ARGV[6];
    }

    $name = lc($name);
    $disable = lc($disable);
    $host = lc($host);
    $user = lc($user);
 
    # Split name
    my @tmp = split(/,/,$name);
    foreach my $row (@tmp) {
        $names->{"$row"}=1;
    }
    @tmp = split(/,/,$disable);
    foreach my $row (@tmp) {
        $disables->{"$row"}=1;
    }
}

#######################################################
# Set env from profile
# 从配置文件读取环境变量并在Shell中设置
#######################################################
sub set_env {
    my $profile="~/.profile";
    if (! -e $profile ){
        $profile="~/.bash_profile"
    }
    open(NEWENV, ". $profile && env|");
    while (<NEWENV>){
        if (/(\w+)=(.*)/){
            $ENV{$1}="$2";
        }
    }
    close NEWENV;
}

#######################################################
# Main Loop to get MySQL Status & Display them
# 获取MySQL状态和显示的主循环
#######################################################
sub do_loop{
    # Check OS Type
    # 检查操作系统类型
    if ($^O eq "MSWin32") {
        $os_win = 1;
    } else {
        $os_win = 0;
    }
    init();
    # if $count == 0 then loop time is unlimit
    if($count){
        for(my $c=0;$c<$count;$c++){
            refresh_all();
            sleep $interval;
        }
    }
    else{ 
        for(my $c=0;;$c++){
            refresh_all();
            sleep $interval;
        }
    }
}

#######################################################
# Catch Ctrl+C
# 捕捉 Ctrl+C 以关闭程序和数据连接
#######################################################
sub quit {
    printf "\nExit...\n";
    $dbconn->disconnect;
    exit 1;
}

#######################################################
# Return Same Char
# 返回若干个相同的字符
#######################################################
sub same_char {
    my ($ch)=$_[0];
    my ($cnt)=$_[1];
    my $out = '';
    for(my $c=0; $c<$cnt; $c++) {
        $out .= sprintf "$ch";
    }
    $out;
}

#######################################################
# Format Value
# 格式化数值为计算机单位
#######################################################
sub format_val {
    my ($val)=$_[0];
    my ($fmt)=$_[1];
    my $ret = $val/1024/1024/1024/1024 < 1
            ? $val/1024/1024/1024 < 1
                ? $val/1024/1024 < 1
                    ? sprintf("$fmt K", $val/1024)
                    : sprintf("$fmt M", $val/1024/1024)
                : sprintf("$fmt G", $val/1024/1024/1024)
            : sprintf("$fmt T", $val/1024/1024/1024/1024);
}

#######################################################
# Initialization Min&Max Values
# 初始化监控变量的最小和最大值
#######################################################
sub init_val {
    my($val) = @_;
    my $min = "Min_".$val;
    my $max = "Max_".$val;
    $status_res->{"$val"} = 0;
    $status_res->{"$min"} = 2147483646;
    $status_res->{"$max"} = 0;
}

#######################################################
# Initialization
# 初始化
#######################################################
sub init {
    # Init Value
    $now = 0;
    get_stat();
    $now = 1-$now;

    # Init Max Values
    init_val('Bytes_traffic');
    init_val('Bytes_received');
    init_val('Bytes_sent');

    init_val('Key_used_ratio');
    init_val('Key_free_ratio');
    init_val('Key_used');
    init_val('Key_free');
    init_val('Key_write_hit_ratio');
    init_val('Key_read_hit_ratio');
    init_val('Key_avg_hit_ratio');
   
    init_val('Qcache_frag_ratio');
    init_val('Qcache_used_ratio');
    init_val('Qcache_hit_ratio');
    init_val('Qcache_hits');
    init_val('Qcache_not_cached');
    init_val('Qcache_hits_inserts_ratio');
    init_val('Qcache_lowmem_prunes');
    init_val('Qcache_hits_inserts_ratio');

    init_val('Thread_cache_hit_ratio');
    init_val('Thread_cache_used_ratio');

    init_val('Table_cache_hit_ratio');
    init_val('Table_cache_used_ratio');
    init_val('Opened_tables');

    init_val('Questions');
    init_val('insert');
    init_val('update');
    init_val('delete'); 
    init_val('select');
    init_val('Select_scan');
    init_val('Select_range');
    init_val('Select_full_join');
    init_val('Select_range_check');
    init_val('Select_full_range_join');
    init_val('Com_select');
    init_val('Com_insert');
    init_val('Com_update');
    init_val('Com_delete');

    init_val('Sort_rows');
    init_val('Sort_times');
    init_val('Sort_load');
    init_val('Sort_scan');
    init_val('Sort_range');
    init_val('Sort_merge_passes');
    init_val('Sort_times');
    
    init_val('Created_tmp_disk_tables');
    init_val('Created_tmp_files');
    init_val('Created_tmp_tables');
    init_val('Created_tmp_tables_on_disk_ratio');

    init_val('Innodb_rows_read');
    init_val('Innodb_rows_inserted');
    init_val('Innodb_rows_updated');
    init_val('Innodb_rows_deleted');
    init_val('Innodb_data_reads');
    init_val('Innodb_data_writes');
    init_val('Innodb_buffer_pool_read_ahead_rnd');
    init_val('Innodb_buffer_pool_read_ahead_seq');
    init_val('Innodb_buffer_pool_read_requests');
    init_val('Innodb_buffer_pool_pages_flushed');
    init_val('Innodb_buffer_pool_write_requests');
    init_val('innodb_buffer_pool_size');
    init_val('Innodb_buffer_pool_pages_usage');
    init_val('Innodb_buffer_pool_pages_read_hit_ratio');
    init_val('Innodb_log_writes');
    init_val('Innodb_lsn_current');
}

#######################################################
# Get MySQL Traffic Status
# 获取MySQL流量状态
#######################################################
sub get_stat_traffic {
    # All Traffic Status
    # 总进出流量
    $status_res->{'Bytes_traffic'} = 
    $status[$now]->{'Bytes_traffic'} = 
        $status[$now]->{'Bytes_received'} + $status[$now]->{'Bytes_sent'};
}

#######################################################
# Get MySQL Key Buffer Status
# 获取MySQL键缓冲状态
#######################################################
sub get_stat_kbuffer {
    # Key Buffer Used Ratio
    # 键缓冲空间用过的最大使用率
    # 大约80%较好
    $status_res->{'Key_used_ratio'} = 
    $status[$now]->{'Key_used_ratio'} =
        $status[$now]->{'Key_blocks_used'}
        ? ($status[$now]->{'Key_blocks_used'}/($status[$now]->{'Key_blocks_unused'}
          +$status[$now]->{'Key_blocks_used'}))*100
        : 0;

    # Key Buffer Free Ratio
    # 键缓冲空间空闲率
    $status_res->{'Key_free_ratio'} = 
    $status[$now]->{'Key_free_ratio'} = 
        100 - $status[$now]->{'Key_used_ratio'};

    # Key Buffer Used Size
    # 键缓冲已用空间
    $status_res->{'Key_used'} = 
    $status[$now]->{'Key_used'} =
        $status[$now]->{'key_buffer_size'}
        ? $status[$now]->{'Key_used_ratio'}/100*$status[$now]->{'key_buffer_size'}
        : 0;

    # Key Buffer Free Size
    # 键缓冲空闲空间
    $status_res->{'Key_free'} = 
    $status[$now]->{'Key_free'} =
        $status[$now]->{'key_buffer_size'}
        ? $status[$now]->{'Key_free_ratio'}/100*$status[$now]->{'key_buffer_size'}
        : 0;

    # Key Buffer Write Hit Ratio
    # 键缓冲写命中率
    $status_res->{'Key_write_hit_ratio'} = 
    $status[$now]->{'Key_write_hit_ratio'} = 
        $status[$now]->{'Key_write_requests'}
        ? (1 -  $status[$now]->{'Key_writes'}/$status[$now]->{'Key_write_requests'})*100
        : 0;

    # Key Buffer Read Hit Ratio
    # 键缓冲读命中率
    $status_res->{'Key_read_hit_ratio'} =
    $status[$now]->{'Key_read_hit_ratio'} = 
        $status[$now]->{'Key_write_requests'}
        ? (1 -  $status[$now]->{'Key_reads'}/$status[$now]->{'Key_read_requests'})*100
        : 0;

    # Key Buffer RW Average Hit Ratio
    # 键缓冲读写平均命中率
    $status_res->{'Key_avg_hit_ratio'} = 
    $status[$now]->{'Key_avg_hit_ratio'} = 
        ($status[$now]->{'Key_write_hit_ratio'}+$status[$now]->{'Key_read_hit_ratio'})/2;
}

#######################################################
# Get MySQL Query Cache Status
# 获取MySQL查询缓存状态
#######################################################
sub get_stat_qcache {
    # Fragmention Ratio
    # 查询缓存空间碎片率
    # 理想值小于20%
    $status_res->{'Qcache_frag_ratio'} = 
    $status[$now]->{'Qcache_frag_ratio'} = 
        $status[$now]->{'Qcache_total_blocks'}
        ? $status[$now]->{'Qcache_free_blocks'}/$status[$now]->{'Qcache_total_blocks'}*100
        : 0;
         
    # QCache Used Ratio
    # 查询缓存空间利用率
    $status_res->{'Qcache_used_ratio'} = 
    $status[$now]->{'Qcache_used_ratio'} = 
        $status[$now]->{'query_cache_size'}
        ? ($status[$now]->{'query_cache_size'} 
          - $status[$now]->{'Qcache_free_memory'})/$status[$now]->{'query_cache_size'}*100
        : 0;
         
    # QCache Hit Ratio
    # 查询缓存命中率
    $status_res->{'Qcache_hit_ratio'} =
    $status[$now]->{'Qcache_hit_ratio'} = 
        ($status[$now]->{'Qcache_hits'}+$status[$now]->{'Com_select'})
        ? $status[$now]->{'Qcache_hits'}/($status[$now]->{'Qcache_hits'}+$status[$now]->{'Com_select'})*100
         #? $status[$now]->{'Qcache_hits'}/($status[$now]->{'Qcache_hits'}
         #+$status[$now]->{'Qcache_inserts'}
         #+$status[$now]->{'Qcache_not_cached'})*100
        : 0;  

    # Query Hit:Insert
    # 查询缓存命中:插入比
    $status_res->{'Qcache_hits_inserts_ratio'} =
    $status[$now]->{'Qcache_hits_inserts_ratio'} =
        $status[$now]->{'Qcache_inserts'}
        ? $status[$now]->{'Qcache_hits'}/$status[$now]->{'Qcache_inserts'}
        : 0;
}

#######################################################
# Get MySQL Thread Cache Status
# 获取MySQL线程缓存状态
#######################################################
sub get_stat_thcache {
    # Thread Cache Hit Ratio
    # 线程缓存命中率
    $status_res->{'Thread_cache_hit_ratio'} =
    $status[$now]->{'Thread_cache_hit_ratio'} =
        $status[$now]->{'Connections'}
        ? 100 - $status[$now]->{'Threads_created'}/$status[$now]->{'Connections'}*100
        : 0;

    # Thread Cache Used Ratio
    # 线程缓存使用率
    $status_res->{'Thread_cache_used_ratio'} =
    $status[$now]->{'Thread_cache_used_ratio'} =
        $status[$now]->{'thread_cache_size'}
        ? $status[$now]->{'Threads_cached'}/$status[$now]->{'thread_cache_size'}*100
        : 0;
}

#######################################################
# Get MySQL Table Cache Status
# 获取MySQL表缓存状态
#######################################################
sub get_stat_tbcache {
    # Table Cache Hit Ratio
    # 表缓存命中率
    # 理想值大于85%
    $status_res->{'Table_cache_hit_ratio'} =
    $status[$now]->{'Table_cache_hit_ratio'} =
        $status[$now]->{'Opened_tables'}
        ? $status[$now]->{'Open_tables'}/$status[$now]->{'Opened_tables'}*100
        : 0;

    # Table Cache Used Ratio
    # 表缓存使用率
    # 理想值小于95%
    $status_res->{'Table_cache_used_ratio'} =
    $status[$now]->{'Table_cache_used_ratio'} =
        $status[$now]->{'table_cache'}
        ? $status[$now]->{'Open_tables'}/$status[$now]->{'table_cache'}*100
        : 0;
}

#######################################################
# Get MySQL Tmp Table Status
# 获取MySQL临时表状态
#######################################################
sub get_stat_tmp {
    # (Created_tmp_disk_tables / Created_tmp_tables) Ratio
    # 创建磁盘临时表占临时表的比例
    # 理想值25%
    $status_res->{'Created_tmp_tables_on_disk_ratio'} =
    $status[$now]->{'Created_tmp_tables_on_disk_ratio'} =
        $status[$now]->{'Created_tmp_tables'} 
        ? $status[$now]->{'Created_tmp_disk_tables'}/$status[$now]->{'Created_tmp_tables'}*100
        : 0;
}

######################################################
# Get MySQL Query Status
# 获取MySQL查询语句状态
#######################################################
sub get_stat_query {
    # Insert Queries
    # 目前传入服务器并被执行的所有Insert语句
    $status_res->{'insert'} =
    $status[$now]->{'insert'} = 
    	$status[$now]->{'Com_insert'}
	+$status[$now]->{'Com_insert_select'};
    # Update Queries
    # 目前传入服务器并被执行的所有Update语句
    $status_res->{'update'} = 
    $status[$now]->{'update'} = 
    	$status[$now]->{'Com_update'}
	+$status[$now]->{'Com_update_multi'};
    # Delete Queries
    # 目前传入服务器并被执行的所有Update语句
    $status_res->{'delete'} = 
    $status[$now]->{'delete'} = 
    	$status[$now]->{'Com_delete'}
	+$status[$now]->{'Com_delete_multi'};
}

######################################################
# Get MySQL Select Status
# 获取MySQL选择查询状态
#######################################################
sub get_stat_select {
    # Select(Include Cached) Queries
    # 目前传入服务器并被执行的所有Select语句
    $status_res->{'select'} = 
    $status[$now]->{'select'} = 
    $status_res->{'All_select'} =
    $status[$now]->{'All_select'} = 
        ($status[$now]->{'Com_select'}
        +$status[$now]->{'Qcache_hits'});
}


######################################################
# Get MySQL Sort Status
# 获取MySQL排序状态
#######################################################
sub get_stat_sort {
    # All Sort Times
    # 所有排序操作总次数
    $status_res->{'Sort_times'} =
    $status[$now]->{'Sort_times'} = 
        $status[$now]->{'Sort_range'}
        + $status[$now]->{'Sort_scan'}
        + $status[$now]->{'Sort_merge_passes'};
}

######################################################
# Get MySQL InnoDB Buffer Pool Status
# 获取MySQL InnoDB缓冲池状态
#######################################################
sub get_stat_innodb_bp {
    # Buffer Pool Usage
    # 缓冲池利用率
    # no warnings qw(uninitialized);
    # $status_res->{'Innodb_buffer_pool_pages_usage'} =
    #     $status[$now]->{'Innodb_buffer_pool_pages_total'} 
    #     ? (1 - $status[$now]->{'Innodb_buffer_pool_pages_free'}/$status[$now]->{'Innodb_buffer_pool_pages_total'})*100
    #     : 0;

    # Buffer Pool Hit Ratio
    # 缓冲池命中率
    # $status_res->{'Innodb_buffer_pool_pages_read_hit_ratio'} =
    #     ($status[$now]->{'Innodb_buffer_pool_read_requests'} - $status[1 - $now]->{'Innodb_buffer_pool_read_requests'})
    #     ? 100 - ($status[$now]->{'Innodb_data_reads'} - $status[1 - $now]->{'Innodb_data_reads'}) /
    #       ($status[$now]->{'Innodb_buffer_pool_read_requests'} - $status[1 - $now]->{'Innodb_buffer_pool_read_requests'})*100
    #     : 0;
}

#######################################################
# Get MySQL Variables & Status
# 获取MySQL变量和状态
#######################################################
sub get_stat {
    # Get MySQL Version 
    my $sql = "SELECT version();";
    my $ver = $dbconn->selectrow_arrayref($sql);
    $status_res->{'version'} = $ver->[0];

    # Get MySQL Variables
    $sql = "SHOW GLOBAL VARIABLES;";
    my $vars = $dbconn->selectall_arrayref($sql);
    foreach my $row(@$vars) {
        $status_res->{"$row->[0]"} = $row->[1];
        $status[$now]->{"$row->[0]"} = $row->[1];
    }

    # Get MySQL Status
    $sql="SHOW GLOBAL STATUS;";
    my $stat=$dbconn->selectall_arrayref($sql);
    foreach my $row(@$stat) {
        $status[$now]->{"$row->[0]"} = $row->[1];
        $status_res->{"$row->[0]"} = $row->[1];
    }
    
    # Fix The MySQL 5.1.3 Change table_cache to table_open_cache
    $status_res->{'table_cache'} = 
        defined($status_res->{'table_open_cache'})
        ? $status_res->{'table_open_cache'}
        : $status_res->{'table_cache'};
        
    # Fix The New Param Queries
    # Using Queries instead of Questions
    # Because Queries Contain all Query but Questions not
    if (defined($status_res->{'Queries'})) {
        $status_res->{'Questions'} = $status_res->{'Com_select'} + $status_res->{'Com_insert'} + $status_res->{'Com_delete'} + $status_res->{'Com_update'};
        $status[$now]->{'Questions'} = $status_res->{'Com_select'} + $status_res->{'Com_insert'} + $status_res->{'Com_delete'} + $status_res->{'Com_update'};
    }
    
    get_stat_traffic();
    get_stat_kbuffer();
    get_stat_qcache();
    get_stat_thcache();
    get_stat_tbcache();
    get_stat_tmp();
    get_stat_query();
    get_stat_select();
    get_stat_sort();
    if($status_res->{'have_innodb'} eq "YES") { 
        get_stat_innodb_bp();
    }
}

#######################################################
# Display Header
# 显示程序头
#######################################################
sub display_header {
    if ($os_win == 0) {
        printf color("red");
    }
    # First Line
    printf "+";
    printf same_char('-',28);
    printf "mystat Ver ".$version;
    printf same_char('-',27);print "+\n";
    # Second Line
    print "+";
    print same_char('-',27);
    print "Powered by PengLiXun.COM";
    print same_char('-',26);
    print "+\n";
    if ($os_win == 0) {
        print color("reset");
    }
}

#######################################################
# Display Version & Hostname & Uptime
# 显示变量部分标题
#######################################################
sub display_var_title {
    # Display Version & Hostname
    my $ver = $status_res->{'version'};
    printf "|--MySQL $ver";
    printf "%25s", "@ ".$status_res->{'hostname'}." (".$status_res->{'version_compile_machine'}.")";
    
    # Display Uptime
    my($sec,$min,$hour,$day) = gmtime($status_res->{'Uptime'});
    $day = $day-1;
    printf "   Uptime:%3sd%3sh%3sm%3ss", $day, $hour, $min, $sec;
    printf "---%2ss--|\n",$interval;
}

#######################################################
# Display Cache Variables
# 显示缓存变量
#######################################################
sub display_var_cache {
    my $query = $status_res->{'query_cache_size'};
    my $thd = $status_res->{'thread_cache_size'};
    my $tbl = $status_res->{'table_cache'};
                        
    printf "\t|";
    printf "Query Cache:";
    printf format_val($query, "%4s");
    printf " | ";
    printf "Thread Cache:%6s", $thd;
    printf " | ";
    printf "Table Cache:%6s|\n", $tbl;
}

#######################################################
# Display Buffer Variables
# 显示缓冲变量
#######################################################
sub display_var_buffer {
    my $key = $status_res->{'key_buffer_size'};
    my $join = $status_res->{'join_buffer_size'};
    my $sort = $status_res->{'sort_buffer_size'};
    
    printf "\t|";
    printf "Key Buffer:";
    printf format_val($key, "%5s");
    printf " | ";
    printf "Sort Buffer:";
    printf format_val($sort, "%5s");
    printf " | ";
    printf "Join Buffer:";
    printf format_val($join, "%4s");
    printf "|\n";
}

#######################################################
# Display Log Status
# 显示日志状态
#######################################################
sub display_var_log {
    no warnings qw(uninitialized);
    my $g_log = $status_res->{'log'};
    my $b_log = $status_res->{'log_bin'};
    my $s_log = $status_res->{'log_slow_queries'};
    
    printf "\t|General Log: %5s", $g_log;
    printf " | Bin Log: %10s", $b_log;
    printf " | Slow Log: %8s|\n", $s_log;
}

#######################################################
# Display Connections Status
# 显示连接状态
#######################################################
sub display_var_conn {
    my $max_conn = $status_res->{'max_connections'};
    my $max_used = $status_res->{'Max_used_connections'};
    my $act_conn = $status_res->{'Threads_connected'};
    my $used_ratio = $max_used/$max_conn*100;#大约85%较好
    my $now_ratio = $act_conn/$max_conn*100;
    
    printf "\t|";
    printf "Act User:%4s(%2.0f%%)", $act_conn, $now_ratio;
    printf " | ";
    printf "Max Used:%5s(%2.0f%%)", $max_used, $used_ratio;
    printf " | ";
    printf "Max Connect:%6s|\n", $max_conn;
}

#######################################################
# Display Query Status
# 显示查询语句状态
#######################################################
sub display_var_query {
    my $select = $status_res->{"Com_select"};
    my $insert = $status_res->{"Com_insert"};
    my $update = $status_res->{"Com_update"};
    my $delete = $status_res->{"Com_delete"};
    my $sql = $select+$insert+$update+$delete;
    my $select_ratio = $select/$sql*100;
    my $insert_ratio = $insert/$sql*100;
    my $update_ratio = $update/$sql*100;
    my $delete_ratio = $delete/$sql*100;
    
    printf "\t|";
    printf "SELECT:%5.2f%%", $select_ratio;
    printf " | ";
    printf "INSERT:%5.2f%%", $insert_ratio;
    printf " | ";
    printf "UPDATE:%5.2f%%", $update_ratio;
    printf " | ";
    printf "DELETE:%5.2f%%|\n", $delete_ratio;
}

#######################################################
# Display Variables
# 控制变量部分显示
#######################################################
sub display_vars {
#print color("blue");
    display_var_title();
    if ($os_win == 0) {
        print color("reset");
    }

    if(!defined($disables->{"var"})) { 
        if ($os_win == 0) {
	    print color("green");
        }
        display_var_cache();
        display_var_buffer();
        display_var_log();
        display_var_conn();
        display_var_query();
	if ($os_win == 0) {
            print color("reset");
        }
   }
}

#######################################################
# Display Traffic Status
# 显示流量相关状态
#######################################################
sub display_stat_traffic {
    my $now_received = $status_res->{'Now_Bytes_received'};
    my $now_sent = $status_res->{'Now_Bytes_sent'};
    my $now_traffic = $status_res->{'Now_Bytes_traffic'};

    my $max_received = $status_res->{'Max_Bytes_received'};
    my $max_sent = $status_res->{'Max_Bytes_sent'};
    my $max_traffic = $status_res->{'Max_Bytes_traffic'};

    my $avg_received = $status_res->{'Avg_Bytes_received'};
    my $avg_sent = $status_res->{'Avg_Bytes_sent'};
    my $avg_traffic = $status_res->{'Avg_Bytes_traffic'};

    my $all_received = $status_res->{'Bytes_received'};
    my $all_sent = $status_res->{'Bytes_sent'};
    my $all_traffic = $status_res->{'Bytes_traffic'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Network Traffic";
    printf same_char('-',60);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }
    
    printf same_char(' ',2);
    printf "Now Traf:";
    printf format_val($now_traffic, "%9.2f")."B/s";
    printf " | ";
    printf "Now Recv:";
    printf format_val($now_received, "%9.2f")."B/s";
    printf " | ";
    printf "Now Sent:";
    printf format_val($now_sent, "%9.2f")."B/s";
    printf "\n";
   
    if(defined($names->{'all'}) || 
       defined($names->{'traffic'})) { 
        printf same_char(' ',2);
        printf "Avg Traf:";
        printf format_val($avg_traffic, "%9.2f")."B/s";
        printf " | ";
        printf "Avg Recv:";
        printf format_val($avg_received, "%9.2f")."B/s";
        printf " | ";
        printf "Avg Sent:";
        printf format_val($avg_sent, "%9.2f")."B/s";
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Traf:";
    printf format_val($max_traffic, "%9.2f")."B/s";
    printf " | ";
    printf "Max Recv:";
    printf format_val($max_received, "%9.2f")."B/s";
    printf " | ";
    printf "Max Sent:";
    printf format_val($max_sent, "%9.2f")."B/s";
    printf "\n";

    if(defined($names->{'all'}) || 
       defined($names->{'traffic'})) { 
        printf same_char(' ',2);
        printf "All Traf:";
        printf format_val($all_traffic, "%11.4f")."B";
        printf " | ";
        printf "All Recv:";
        printf format_val($all_received, "%11.4f")."B";
        printf " | ";
        printf "All Sent:";
        printf format_val($all_sent, "%11.4f")."B";
        printf "\n";
    }
}

#######################################################
# Display Key Buffer Status
# 显示键缓存状态
#######################################################
sub display_stat_kbuffer {
    my $key_buffer = $status_res->{'key_buffer_size'};
    my $key_blocks_used = $status_res->{'Key_blocks_used'};
    my $key_blocks_unused = $status_res->{'Key_blocks_unused'};
    my $key_used_ratio =$status_res->{'Key_used_ratio'};
    my $key_free_ratio = $status_res->{'Key_free_ratio'};
    my $key_used = $status_res->{'Key_used'};
    my $key_free = $status_res->{'Key_free'};
 
    my $key_read_requests = $status_res->{'Key_read_requests'};
    my $key_reads = $status_res->{'Key_reads'};
    my $key_read_hit_ratio =$status_res->{'Key_read_hit_ratio'}; 

    my $key_write_requests = $status_res->{'Key_write_requests'};
    my $key_writes = $status_res->{'Key_writes'};
    my $key_write_hit_ratio = $status_res->{'Key_write_hit_ratio'};

    my $key_avg_hit_ratio = $status_res->{'Key_avg_hit_ratio'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Key Buffer";
    printf same_char('-',65);print "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Buffer Used:";
    printf format_val($key_used, "%10.2f");
    printf "B (%6.2f%%)", $key_used_ratio;
    printf "  |  ";
    printf "Buffer Free:";
    printf format_val($key_free, "%10.2f");
    printf "B (%6.2f%%)", $key_free_ratio;
    printf "\n";

    printf same_char(' ',2);
    printf "Avg Hit:%13.2f %%", $key_avg_hit_ratio;
    printf " | ";
    printf "Read Hit:%12.2f %%", $key_read_hit_ratio;
    printf " | ";
    printf "Write Hit:%11.2f %%\n", $key_write_hit_ratio;
}

#######################################################
# Display Query Cache Status
# 显示查询缓存状态
#######################################################
sub display_stat_qcache {
    my $qcache_queries_in_cache = $status_res->{'Qcache_queries_in_cache'};

    my $qcache_frag_ratio = $status_res->{'Qcache_frag_ratio'};
    my $qcache_used_ratio = $status_res->{'Qcache_used_ratio'};
    my $qcache_hit_ratio = $status_res->{'Qcache_hit_ratio'};

    my $now_qcache_lowmem_prunes = $status_res->{'Now_Qcache_lowmem_prunes'};
    my $avg_qcache_lowmem_prunes = $status_res->{'Avg_Qcache_lowmem_prunes'};
    my $max_qcache_lowmem_prunes = $status_res->{'Max_Qcache_lowmem_prunes'};
    
    my $now_qcache_not_cached = $status_res->{'Now_Qcache_not_cached'};
    my $now_qcache_not_cached_ratio = $status_res->{'Now_Qcache_not_cached_ratio'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Query Cache";
    printf same_char('-',64);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }
    
    printf same_char(' ',2);
    printf "Qcache Used: %8.2f %%", $qcache_used_ratio;
    printf " | ";
    printf "Qcache Hit: %9.2f %%", $qcache_hit_ratio;
    printf " | ";
    printf "Fragmentation: %6.2f %%", $qcache_frag_ratio;
    printf "\n";
    
    printf same_char(' ',2);
    printf "Query in Cache:%8s", $qcache_queries_in_cache;
    printf " | ";
    printf "Now Not Cached:%5s /s", $now_qcache_not_cached;
    printf " | ";
    printf "Not Cached Ratio:%4.0f %%", $now_qcache_not_cached_ratio;
    printf "\n";
    
    printf same_char(' ',2);
    printf "Now Prunes:%9.0f /s", $now_qcache_lowmem_prunes; 
    printf " | ";
    printf "Avg Prunes:%9.0f /s", $avg_qcache_lowmem_prunes; 
    printf " | ";
    printf "Max Prunes:%9.0f /s", $max_qcache_lowmem_prunes; 
    printf "\n";
}

#######################################################
# Display Thread Cache Status
# 显示线程缓存状态
#######################################################
sub display_stat_thcache {
    my $thread_cache_used_ratio = $status_res->{'Thread_cache_used_ratio'};
    my $thread_cache_hit_ratio = $status_res->{'Thread_cache_hit_ratio'};
    
    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Thread Cache";
    printf same_char('-',63);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Cache Used:%10.0f %%", $thread_cache_used_ratio;
    printf " | ";
    printf "Hit Ratio:%11.0f %%", $thread_cache_hit_ratio;
    printf "\n";
}

#######################################################
# Display Table Cache Status
# 显示表缓存状态
#######################################################
sub display_stat_tbcache {
    my $table_cache_used_ratio = $status_res->{'Table_cache_used_ratio'};
    my $table_cache_hit_ratio = $status_res->{'Table_cache_hit_ratio'};
    
    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Table Cache";
    printf same_char('-',64);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Cache Used:%10.0f %%", $table_cache_used_ratio;
    printf " | ";
    printf "Hit Ratio:%11.0f %%", $table_cache_hit_ratio;
    printf "\n";
}

#######################################################
# Display Queries Status
# 显示查询语句状态
#######################################################
sub display_stat_query {
    my $now_questions = $status_res->{'Now_Questions'};
    my $avg_questions = $status_res->{'Avg_Questions'};
    my $max_questions = $status_res->{'Max_Questions'};

    my $now_insert = $status_res->{'Now_insert'};
    my $avg_insert = $status_res->{'Avg_insert'};
    my $max_insert = $status_res->{'Max_insert'};

    my $now_update = $status_res->{'Now_update'};
    my $avg_update = $status_res->{'Avg_update'};
    my $max_update = $status_res->{'Max_update'};

    my $now_delete = $status_res->{'Now_delete'};
    my $avg_delete = $status_res->{'Avg_delete'};
    my $max_delete = $status_res->{'Max_delete'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Queries";
    printf same_char('-',68);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Now Queries:%8.0f /s", $now_questions;
    printf " | ";
    printf "Avg Queries:%8.0f /s", $avg_questions;
    printf " | ";
    printf "Max Queries:%8.0f /s", $max_questions;
    printf "\n";

    printf same_char(' ',2);
    printf "Now Insert:%9.0f /s", $now_insert;
    printf " | ";
    printf "Now Update:%9.0f /s", $now_update;
    printf " | ";
    printf "Now Delete:%9.0f /s", $now_delete;
    printf "\n";
   
    if(defined($names->{'all'}) ||
       defined($names->{'query'})) { 
        printf same_char(' ',2);
        printf "Avg Insert:%9.0f /s", $avg_insert;
        printf " | ";
        printf "Avg Update:%9.0f /s", $avg_update;
        printf " | ";
        printf "Avg Delete:%9.0f /s", $avg_delete;
        printf "\n";
    }
    
    printf same_char(' ',2);
    printf "Max Insert:%9.0f /s", $max_insert;
    printf " | ";
    printf "Max Update:%9.0f /s", $max_update;
    printf " | ";
    printf "Max Delete:%9.0f /s", $max_delete;
    printf "\n";
}

#######################################################
# Display Select Status
# 显示选择查询状态
#######################################################
sub display_stat_select {
    my $now_select_scan = $status_res->{'Now_Select_scan'};
    my $now_select_range = $status_res->{'Now_Select_range'};
    my $now_select_full_join = $status_res->{'Now_Select_full_join'};
    my $now_select_range_check = $status_res->{'Now_Select_range_check'};
    my $now_select_full_range_join = $status_res->{'Now_Select_full_range_join'};
    
    my $avg_select_scan = $status_res->{'Avg_Select_scan'};
    my $avg_select_range = $status_res->{'Avg_Select_range'};
    my $avg_select_full_join = $status_res->{'Avg_Select_full_join'};
    my $avg_select_range_check = $status_res->{'Avg_Select_range_check'};
    my $avg_select_full_range_join = $status_res->{'Avg_Select_full_range_join'};

    my $max_select_scan = $status_res->{'Max_Select_scan'};
    my $max_select_range = $status_res->{'Max_Select_range'};
    my $max_select_full_join = $status_res->{'Max_Select_full_join'};
    my $max_select_range_check = $status_res->{'Max_Select_range_check'};
    my $max_select_full_range_join = $status_res->{'Max_Select_full_range_join'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Select";
    printf same_char('-',69);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Now Scan:%11.0f /s", $now_select_scan;
    printf " | ";
    printf "Now Range:%10.0f /s", $now_select_range;
    printf " | ";
    printf "Now Range Check:%4.0f /s", $now_select_range_check;
    printf "\n";

    if(defined($names->{'all'}) ||
       defined($names->{'select'})) {
        printf same_char(' ',2);
        printf "Avg Scan:%11.0f /s", $avg_select_scan;
        printf " | ";
        printf "Avg Range:%10.0f /s", $avg_select_range;
        printf " | ";
        printf "Avg Range Check:%4.0f /s", $avg_select_range_check;
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Scan:%11.0f /s", $max_select_scan;
    printf " | ";
    printf "Max Range:%10.0f /s", $max_select_range;
    printf " | ";
    printf "Max Range Check:%4.0f /s", $max_select_range_check;
    printf "\n";

    printf same_char(' ',2);
    printf "Now Full Join:%6.0f /s", $now_select_full_join;
    printf " | ";
    printf "Now Full Range Join:%5.0f /s", $now_select_full_range_join;
    printf "\n";
   
    if(defined($names->{'all'}) ||
       defined($names->{'select'})) { 
        printf same_char(' ',2);
        printf "Avg Full Join:%6.0f /s", $avg_select_full_join;
        printf " | ";
        printf "Avg Full Range Join:%5.0f /s", $avg_select_full_range_join;
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Full Join:%6.0f /s", $max_select_full_join;
    printf " | ";
    printf "Max Full Range Join:%5.0f /s", $max_select_full_range_join;
    printf "\n";
}

#######################################################
# Display Sort Status
# 显示排序状态
#######################################################
sub display_stat_sort {
    my $now_sort_rows = $status_res->{'Now_Sort_rows'};
    my $now_sort_times = $status_res->{'Now_Sort_times'};
    my $now_sort_load = $status_res->{'Now_Sort_load'};
    
    my $now_sort_range = $status_res->{'Now_Sort_range'};
    my $now_sort_scan = $status_res->{'Now_Sort_scan'};
    my $now_sort_merge_passes = $status_res->{'Now_Sort_merge_passes'};

    my $avg_sort_rows = $status_res->{'Avg_Sort_rows'};
    my $avg_sort_times = $status_res->{'Avg_Sort_times'};
    my $avg_sort_load = $status_res->{'Avg_Sort_load'};
    
    my $avg_sort_range = $status_res->{'Avg_Sort_range'};
    my $avg_sort_scan = $status_res->{'Avg_Sort_scan'};
    my $avg_sort_merge_passes = $status_res->{'Avg_Sort_merge_passes'};
 
    my $max_sort_rows = $status_res->{'Max_Sort_rows'};
    my $max_sort_times = $status_res->{'Max_Sort_times'};
    my $max_sort_load = $status_res->{'Max_Sort_load'};
    
    my $max_sort_scan = $status_res->{'Max_Sort_scan'};
    my $max_sort_range = $status_res->{'Max_Sort_range'};
    my $max_sort_merge_passes = $status_res->{'Max_Sort_merge_passes'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Sort";
    printf same_char('-',71);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Now Rows:%7.0f Rows/s", $now_sort_rows;
    printf " | ";
    printf "Now Times:%5.0f Times/s", $now_sort_times;
    printf " | ";
    printf "Now Load:%4.0f Rows/Time", $now_sort_load;
    printf "\n";

    if(defined($names->{'all'}) ||
       defined($names->{'sort'})) {
        printf same_char(' ',2);
        printf "Avg Rows:%7.0f Rows/s", $avg_sort_rows;
        printf " | ";
        printf "Avg Times:%5.0f Times/s", $avg_sort_times;
        printf " | ";
        printf "Avg Load:%4.0f Rows/Time", $avg_sort_load;
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Rows:%7.0f Rows/s", $max_sort_rows;
    printf " | ";
    printf "Max Times:%5.0f Times/s", $max_sort_times;
    printf " | ";
    printf "Max Load:%4.0f Rows/Time", $max_sort_load;
    printf "\n";

    printf same_char(' ',2);
    printf "Now Scan:%6.0f Times/s", $now_sort_scan;
    printf " | ";
    printf "Now Range:%5.0f Times/s", $now_sort_range;
    printf " | ";
    printf "Now Merge:%5.0f Times/s", $now_sort_merge_passes;
    printf "\n";
    
    if(defined($names->{'all'}) ||
       defined($names->{'sort'})) {
        printf same_char(' ',2);
        printf "Avg Scan:%6.0f Times/s", $avg_sort_scan;
        printf " | ";
        printf "Avg Range:%5.0f Times/s", $avg_sort_range;
        printf " | ";
        printf "Avg Merge:%5.0f Times/s", $avg_sort_merge_passes;
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Scan:%6.0f Times/s", $max_sort_scan;
    printf " | ";
    printf "Max Range:%5.0f Times/s", $max_sort_range;
    printf " | ";
    printf "Max Merge:%5.0f Times/s", $max_sort_merge_passes;
    printf "\n";
}

#######################################################
# Display Temporary Tables Status
# 显示临时表状态
#######################################################
sub display_stat_tmp {
    my $now_created_tmp_disk_tables = $status_res->{'Now_Created_tmp_disk_tables'};
    my $now_created_tmp_files = $status_res->{'Now_Created_tmp_files'};
    my $now_created_tmp_tables = $status_res->{'Now_Created_tmp_tables'};
    
    my $avg_created_tmp_disk_tables = $status_res->{'Avg_Created_tmp_disk_tables'};
    my $avg_created_tmp_files = $status_res->{'Avg_Created_tmp_files'};
    my $avg_created_tmp_tables = $status_res->{'Avg_Created_tmp_tables'};
    
    my $max_created_tmp_disk_tables = $status_res->{'Max_Created_tmp_disk_tables'};
    my $max_created_tmp_files = $status_res->{'Max_Created_tmp_files'};
    my $max_created_tmp_tables = $status_res->{'Max_Created_tmp_tables'};
    
    my $created_tmp_tables_on_disk_ratio = $status_res->{'Created_tmp_tables_on_disk_ratio'};

    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "Tmp Tables";
    printf same_char('-',65);
    printf "+\n";
    if ($os_win == 0) { 
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Now Tmp Tables:%5.0f /s", $now_created_tmp_tables;
    printf " | ";
    printf "Now Disk Tables:%4.0f /s", $now_created_tmp_disk_tables;
    printf " | ";
    printf "Now Tmp Files:%6.0f /s", $now_created_tmp_files;
    printf "\n";
    
    if(defined($names->{'all'}) ||
       defined($names->{'tmp'})) {
        printf same_char(' ',2);
        printf "Avg Tmp Tables:%5.0f /s", $avg_created_tmp_tables;
        printf " | ";
        printf "Avg Disk Tables:%4.0f /s", $avg_created_tmp_disk_tables;
        printf " | ";
        printf "Avg Tmp Files:%6.0f /s", $avg_created_tmp_files;
        printf "\n";
    }

    printf same_char(' ',2);
    printf "Max Tmp Tables:%5.0f /s", $max_created_tmp_tables;
    printf " | ";
    printf "Max Disk Tables:%4.0f /s", $max_created_tmp_disk_tables;
    printf " | ";
    printf "Max Tmp Files:%6.0f /s", $max_created_tmp_files;
    printf "\n";

    printf same_char(' ',2);
    printf "Create Tmp Tables On Disk Ratio:%4.0f %%", $created_tmp_tables_on_disk_ratio;
    printf "\n";
}

#######################################################
# Display InnoDB Buffer Pool Status
# 显示InnoDB缓冲池状态
#######################################################
sub display_stat_innodb_bp {
    my $innodb_buffer_pool_pages_usage = $status_res->{'Innodb_buffer_pool_pages_usage'};
    my $innodb_bp_pages_size = $status_res->{'innodb_buffer_pool_size'} * $innodb_buffer_pool_pages_usage / 100;
    my $innodb_buffer_pool_pages_read_hit_ratio = $status_res->{'Innodb_buffer_pool_pages_read_hit_ratio'};
    my $min_innodb_buffer_pool_pages_usage = $status_res->{'Min_Innodb_buffer_pool_pages_usage'};
    my $min_innodb_bp_pages_size = $status_res->{'innodb_buffer_pool_size'} * $min_innodb_buffer_pool_pages_usage / 100;
    my $min_innodb_buffer_pool_pages_read_hit_ratio = $status_res->{'Min_Innodb_buffer_pool_pages_read_hit_ratio'};
    my $max_innodb_buffer_pool_pages_usage = $status_res->{'Max_Innodb_buffer_pool_pages_usage'};
    my $max_innodb_bp_pages_size = $status_res->{'innodb_buffer_pool_size'} * $max_innodb_buffer_pool_pages_usage / 100;
    my $max_innodb_buffer_pool_pages_read_hit_ratio = $status_res->{'Max_Innodb_buffer_pool_pages_read_hit_ratio'};

    my $now_innodb_data_reads = $status_res->{'Now_Innodb_data_reads'};
    #my $now_innodb_buffer_pool_read_ahead_rnd = $status_res->{'Now_Innodb_buffer_pool_read_ahead_rnd'};
    #my $now_innodb_buffer_pool_read_ahead_seq = $status_res->{'Now_Innodb_buffer_pool_read_ahead_seq'};
    my $now_innodb_buffer_pool_read_requests = $status_res->{'Now_Innodb_buffer_pool_read_requests'};
    #my $now_innodb_buffer_pool_pages_flushed = $status_res->{'Now_Innodb_buffer_pool_pages_flushed'};
    my $now_innodb_buffer_pool_write_requests = $status_res->{'Now_Innodb_buffer_pool_write_requests'};

    my $avg_innodb_data_reads = $status_res->{'Avg_Innodb_data_reads'};
    #my $avg_innodb_buffer_pool_read_ahead_rnd = $status_res->{'Avg_Innodb_buffer_pool_read_ahead_rnd'};
    #my $avg_innodb_buffer_pool_read_ahead_seq = $status_res->{'Avg_Innodb_buffer_pool_read_ahead_seq'};
    my $avg_innodb_buffer_pool_read_requests = $status_res->{'Avg_Innodb_buffer_pool_read_requests'};
    #my $avg_innodb_buffer_pool_pages_flushed = $status_res->{'Avg_Innodb_buffer_pool_pages_flushed'};
    my $avg_innodb_buffer_pool_write_requests = $status_res->{'Avg_Innodb_buffer_pool_write_requests'};

    my $max_innodb_data_reads = $status_res->{'Max_Innodb_data_reads'};
    #my $max_innodb_buffer_pool_read_ahead_rnd = $status_res->{'Max_Innodb_buffer_pool_read_ahead_rnd'};
    #my $max_innodb_buffer_pool_read_ahead_seq = $status_res->{'Max_Innodb_buffer_pool_read_ahead_seq'};
    my $max_innodb_buffer_pool_read_requests = $status_res->{'Max_Innodb_buffer_pool_read_requests'};
    #my $max_innodb_buffer_pool_pages_flushed = $status_res->{'Max_Innodb_buffer_pool_pages_flushed'};
    my $max_innodb_buffer_pool_write_requests = $status_res->{'Max_Innodb_buffer_pool_write_requests'};

    my $now_innodb_rows_read = $status_res->{'Now_Innodb_rows_read'};
    my $avg_innodb_rows_read = $status_res->{'Avg_Innodb_rows_read'};
    my $max_innodb_rows_read = $status_res->{'Max_Innodb_rows_read'};

    my $now_innodb_rows_inserted = $status_res->{'Now_Innodb_rows_inserted'};
    my $avg_innodb_rows_inserted = $status_res->{'Avg_Innodb_rows_inserted'};
    my $max_innodb_rows_inserted = $status_res->{'Max_Innodb_rows_inserted'};

    my $now_innodb_rows_updated = $status_res->{'Now_Innodb_rows_updated'};
    my $avg_innodb_rows_updated = $status_res->{'Avg_Innodb_rows_updated'};
    my $max_innodb_rows_updated = $status_res->{'Max_Innodb_rows_updated'};

    my $now_innodb_rows_deleted = $status_res->{'Now_Innodb_rows_deleted'};
    my $avg_innodb_rows_deleted = $status_res->{'Avg_Innodb_rows_deleted'};
    my $max_innodb_rows_deleted = $status_res->{'Max_Innodb_rows_deleted'};

    # added for data disk writes, redo log writes, redo log size
    my $now_innodb_data_writes = $status_res->{'Now_Innodb_data_writes'};
    my $avg_innodb_data_writes = $status_res->{'Avg_Innodb_data_writes'};
    my $max_innodb_data_writes = $status_res->{'Max_Innodb_data_writes'};

    my $now_innodb_log_writes = $status_res->{'Now_Innodb_log_writes'};
    my $avg_innodb_log_writes = $status_res->{'Avg_Innodb_log_writes'};
    my $max_innodb_log_writes = $status_res->{'Max_Innodb_log_writes'};

    my $now_innodb_lsn_current = $status_res->{'Now_Innodb_lsn_current'};
    my $avg_innodb_lsn_current = $status_res->{'Avg_Innodb_lsn_current'};
    my $max_innodb_lsn_current = $status_res->{'Max_Innodb_lsn_current'};

    
    if ($os_win == 0) {
        printf color("blue");
    }
    printf "+";
    printf same_char('-',2);
    printf "InnoDB Buffer Pool";
    printf same_char('-',57);
    printf "+\n";
    if ($os_win == 0) {
        printf color("reset");
    }

    printf same_char(' ',2);
    printf "Now BP Pages Usage: ";
    printf format_val($innodb_bp_pages_size, "%4.0f");
    printf "B (%5.1f%%)", $innodb_buffer_pool_pages_usage;
    printf " | ";
    printf "Now Read Hit Ratio:%6.0f %%", $innodb_buffer_pool_pages_read_hit_ratio;
    printf "\n";

    printf same_char(' ',2);
    printf "Min BP Pages Usage: ";
    printf format_val($min_innodb_bp_pages_size, "%4.0f");
    printf "B (%5.1f%%)", $min_innodb_buffer_pool_pages_usage;
    printf " | ";
    printf "Min Read Hit Ratio:%6.0f %%", $min_innodb_buffer_pool_pages_read_hit_ratio;
    printf "\n";

    printf same_char(' ',2);
    printf "Max BP Pages Usage: ";
    printf format_val($max_innodb_bp_pages_size, "%4.0f");
    printf "B (%5.1f%%)", $max_innodb_buffer_pool_pages_usage;
    printf " | ";
    printf "Max Read Hit Ratio:%6.0f %%", $max_innodb_buffer_pool_pages_read_hit_ratio;
    printf "\n";

    printf same_char(' ',2);
    printf "Now Read Req:%7.0f /s", $now_innodb_buffer_pool_read_requests;
    printf " | ";
    printf "Now Write Req:%6.0f /s", $now_innodb_buffer_pool_write_requests;
    printf " | ";
    printf "Now Log Write:%6.0f /s", $now_innodb_log_writes;
    printf "\n";

    printf same_char(' ',2);
    printf "Avg Read Req:%7.0f /s", $avg_innodb_buffer_pool_read_requests;
    printf " | ";
    printf "Avg Write Req:%6.0f /s", $avg_innodb_buffer_pool_write_requests;
    printf " | ";
    printf "Avg Log Write:%6.0f /s", $avg_innodb_log_writes;
    printf "\n";

    printf same_char(' ',2);
    printf "Max Read Req:%7.0f /s", $max_innodb_buffer_pool_read_requests;
    printf " | ";
    printf "Max Write Req:%6.0f /s", $max_innodb_buffer_pool_write_requests;
    printf " | ";
    printf "Max Log Write:%6.0f /s", $max_innodb_log_writes;
    printf "\n";

    printf same_char(' ',2);
    printf "Now Disk Read:%6.0f /s", $now_innodb_data_reads;
    printf " | ";
    printf "Now Disk Write:%5.0f /s", $now_innodb_data_writes;
    printf " | ";
    printf "Now Log Size:";
    print format_val($now_innodb_lsn_current, "%5.0f")."B/s";
    printf "\n";

    printf same_char(' ',2);
    printf "Avg Disk Read:%6.0f /s", $avg_innodb_data_reads;
    printf " | ";
    printf "Avg Disk Write:%5.0f /s", $avg_innodb_data_writes;
    printf " | ";
    printf "Avg Log Size:";
    print format_val($avg_innodb_lsn_current, "%5.0f")."B/s";
    printf "\n";

    printf same_char(' ',2);
    printf "Max Disk Read:%6.0f /s", $max_innodb_data_reads;
    printf " | ";
    printf "Max Disk Write:%5.0f /s", $max_innodb_data_writes;
    printf " | ";
    printf "Max Log Size:";
    print format_val($max_innodb_lsn_current, "%5.0f")."B/s";
    printf "\n";

    printf same_char(' ',2);
    printf "Now Read:%11.0f /s", $now_innodb_rows_read;
    printf " | ";
    printf "Now Inserted:%7.0f /s", $now_innodb_rows_inserted;
    printf " | ";
    printf "Now Updated:%8.0f /s", $now_innodb_rows_updated;
    printf " | ";
    printf "Now Deleted:%8.0f /s", $now_innodb_rows_deleted;
    printf "\n";

    printf same_char(' ',2);
    printf "Avg Read:%11.0f /s", $avg_innodb_rows_read;
    printf " | ";
    printf "Avg Inserted:%7.0f /s", $avg_innodb_rows_inserted;
    printf " | ";
    printf "Avg Updated:%8.0f /s", $avg_innodb_rows_updated;
    printf " | ";
    printf "Avg Deleted:%8.0f /s", $avg_innodb_rows_deleted;
    printf "\n";

    printf same_char(' ',2);
    printf "Max Read:%11.0f /s", $max_innodb_rows_read;
    printf " | ";
    printf "Max Inserted:%7.0f /s", $max_innodb_rows_inserted;
    printf " | ";
    printf "Max Updated:%8.0f /s", $max_innodb_rows_updated;
    printf " | ";
    printf "Max Deleted:%8.0f /s", $max_innodb_rows_deleted;
    printf "\n";
}


#######################################################
# Display Status
# Notes: You can choose you wants to display it.
# 显示状态控制
# 提示: 您可以在这里选择您要显示的部分
#######################################################
sub display_stat {
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'traffic'})) {
        display_stat_traffic();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'kbuffer'})) {
        display_stat_kbuffer();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'qcache'})) {
        display_stat_qcache();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'thcache'})) {
        display_stat_thcache();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'tbcache'})) {
        display_stat_tbcache();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'query'})) {
        display_stat_query();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'select'})) {
        display_stat_select();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'sort'})) {
        display_stat_sort();
    }
    if(defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'tmp'})) {
        display_stat_tmp();
    }
    # Display InnoDB Status Must Have InnoDB
    no warnings qw(uninitialized);
    if((defined($names->{'all'}) ||
       defined($names->{'basic'}) ||
       defined($names->{'myisam'}) ||
       defined($names->{'innodb'}) ||
       defined($names->{'innodb_bp'})) &&
       !defined($disables->{'innodb'}) &&
       $status_res->{'have_innodb'} eq "YES") {
        display_stat_innodb_bp();
    }
}

#######################################################
# Calc Value Templabe
# 状态数值计算模板
#######################################################
sub calc_val {
    my ($type)=$_[0];
    my ($val)=$_[1];
    my $now_str = 'Now_'.($val);
    my $avg_str = 'Avg_'.($val);
    my $min_str = 'Min_'.($val);
    my $max_str = 'Max_'.($val);
    
    switch($type) {
        # 计算实时、平均、最大、最小值，适合流量等计算
        case 0 {
            no warnings qw(uninitialized);
            # Calc Now Values
            $status_res->{"$now_str"} = 
                ($status[$now]->{"$val"} - $status[1-$now]->{"$val"})/$interval;
            # Calc Avegate Values
            $status_res->{"$avg_str"} =
                $status_res->{"$val"}/$status_res->{'Uptime'};
            # Calc Min Values
            if ($status_res->{"$min_str"} > $status_res->{"$now_str"}) {
                $status_res->{"$min_str"} = $status_res->{"$now_str"};
            }
            # Calc Max Values
            if ($status_res->{"$max_str"} < $status_res->{"$now_str"}) {
                $status_res->{"$max_str"} = $status_res->{"$now_str"};
            }
        }
        # 计算最小值和最大值，适合百分比的计算
        case 1 {
            # Calc Min Values
            if ($status_res->{"$min_str"} > $status_res->{"$val"}) {
                $status_res->{"$min_str"} = $status_res->{"$val"};
            }
            # Calc Max Values
            if ($status_res->{"$max_str"} < $status_res->{"$val"}) {
                $status_res->{"$max_str"} = $status_res->{"$val"};
            }
        }
        # 计算最小值
        case 2 {
            # Calc Min Values
            if ($status_res->{"$min_str"} > $status_res->{"$val"}) {
                $status_res->{"$min_str"} = $status_res->{"$val"};
            }
        }
        # 计算最大值
        case 3 {
            # Calc Max Values
            if ($status_res->{"$max_str"} < $status_res->{"$val"}) {
                $status_res->{"$max_str"} = $status_res->{"$val"};
            }
        }
    }
}

#######################################################
# Calc Traffic
# 计算流量相关数据
#######################################################
sub calc_stat_traffic {
    # Calc All Traffic
    # 计算当前数据库总流速
    calc_val(0, 'Bytes_traffic');

    # Calc Recevied Traffic
    # 计算当前数据库接收速率
    calc_val(0, 'Bytes_received');

    # Calc Sent Traffic
    # 计算当前数据库发送速率
    calc_val(0, 'Bytes_sent');
}

#######################################################
# Calc Key Buffer
# 计算键缓存相关数据
#######################################################
sub calc_stat_kbuffer {
    # Calc Key Buffer Used Ratio
    # Key Buffer 空间使用率
    calc_val(1, 'Key_used_ratio');

    # Calc Key Buffer Free Ratio
    # Key Buffer 空间空闲率
    calc_val(1, 'Key_free_ratio');

    # Calc Key Buffer Used Size
    # Key Buffer 已用空间
    calc_val(1, 'Key_used');

    # Calc Key Buffer Free Size
    # Key Buffer 空闲空间
    calc_val(1, 'Key_free');

    # Calc Key Buffer Write Hit Ratio
    # Key Buffer 写命中率
    calc_val(1, 'Key_write_hit_ratio');

    # Calc Key Buffer Read Hit Ratio
    # Key Buffer 读命中率
    calc_val(1, 'Key_read_hit_ratio');

    # Calc Key Buffer Average Hit Ratio
    # Key Buffer 平均命中率
    calc_val(1, 'Key_avg_hit_ratio');
}

#######################################################
# Calc Query Cache
# 计算查询缓存相关数据
#######################################################
sub calc_stat_qcache {
    # Calc Fragmention Ratio
    # Query Cache 空间碎片率
    calc_val(1, 'Qcache_frag_ratio');
         
    # Calc QCache Used Ratio
    # Query Cache 空间利用率
    calc_val(1, 'Qcache_used_ratio');
         
    # Calc QCache Hit Ratio
    # Query Cache 命中率
    calc_val(1, 'Qcache_hit_ratio');
    
    # Calc QCache Hit Queries
    # Query Cache 命中Query数
    calc_val(0, 'Qcache_hits');

    # Calc QCache Not Cached Queries
    # Query Cache 未命中的Query数
    calc_val(0, 'Qcache_not_cached');
        
    # Calc QCache Not Cached Ratio
    # Query Cache 当前未命中的比率
    $status_res->{'Now_Qcache_not_cached_ratio'} = 
        $status_res->{'Now_Qcache_hits'}+$status_res->{'Now_Qcache_not_cached'}
        ? $status_res->{'Now_Qcache_not_cached'}/($status_res->{'Now_Qcache_hits'}
          +$status_res->{'Now_Qcache_not_cached'})*100
        : 0;
    
    # Calc Query Low Mem Prunes
    calc_val(0, 'Qcache_lowmem_prunes');

    # Calc Hit:Insert
    calc_val(1, 'Qcache_hits_inserts_ratio');
}

#######################################################
# Calc Thread Cache
# 计算线程查询相关数据
#######################################################
sub calc_stat_thcache {
    # Calc Thread Cache Hit Ratio
    # 线程缓存命中率
    calc_val(1, 'Thread_cache_hit_ratio');

    # Calc Thread Cache Used Ratio
    # 线程缓存使用率
    calc_val(1, 'Thread_cache_used_ratio');
}

#######################################################
# Calc Table Cache
# 计算表缓存相关数据
#######################################################
sub calc_stat_tbcache {
    # Calc Table Cache Hit Ratio
    # 表缓存命中率
    calc_val(1, 'Table_cache_hit_ratio');

    # Calc Table Cache Used Ratio
    # 表缓存使用率
    calc_val(1, 'Table_cache_used_ratio');

    # Calc Table Create Speed
    # 表创建速度
    calc_val(0, 'Opened_tables');
}

######################################################
# Calc Queries
# 计算查询语句相关数据
#######################################################
sub calc_stat_query {
    # Calc Queries
    # Queries流量
    calc_val(0, 'Questions');

    # Calc Insert
    # Insert语句流量
    calc_val(0, 'insert');
    #calc_val(1, 'Com_insert');
    #calc_val(1, 'Com_insert_select');

    # Calc Update
    # Update语句流量
    calc_val(0, 'update');
    #calc_val(1, 'Com_update');
    #calc_val(1, 'Com_update_multi');

    # Calc Delete
    # Delete语句流量
    calc_val(0, 'delete');
    #calc_val(1, 'Com_delete');
    #calc_val(1, 'Com_delete_multi');
}

######################################################
# Calc Select
# 计算选择查询相关数据
#######################################################
sub calc_stat_select {
    # Calc Select(Include Cached) Queries
    # 所有传入服务器的Select语句数量
    calc_val(0, 'select');

    # Calc Select(Not Cached) Queries
    # 被执行的Select语句数量
    calc_val(0, 'Com_select');

    # 被执行的全表扫描查询语句的数量
    calc_val(0, 'Select_scan');

    # 被执行的范围查询语句的数量
    calc_val(0, 'Select_range');

    # 被执行的全表连接查询语句的数量
    # SELECT * FROM tbl1, tbl2 WHERE tbl1.col1 = tbl2.col1;
    calc_val(0, 'Select_full_join');

    # 被执行的范围检查连接查询语句的数量
    # SELECT * FROM tbl1, tbl2 WHERE tbl1.col1 > tbl2.col1;
    calc_val(0, 'Select_range_check');

    # 被执行的全表范围连接查询语句的数量
    # SELECT * FROM tbl1, tbl2 WHERE tbl1.col1 = 10 AND tbl2.col1 > 13;
    calc_val(0, 'Select_full_range_join');
}

######################################################
# Calc Sort
# 计算排序相关数据
#######################################################
sub calc_stat_sort {
    # Calc Sort Times
    # 排序操作的次数
    calc_val(0, 'Sort_times');
    calc_val(0, 'Sort_range');
    calc_val(0, 'Sort_scan');
    calc_val(0, 'Sort_merge_passes');

    # Calc Sort Rows
    # 排序操作的行数
    calc_val(0, 'Sort_rows');

    # Calc Now Sort Speed
    # 当前平均每次排序行数
    $status_res->{'Now_Sort_load'} =
          $status_res->{'Now_Sort_times'}
        ? $status_res->{'Now_Sort_rows'}/$status_res->{'Now_Sort_times'}
        : 0;

    # Calc Avg Sort Speed
    # 目前平均每次排序行数
    $status_res->{'Avg_Sort_load'} =
        $status_res->{'Sort_times'}
        ? $status_res->{'Sort_rows'}/$status_res->{'Sort_times'}
        : 0;

    # Calc Max Sort Speed    
    # 目前最大每次排序行数
    if ($status_res->{'Max_Sort_load'} < $status_res->{'Now_Sort_load'}) {
        $status_res->{'Max_Sort_load'} = $status_res->{'Now_Sort_load'};
    }
}

######################################################
# Calc Temporary Tables
# 计算临时表相关数据
#######################################################
sub calc_stat_tmp {
    # Calc Memory Temporary Tables
    # 创建内存临时表的数量
    calc_val(0, 'Created_tmp_tables');

    # Calc Disk Temporary Tables
    # 创建磁盘临时表的数量
    calc_val(0, 'Created_tmp_disk_tables');

    # Calc Disk Temporary Files
    # 创建磁盘临时文件的数量
    calc_val(0, 'Created_tmp_files');

    # Calc (Created_tmp_disk_tables / Created_tmp_tables) Ratio
    # 创建磁盘临时表占临时表的比例
    calc_val(1, 'Created_tmp_tables_on_disk_ratio');
}

######################################################
# Calc InnoDB Buffer Pool
# 计算InnoDB缓冲池相关数据
#######################################################
sub calc_stat_innodb_bp {
    # Buffer Pool Usage
    # 缓冲池利用率
    $status_res->{'Innodb_buffer_pool_pages_usage'} =
        $status[$now]->{'Innodb_buffer_pool_pages_total'} 
        ? (1 - $status[$now]->{'Innodb_buffer_pool_pages_free'}/$status[$now]->{'Innodb_buffer_pool_pages_total'})*100
        : 0;

    # Buffer Pool Hit Ratio
    # 缓冲池命中率
    $status_res->{'Innodb_buffer_pool_pages_read_hit_ratio'} =
        ($status[$now]->{'Innodb_buffer_pool_read_requests'} - $status[1 - $now]->{'Innodb_buffer_pool_read_requests'})
        ? 100 - ($status[$now]->{'Innodb_data_reads'} - $status[1 - $now]->{'Innodb_data_reads'}) /
          ($status[$now]->{'Innodb_buffer_pool_read_requests'} - $status[1 - $now]->{'Innodb_buffer_pool_read_requests'})*100
        : 0;
    # Calc Buffer Pool Usage
    # 计算缓冲池利用率
    calc_val(1, 'Innodb_buffer_pool_pages_usage');

    # Calc Read Hit
    # 计算缓冲池读命中
    calc_val(1, 'Innodb_buffer_pool_pages_read_hit_ratio');

    # Calc Read From Disk
    # 计算从磁盘中读取次数
    calc_val(0, 'Innodb_data_reads');

    # Calc Read Rnd
    # 计算从内存中随机读取次数
    calc_val(0, 'Innodb_buffer_pool_read_ahead_rnd');

    # Calc Read Seq
    # 计算从内存中顺序读取次数
    calc_val(0, 'Innodb_buffer_pool_read_ahead_seq');

    # Calc Read From Memory
    # 计算读取请求次数
    calc_val(0, 'Innodb_buffer_pool_read_requests');

    # Calc Flushed Times
    # 计算刷新次数
    calc_val(0, 'Innodb_buffer_pool_pages_flushed');

    # Calc Wirte Requests
    # 计算写请求数量
    calc_val(0, 'Innodb_buffer_pool_write_requests');

    # Calc Write to Disk
    # 计算写磁盘次数
    calc_val(0, 'Innodb_data_writes');

    # Calc InnoDB Redo Log Writes to Disk
    # 计算log写磁盘次数
    calc_val(0, 'Innodb_log_writes');

    # Calc InnoDB Redo size to Disk
    # 计算写磁盘次数
    calc_val(0, 'Innodb_lsn_current');

    # Calc Inserted Queries 
    # 计算已经完成的Insert语句数量
    calc_val(0, 'Innodb_rows_read');

    # Calc Inserted Queries 
    # 计算已经完成的Insert语句数量
    calc_val(0, 'Innodb_rows_inserted');

    # Calc Updated Queries
    # 计算已经完成的Update语句数量
    calc_val(0, 'Innodb_rows_updated');

    # Calc Deleted Queries
    # 计算已经完成的Delete语句数量
    calc_val(0, 'Innodb_rows_deleted');
}

#######################################################
# Calc Result Status
# 数据计算控制
#######################################################
sub calc_stat {
    calc_stat_traffic();
    calc_stat_kbuffer();
    calc_stat_qcache();
    calc_stat_thcache();
    calc_stat_tbcache();
    calc_stat_query();
    calc_stat_select();
    calc_stat_sort();
    calc_stat_tmp();
    if($status_res->{'have_innodb'} eq "YES") { 
        calc_stat_innodb_bp();
    }
}

#######################################################
# Refresh All Must Do
# 刷新全部
#######################################################
sub refresh_all {
    get_stat();
    calc_stat();
    if ($os_win) {
        system "cls";
    } else {
	system "clear";
    }
    display_header();
    display_vars();
    display_stat();
    $now = 1 - $now;
}

