# jfr-native-image-performance

### Summary
This test builds a simple custom Quarkus native app that has been rigged to produce more JFR events. It measures time to first repsonse, RSS (measured upon start up), image size, and runs a hyperfoil benchmark to gather response latency data. Then it produces `report_date.txt` which summarizes the results. 

### Configurations Tested

1. Native Image with JFR enabled
2. Native Image without JFR in the build
3. Java with JFR enabled
4. Java without JFR enabled


All configurations are tested in a single run.

The Quarkus app has two endpoints `regular` and `work` which are meant to be used for two different benchmarks. 

The `regular` endpoint is supposed to be more similar to what a quarkus app might do under normal circumstances (possibly emitting a few events while handling the request). For example, this scenario is useful for obtaining some rough figures describing how JFR is impacting performance in general. 

The `work` endpoint generates an unrealistic number of JFR events. This should help highlight the impact any changes to the substrateVM JFR infrastructure have on performance. For example, this scenario is useful for testing with/without new development changes before deciding to merge them.

Hyperfoil templating is used to select between the endpoints depending on the benchmark being performed.

### Requirements

- Java 17+
- GraalVM
- ps
- python3.8
- hyperfoil
- linux

If you are interested in this project, you probably already have been using most of these tools in order build native image executables. The only requirement you may be missing is [Hyperfoil](https://hyperfoil.io/).

### Usage
Before running the test, export the required environment variables:
- **JAVA_HOME**:    Path to JDK
- **GRAALVM_HOME**:   Path to GraalVM
- **HYPERFOIL_HOME**:    Path to hyperfoil

You may be prompted to enter your password since `sudo` is needed to turn off turbo boost and clear caches. 

Usage: `python3.8 performance_test.py <endpoint> <allow_building_images>`

`python3.8 performance_test.py` will build the Native Image Quarkus apps and run the test using the "work" endpoint.

`python3.8 performance_test.py regular false` will run the test using the "regular" endpoint without rebuilding the images.