#!/bin/bash
# Set the paths and variables below before running!
# ----------------------------------------------------------------------
GRAALVM_SOURCE_HOME=/home/rtoyonag/IdeaProjects/graal # These sources will be built
MX_HOME=/home/rtoyonag/repos/mx
DEV_BRANCH="object-count-backport"
CLEAN_COMMIT="602b8236aa85344bf329dc75bd61f59741148d12"
# ----------------------------------------------------------------------
RESULTS=("" "" "" "" "" "")
FILESIZE=(0 0)
RSS=()
RSS_STARTUP_POOL_SIZE=5
STARTUP=()
COUNT=0
IMAGE_NAME_ORIGINAL=target/getting-started-1.0.0-SNAPSHOT-runner
IMAGE_NAME_JFR="${IMAGE_NAME_ORIGINAL}_jfr"
IMAGE_NAME_NO_JFR="${IMAGE_NAME_ORIGINAL}_no_jfr"
IMAGE_NAME_DEV="${IMAGE_NAME_ORIGINAL}_dev"
IMAGE_NAME_CLEAN="${IMAGE_NAME_ORIGINAL}_clean"
BUILD_GRAAL=true
BUILD_QUARKUS=true
TEST_DEV=false
TEST_JAVA=false
RUN_COUNT=0
TEST_NAMES=("Without JFR in build" "Without JFR enabled" "With JFR")
ENDPOINT=("regular" "work")
ENDPOINT_COUNT=0
CWD=$(pwd)
RUN_COMMANDS=("./$IMAGE_NAME_NO_JFR" "./$IMAGE_NAME_JFR" "./$IMAGE_NAME_JFR -XX:+FlightRecorder -XX:StartFlightRecording=settings=$CWD/quarkus-demo.jfc,duration=4s,filename=performance_test.jfr")

set_up_hyperfoil(){
    echo "Setting Up Hyperfoil"

    # Start controller
    $HYPERFOIL_HOME/bin/standalone.sh > output_dump.txt &

    # Wait for hyperfoil controller app to start up
    echo "-- Waiting for hyperfoil to start"
    while ! (curl -sf http://0.0.0.0:8090/openapi > /dev/null)
    do
        # Busy wait rather than wait some arbitrary amount of time and risk waiting too long
        :
    done
    echo "-- Done waiting for hyperfoil start-up"

    # Upload benchmark
    curl -X POST --data-binary @"benchmark.hf.yaml" -H "Content-type: text/vnd.yaml" http://0.0.0.0:8090/benchmark
}

run_hyperfoil_benchmark(){

    # start the benchmark
    NAME=$(curl "http://0.0.0.0:8090/benchmark/jfr-hyperfoil/start?templateParam=ENDPOINT=${ENDPOINT[$ENDPOINT_COUNT]}" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")

    # sleep until test is done
    sleep 7 #37

    # Get and parse results
    readarray -d' ' results < <(curl "http://localhost:8090/run/${NAME}/stats/all/json" | python3 $CWD/json_parser.py)

    echo "MEAN $((results[0]/1000)) us, MAX $((results[1]/1000)) us, 50 $((results[2]/1000)) us, 90 $((results[3]/1000)) us, 99 $((results[4]/1000)) us, errors ${results[5]}"
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
    for ((i=0; i<RSS_STARTUP_POOL_SIZE; i++));
    do
          shutdown_quarkus
          # Clear caches (Greatly affects startup time)
          sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'

          start=$(date +%s%N)

          # run the quarkus app
          ${RUN_COMMANDS[$((COUNT%RUN_COUNT))]} > output_dump.txt & CURRENT_PID=$!

          wait_for_quarkus
          end=$(date +%s%N)
          STARTUP+=($(("$end" - "$start")))

          # Get rss
          RSS+=($(ps -o rss= -p $CURRENT_PID | sed 's/^ *//g'))
    done

    # Run benchmark
    RESULTS[$COUNT]="$(run_hyperfoil_benchmark)"
    shutdown_quarkus
}

build_images() {
  if $TEST_DEV
  then
    # Build images necessary to test development branch changes

    # build Graal with development changes
    cd $GRAALVM_SOURCE_HOME/substratevm
    git checkout "$DEV_BRANCH"
    $MX_HOME/mx clean
    $MX_HOME/mx build

    # build quarkus app using Graal with dev changes
    cd $CWD
    ./mvnw clean package -Dnative -DskipTests -Dquarkus.native.monitoring=jfr  -Dquarkus.native.additional-build-args=-H:+SignalHandlerBasedExecutionSampler
    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_DEV

    # Build Graal without dev changes
    cd $GRAALVM_SOURCE_HOME/substratevm
    git checkout "$CLEAN_COMMIT"
    $MX_HOME/mx clean
    $MX_HOME/mx build

    # Build quarkus app using Graal without dev changes
    cd $CWD
    ./mvnw package -Dnative -DskipTests -Dquarkus.native.monitoring=jfr  -Dquarkus.native.additional-build-args=-H:+SignalHandlerBasedExecutionSampler
    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_CLEAN
  elif $TEST_JAVA
  then
    # Testing java so only need to compile.
    cd $CWD
    ./mvnw package
  else
    # Testing master branch, build iamges  with and without JFR.

    if $BUILD_GRAAL
      then
          # Rebuild GraalVM from master branch
          cd $GRAALVM_SOURCE_HOME/substratevm
          git checkout master
          $MX_HOME/mx clean
          $MX_HOME/mx build
    fi

    cd $CWD

    # Only clean on initial build. Must use sigprof based handler always! Otherwise too many meaningless recurring callback samples
    ./mvnw clean package -Dnative -DskipTests -Dquarkus.native.monitoring=jfr  -Dquarkus.native.additional-build-args=-H:+SignalHandlerBasedExecutionSampler

    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_JFR

    # Build without JFR in image
    ./mvnw package -Dnative -DskipTests

    mv $IMAGE_NAME_ORIGINAL $IMAGE_NAME_NO_JFR
  fi
}

get_image_sizes() {
    # Get the size of the binary
    if $TEST_DEV
    then
      FILESIZE[0]=$(stat -c%s "$IMAGE_NAME_DEV")
      FILESIZE[1]=$(stat -c%s "$IMAGE_NAME_CLEAN")
    else
      FILESIZE[0]=$(stat -c%s "$IMAGE_NAME_JFR")
      FILESIZE[1]=$(stat -c%s "$IMAGE_NAME_NO_JFR")
    fi
}


while getopts "gqdj" flag
do
    case "${flag}" in
        g) BUILD_GRAAL=false
          echo "Running Quarkus rebuild then hyperfoil";;
        q) BUILD_QUARKUS=false
          echo "Running hyperfoil only";;
        d) TEST_DEV=true
          TEST_NAMES=("With dev changes" "Without dev changes")
          RUN_COMMANDS=("./$IMAGE_NAME_DEV -XX:+FlightRecorder -XX:StartFlightRecording=settings=$CWD/quarkus-demo.jfc,duration=4s,filename=performance_test_dev.jfr" "./$IMAGE_NAME_CLEAN -XX:+FlightRecorder -XX:StartFlightRecording=settings=$CWD/quarkus-demo.jfc,duration=4s,filename=performance_test_clean.jfr")
          echo "testing dev branch only";;
        j) TEST_JAVA=true
          TEST_NAMES=("Java mode without JFR" "Java mode with JFR")
          RUN_COMMANDS=("$JAVA_HOME/bin/java -jar ./target/quarkus-app/quarkus-run.jar" "$JAVA_HOME/bin/java -XX:+FlightRecorder -XX:StartFlightRecording=settings=$CWD/quarkus-demo.jfc,filename=performance_test_JVM.jfr -jar ./target/quarkus-app/quarkus-run.jar")
          echo "testing Java mode";;
        *)
    esac
