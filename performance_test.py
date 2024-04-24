import sys
import json
import os
import subprocess
import time
from datetime import datetime


configurations = {
    "Without JFR in build": {},
    # "Without JFR enabled":{},
    "With JFR": {},
    "Java mode without JFR": {},
    "Java mode with JFR": {}
}
measurements = {
    "mean",
    "max",
    "p50",
    "p90",
    "p99",
    "rss",
    "startup"
}

BUILD_IMAGES = True
MODE = ""
ITERATIONS = 10
BENCHMARK = ""
IMAGE_NAME_ORIGINAL = "target/getting-started-1.0.0-SNAPSHOT-runner"
IMAGE_NAME_JFR = IMAGE_NAME_ORIGINAL+"_jfr"
IMAGE_NAME_NO_JFR = IMAGE_NAME_ORIGINAL+"_no_jfr"
JAVA_HOME = ""
GRAALVM_HOME = ""
HYPERFOIL_HOME = ""
CWD = os.getcwd()
RUN_COMMANDS = []


def check_endpoint(endpoint):
    # Execute the command and check the result
    try:
        subprocess.run("curl -sf " + endpoint + " > /dev/null", shell=True, check=True)
        return True  # Return True if the command succeeds
    except subprocess.CalledProcessError:
        return False  # Return False if the command fails


def set_up_hyperfoil():
    # Start controller
    subprocess.run(HYPERFOIL_HOME + "/bin/standalone.sh > output_dump" + datetime.now().isoformat() + ".txt &", shell=True, check=True)

    # Wait for hyperfoil controller app to start up
    # Busy wait rather than wait some arbitrary amount of time and risk waiting too long
    print("-- Waiting for hyperfoil to start")
    while True:
        if check_endpoint("http://0.0.0.0:8090/openapi"):
            break

    print("-- Done waiting for hyperfoil start-up")

    # Upload benchmark
    subprocess.run("curl -X POST --data-binary @\"benchmark.hf.yaml\" -H \"Content-type: text/vnd.yaml\" http://0.0.0.0:8090/benchmark", shell=True, check=True)


