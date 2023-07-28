# jfr-native-image-performance

### Summary
This test builds graalvm master branch and uses it to build a simple custom Quarkus native app that has been rigged to produce more JFR events. It measures time to first repsonse, RSS (measured upon start up), image size, and runs a hyperfoil benchmark to gather repsone time data. Then it produces `performance_test_results.txt` which summarizes the results. 

### Configurations Tested

- Master branch without JFR in the image build
- Master branch with JFR recording 
- Master branch with JFR in the build but not recording

These three configurations are each tested using two different hyperfoil benchmarks. The same quarkus app is used for both, just at different endpoints. 

The `normal_case_benchmark.hf.yaml` benchmark hits an endpoint that is supposed to be more similar to what a quarkus app might do under normal circumstances (possibly emitting a few events while handling the request). For example, this scenario is useful for obtaining some rough figures describing how JFR is impacting performance in general. 

The `worst_case_benchmark.hf.yaml` benchmark is supposed to generate an unrealistic number of JFR events. This should help highlight the impact any changes to the substrateVM JFR infrastructure have on performance. For example, this scenario is useful for testing with/without new development changes before deciding to merge them.

### Usage
Before running the test, set the paths at the top of `master_test.sh`.

`sudo` is needed to turn off turbo boost and clear caches. 

`sudo ./master_test.sh`  To build master branch and build everything from scratch before running.

`sudo ./master_test.sh -g` To skip building graalVM native-image utility and only rebuild quarkus apps before running the test.

`sudo ./master_test.sh -q` To skip building graalVM and skip rebuilding the quarkus apps. Simply run the tests on the quarkus native executables that are already built.