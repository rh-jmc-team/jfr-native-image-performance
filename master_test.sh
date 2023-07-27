#!/usr/bin/bash
export JAVA_HOME=/home/rtoyonag/JDKs/labsjdk-ce-20-jvmci-23.0-b10
export PATH=/home/rtoyonag/repos/mx:$PATH
export GRAALVM_HOME=/home/rtoyonag/IdeaProjects/graal/vm/latest_graalvm_home

THIS_REPO=/home/rtoyonag/IdeaProjects/jfr-native-image-performance
HYPERFOIL_HOME=/home/rtoyonag/tools/hyperfoil-0.24.1
GRAALVM_SOURCE_HOME=/home/rtoyonag/IdeaProjects/graal

TEST=("With JFR" "Without JFR enabled" "Without JFR in build")
RUNS=("./target/getting-started-1.0.0-SNAPSHOT-runner_jfr -XX:+FlightRecorder -XX:StartFlightRecording=settings=$THIS_REPO/quarkus-demo.jfc,filename=performance_test.jfr" './target/getting-started-1.0.0-SNAPSHOT-runner_jfr' './target/getting-started-1.0.0-SNAPSHOT-runner_no_jfr')
RESULTS=("" "" "")
FILESIZE=(0 0)
RSS=(0 0 0)
STARTUP=(0 0 0)
COUNT=0
IMAGE_NAME_ORIGINAL=target/getting-started-1.0.0-SNAPSHOT-runner
IMAGE_NAME_JFR="${IMAGE_NAME_ORIGINAL}_jfr"
IMAGE_NAME_NO_JFR="${IMAGE_NAME_ORIGINAL}_no_jfr"

set_up_hyperfoil(){
    echo "Setting Up Hyperfoil"

    # Upload benchmark
    printf "start-local\nupload %s/jfr_plaintext.hf.yaml\nexit\n" "$THIS_REPO" | $HYPERFOIL_HOME/bin/cli.sh

    # Start controller
    $HYPERFOIL_HOME/bin/standalone.sh > waste.txt &

    # Wait for hyperfoil controller app to start up
    echo "-- Waiting for hyperfoil to start"
    while ! (curl -sf http://0.0.0.0:8090/benchmark/jfr-hyperfoil > /dev/null)
    do
        # Busy wait rather than wait some arbitrary amount of time and risk waiting too long
        :
    done
    echo "-- Done waiting for hyperfoil start-up"
}

run_hyperfoil_benchmark(){

    # start the benchmark
    NAME=`curl "http://0.0.0.0:8090/benchmark/jfr-hyperfoil/start" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])"`

    # sleep until test is done
    sleep 7

    # Get and parse results
    readarray -d',' results < <(curl "http://localhost:8090/run/${NAME}/stats/all/json" | python3 $THIS_REPO/json_parser.py)

    echo "MEAN ${results[0]} MAX ${results[1]} 50 ${results[2]} 90 ${results[3]} 99 ${results[4]} errors ${results[5]}"
}

shutdown_hyperfoil() {
    # kill Hyperfoil standalone controller
    fuser -k 8090/tcp
}

wait_for_quarkus() {
    # Wait for quarkus app to start up
    while ! (curl -sf http://0.0.0.0:8080/hello/greeting/test_input > /dev/null)
    do
        # Busy wait rather than wait some arbitrary amount of time and risk waiting too long
        :
    done
}

shutdown_quarkus() {
    # kill quarkus app
    fuser -k 8080/tcp
}

run_test() {
    # Clear caches (Greatly affects startup time)
    sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    start=$(date +%s%N)

    # run the quarkus app
    ${RUNS[$COUNT]} > waste.txt & CURRENT_PID=$!

    wait_for_quarkus
    end=$(date +%s%N)
    STARTUP[$COUNT]=$(("$end" - "$start"))

    # Get rss
    RSS[$COUNT]=$(ps -o rss= -p $CURRENT_PID | sed 's/^ *//g')

    # Run benchmark
    RESULTS[$COUNT]="$(run_hyperfoil_benchmark)"
    shutdown_quarkus
}

build_images() {
    cd GRAALVM_SOURCE_HOME/substratevm
    git checkout master
    #mx build

    cd $THIS_REPO

    #must use sigprof based handler always! Otherwise too many meaningless recurrign callback samples
    ./mvnw package -Dnative -DskipTests -Dquarkus.native.monitoring=jfr  -Dquarkus.native.additional-build-args=-H:+SignalHandlerBasedExecutionSampler

    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_JFR

    # Build without JFR in image
    ./mvnw package -Dnative -DskipTests

    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_NO_JFR
}

get_image_sizes() {
    # Get the size of the binary
    FILESIZE[0]=$(stat -c%s "$IMAGE_NAME_JFR")
    FILESIZE[1]=$(stat -c%s "$IMAGE_NAME_NO_JFR")
}

echo "Starting Performance Test"
cd $THIS_REPO

build_images
get_image_sizes

# Disable turbo boost and start testing (need to run  sudo ./test.sh)
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

set_up_hyperfoil

# Do test
for i in "${RUNS[@]}"
do
    run_test
    COUNT=$COUNT+1
done


shutdown_hyperfoil

# enable turbo boost again
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo


echo "*****************************" >> performance_test_results.txt
echo $(date) >> performance_test_results.txt
echo "Size with JFR in build = ${FILESIZE[0]} bytes." >> performance_test_results.txt
echo "Size without JFR in build = ${FILESIZE[1]} bytes." >> performance_test_results.txt

for ((i=0; i<3; i++));
do
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> performance_test_results.txt
    echo "Run ${TEST[$i]}" >> performance_test_results.txt
    echo "RSS is ${RSS[$i]}" >> performance_test_results.txt
    echo "StartUp $((${STARTUP[$i]}/1000000)) ms.">> performance_test_results.txt
    echo "Stats ${RESULTS[$i]}" >> performance_test_results.txt
done
