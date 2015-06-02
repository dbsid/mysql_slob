HOME_PATH=`pwd`
LOG_PATH="${HOME_PATH}/log/$(date +"%Y.%m.%d-%H_%M_%S")_P_$(echo "$@" | sed 's/ /_/g')"
EXEC_NAME=$HOME_PATH/runit.sh

for i in "$@"
do
    $EXEC_NAME $i | tee slob.out
    mkdir -p $LOG_PATH/$i
    mv vmstat.out mpstat.out iostat.out slob_debug.out tm.out slob.out mystat.out $LOG_PATH/$i
done