done

echo "Starting Performance Test"

if [[ -z $JAVA_HOME ]]; then
    printenv
    echo "Please set JAVA_HOME prior to starting test."
    exit 1
fi

if [[ ! -d $JAVA_HOME ]]; then
    echo "JAVA_HOME not found."
    exit 1
fi

if [[ -z $GRAALVM_HOME ]]; then
    echo "Please set GRAALVM_HOME prior to starting test."
    echo "This is where GraalVM will be built, or wherever your pre-built installation of GraalVM/Mandrel is."
    exit 1
fi

if [[ ! -d $GRAALVM_HOME ]]; then
    echo "GRAALVM_HOME not found."
    exit 1
fi

if [[ -z $HYPERFOIL_HOME ]]; then
    echo "Please set HYPERFOIL_HOME prior to starting test."
    exit 1
fi

if [[ ! -d $HYPERFOIL_HOME ]]; then
    echo "HYPERFOIL_HOME not found."
    exit 1
fi

RUN_COUNT=${#RUN_COMMANDS[@]}

if $BUILD_QUARKUS
then
  build_images
fi

get_image_sizes

# Disable turbo boost and start testing (need to run  sudo ./test.sh)
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

# Do test with "regular" endpoint. Only bother with "regular" endpoint benchmark if not testing dev changes.
if ! $TEST_DEV
then
  set_up_hyperfoil
  # Do test
  for i in "${RUN_COMMANDS[@]}"
  do
      run_test
      COUNT=$COUNT+1
  done
  shutdown_hyperfoil
fi

ENDPOINT_COUNT=$ENDPOINT_COUNT+1
set_up_hyperfoil

# Do test with "work" endpoint
for i in "${RUN_COMMANDS[@]}"
do
    run_test
    COUNT=$COUNT+1
done


shutdown_hyperfoil

# enable turbo boost again
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

# Write results
{
  echo "*****************************"
  echo "$(date)"
  echo "Size with JFR in build = ${FILESIZE[0]} bytes."
  echo "Size without JFR in build = ${FILESIZE[1]} bytes."
} >> performance_test_results.txt

for ((i=0; i<RUN_COUNT; i++));
do
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> performance_test_results.txt
    echo "Run ${TEST_NAMES[$i]}" >> performance_test_results.txt

    # Compute average RSS
    sum=0
    start="$((RSS_STARTUP_POOL_SIZE*i))"
    for rss in "${RSS[@]:start:RSS_STARTUP_POOL_SIZE}"
    do
      ((sum+=rss))
    done
    ((avg_rss=sum/RSS_STARTUP_POOL_SIZE))

    # Compute average start up time
    sum=0
    for start_up in "${STARTUP[@]:start:RSS_STARTUP_POOL_SIZE}"
    do
      ((sum+=start_up))
    done
    ((avg_startup=sum/RSS_STARTUP_POOL_SIZE))

    if ! $TEST_DEV
    then
          {
            echo "Average (of $RSS_STARTUP_POOL_SIZE) RSS is $avg_rss kB."
            echo "Average (of $RSS_STARTUP_POOL_SIZE) StartUp $((avg_startup/1000000)) ms."
            echo "Normal Stats ${RESULTS[$i]}. Worst case Stats ${RESULTS[$((i+RUN_COUNT))]}"
          } >> performance_test_results.txt

    else
          {
            echo "Average (of $RSS_STARTUP_POOL_SIZE) RSS is $avg_rss. kB"
            echo "Average (of $RSS_STARTUP_POOL_SIZE) StartUp $((avg_startup/1000000)) ms."
            echo "Stats ${RESULTS[$i]}."
          } >> performance_test_results.txt
    fi

done