def shutdown_hyperfoil():
    try:
        subprocess.run("sudo fuser -k 8090/tcp", shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")
        print("-- Failed to shutdown hyperfoil")


def shutdown_quarkus():
    try:
        subprocess.run("sudo fuser -k 8080/tcp", shell=True, check=True)
    except:
        print("-- Failed to shutdown quarkus")


def wait_for_quarkus():
    print("waiting for quarkus")
    while True:
        if check_endpoint("http://0.0.0.0:8080/hello/greeting/test_input"):
            print("quarkus is accessible")
            return


def enableTurboBoost(enable):
    bit = 1
    if enable:
        bit = 0
    try:
        subprocess.run("echo " + str(bit) + " | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo", shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")


def run_hyperfoil_benchmark(config):
    # start the benchmark
    name = ""
    try:
        # TODO remove embedded python ported from bash script
        process = subprocess.run("curl \"http://0.0.0.0:8090/benchmark/jfr-hyperfoil/start?templateParam=ENDPOINT=" + BENCHMARK + "\" | python3 -c \"import sys, json; print(json.load(sys.stdin)['id'])\"", shell=True, check=True, capture_output=True, text=True)
        name = str(process.stdout).strip("\n")
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")

    # sleep until test is done
    time.sleep(7)

    # Get and parse results

    try:
        process = subprocess.run("curl \"http://0.0.0.0:8090/run/" + name + "/stats/all/json\"", shell=True, check=True, capture_output=True, text=True)

        response_json = json.loads(str(process.stdout))

        # record in us
        config["mean"].append(response_json["stats"][0]["total"]["summary"]["meanResponseTime"]/1000)
        config["max"].append(response_json["stats"][0]["total"]["summary"]["maxResponseTime"]/1000)
        config["p50"].append(response_json["stats"][0]["total"]["summary"]["percentileResponseTime"]["50.0"]/1000)
        config["p90"].append(response_json["stats"][0]["total"]["summary"]["percentileResponseTime"]["90.0"]/1000)
        config["p99"].append(response_json["stats"][0]["total"]["summary"]["percentileResponseTime"]["99.0"]/1000)

    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")


# Does a single run of the test, on a single configuration, collecting measurements along the way.
def run_test(config, config_name):
    print("Starting test for configuration: " + config_name)
    shutdown_hyperfoil()
    shutdown_quarkus()
    set_up_hyperfoil()
    
    # Clear caches (Greatly affects startup time)
    try:
        subprocess.run(
            "sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'", shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")

    start_time = time.time()

    # Start quarkus
    try:
        subprocess.run(
            "sudo " + config["run_command"] + " &", shell=True, check=True)
        wait_for_quarkus()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")

    startup = time.time() - start_time

    process = subprocess.run(
        "sudo lsof -t -i:8080", shell=True, check=True, capture_output=True, text=True)
    process = subprocess.run("sudo ps -o rss= -p "+str(process.stdout), shell=True, check=True, capture_output=True, text=True)
    config["rss"].append(int(process.stdout.strip("\n")))
    config["startup"].append(startup)
    run_hyperfoil_benchmark(config)

    shutdown_quarkus()
    shutdown_hyperfoil()



def set_global_variables():
    global RUN_COMMANDS, JAVA_HOME, GRAALVM_HOME, HYPERFOIL_HOME, BUILD_IMAGES, MODE, BENCHMARK

    # Print individual environment variables.
    if "JAVA_HOME" in os.environ:
        JAVA_HOME = os.environ["JAVA_HOME"]
        if not os.path.exists(JAVA_HOME):
            print("JAVA_HOME not set to valid path")
            sys.exit()
    else:
        print("GRAALVM_HOME not set")
        sys.exit()

    if "GRAALVM_HOME" in os.environ:
        GRAALVM_HOME = os.environ["GRAALVM_HOME"]
        if not os.path.exists(GRAALVM_HOME):
            print("GRAALVM_HOME not set to valid path")
            sys.exit()
    else:
        print("GRAALVM_HOME not set")
        sys.exit()

    if "HYPERFOIL_HOME" in os.environ:
        HYPERFOIL_HOME = os.environ["HYPERFOIL_HOME"]
        if not os.path.exists(HYPERFOIL_HOME):
            print("HYPERFOIL_HOME not set to valid path")
            sys.exit()
    else:
        print("HYPERFOIL_HOME not set")
        sys.exit()

    print("Starting test")
    print("JAVA_HOME:", JAVA_HOME)
    print("GRAALVM_HOME:", GRAALVM_HOME)
    print("HYPERFOIL_HOME:", HYPERFOIL_HOME)

    RUN_COMMANDS = [
        "./" + IMAGE_NAME_NO_JFR,
        # "./" + IMAGE_NAME_JFR,
        "./" + IMAGE_NAME_JFR + " -XX:+FlightRecorder -XX:StartFlightRecording=settings=" +
        CWD + "/quarkus-demo.jfc,duration=4s,filename=performance_test.jfr",
        JAVA_HOME + "/bin/java -jar ./target/quarkus-app/quarkus-run.jar",
        JAVA_HOME + "/bin/java -XX:+FlightRecorder -XX:StartFlightRecording=settings=" + CWD +
        "/quarkus-demo.jfc,filename=performance_test_JVM.jfr -jar ./target/quarkus-app/quarkus-run.jar"
    ]

    # Set mode to stress endpoint by default
    if len(sys.argv) > 1:
        MODE = sys.argv[1]
    else:
        MODE = "work"

    if len(sys.argv) > 2 and sys.argv[2] == "false":
        BUILD_IMAGES = False

    if MODE == "work":
        BENCHMARK = "work"
    elif MODE == "regular":
        BENCHMARK = "regular"
    else:
        print("invalid mode specified")
        sys.exit()


def build_apps():
    if not BUILD_IMAGES:
        return
    try:
        # Only clean on initial build. Must use sigprof based handler always! Otherwise too many meaningless recurring callback samples
        subprocess.run("./mvnw clean package -Dnative -DskipTests -Dquarkus.native.monitoring=jfr -Dquarkus.native.additional-build-args=-H:+SignalHandlerBasedExecutionSampler", shell=True, check=True)
        subprocess.run("mv " + IMAGE_NAME_ORIGINAL + " " + IMAGE_NAME_JFR, shell=True, check=True)

        # Build without JFR in image
        subprocess.run("./mvnw package -Dnative -DskipTests", shell=True, check=True)
        subprocess.run("mv " + IMAGE_NAME_ORIGINAL + " " + IMAGE_NAME_NO_JFR, shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")


def get_image_sizes():
    process = subprocess.run("stat -c%s " + IMAGE_NAME_JFR, shell=True, check=True, capture_output=True, text=True)
    file_size_jfr = process.stdout.strip("\n")
    process = subprocess.run("stat -c%s " + IMAGE_NAME_NO_JFR, shell=True, check=True, capture_output=True, text=True)
    file_size_no_jfr = process.stdout.strip("\n")
    return file_size_jfr, file_size_no_jfr



def write_results(file_sizes):
    # print(configurations)

    # Prepare the data structure
    diff_percentages = {"ni": {}, "jdk": {}}
    for diff_percentage in diff_percentages:
        for measurement in measurements:
            diff_percentages[diff_percentage][measurement] = []
            diff_percentages[diff_percentage][measurement+"_average"] = 0

    for i in range(ITERATIONS):
        for measurement in measurements:
            result = (configurations["With JFR"][measurement][i] - configurations["Without JFR in build"][measurement][i]) / configurations["Without JFR in build"][measurement][i]
            diff_percentages["ni"][measurement].append(result)

            diff_percentages["ni"][measurement + "_average"] += result / ITERATIONS

            result = (configurations["Java mode with JFR"][measurement][i] - configurations["Java mode without JFR"][measurement][i]) / configurations["Java mode without JFR"][measurement][i]
            diff_percentages["jdk"][measurement].append(result)

            diff_percentages["jdk"][measurement + "_average"] += result / ITERATIONS

            for config in configurations:
                configurations[config][measurement + "_average"] += configurations[config][measurement][i] / ITERATIONS
            

    # print(diff_percentages)

    current_datetime = datetime.now().isoformat()
    with open("report_"+current_datetime+".txt", 'a') as file:
        file.write("MODE: " + MODE+"\n")
        file.write("ITERATIONS: " + str(ITERATIONS)+"\n")
        file.write("JAVA_HOME: " + JAVA_HOME+"\n")
        file.write("GRAALVM_HOME: " + GRAALVM_HOME+"\n")
        file.write("HYPERFOIL_HOME: " + HYPERFOIL_HOME+"\n\n")

        file.write("Image size with JFR: " + file_sizes[0]+"\n")
        file.write("Image size without JFR: " + file_sizes[1]+"\n")

        file.write("\n------------------------------------------------\n")
        file.write("Average Performance Difference:\n")
        file.write("These values are averages calculated using the results in the 'Performance Difference' section. \n")
        for measurement in measurements:
            file.write(measurement+" (NI): " +
                       str(diff_percentages["ni"][measurement+"_average"])+"\n")
            file.write(measurement + " (JAVA): " +
                       str(diff_percentages["jdk"][measurement+"_average"])+"\n")

        file.write("\n------------------------------------------------\n")
        file.write("Average Measurments:\n")
        file.write("These values are averages calculated using the results in the 'Raw Measurements' section. \n")
        for measurement in measurements:
            for config in configurations:
                file.write(measurement+" (" + config + "): " + str(configurations[config][measurement + "_average"])+"\n")

        file.write("\n------------------------------------------------\n")
        file.write("Performance Difference:\n")
        file.write("These values are calculated pair-wise for each iteration. They are percentages calcluated using (With JFR - Without JFR) / Without JFR. \n")
        for measurement in measurements:
            file.write(measurement+" (NI): " + str(diff_percentages["ni"][measurement])+"\n")
            file.write(measurement+" (JAVA): " + str(diff_percentages["jdk"][measurement])+"\n")

        file.write("\n------------------------------------------------\n")
        file.write("Raw Measurements:\n")
        file.write("These are individual measurements for each iteration. rss is in kB, startup time is ms, all others are in us. \n")
        for config in configurations:
            file.write("\n"+config+":\n")
            for measurement in measurements:
                file.write(measurement+": " + str(configurations[config][measurement])+"\n")


def main():

    set_global_variables()

    # set up the data dictionaries
    count = 0
    for config in configurations:
        configurations[config]["run_command"] = RUN_COMMANDS[count] # ensure run commands and configs match up
        count += 1
        for measurement in measurements:
            configurations[config][measurement] = []
            configurations[config][measurement + "_average"] = 0

    build_apps()
    file_sizes = get_image_sizes()
    
    enableTurboBoost(False)

    # Do the test multiple times.
    for i in range(ITERATIONS):
        ''' 
        Test the full set of configurations as a batch. This way we interleave the runs. 
        It makes more sense to calculate the deltas this way because the diffs wer're comparing are closer temporally (so are more likely to be affected by the same system load etc.).
        '''
        for config in configurations:
            run_test(configurations[config], config)

    enableTurboBoost(True)

    write_results(file_sizes)


# Check if the script is being run directly
if __name__ == "__main__":
    # Call the main function
    main()
