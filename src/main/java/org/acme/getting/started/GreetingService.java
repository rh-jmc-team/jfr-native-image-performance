package org.acme.getting.started;

import jakarta.enterprise.context.ApplicationScoped;

import java.util.concurrent.locks.LockSupport;

@ApplicationScoped
public class GreetingService {
//    private static volatile long count;
//    private static final long MOD = 10;
//    private static final long GC_MOD = 100;
//    private static final int ALIGNED_HEAP_CHUNK_SIZE = 512 * 1024;

    public String greeting(String name) {
        return "hello " + name + "JFR TEST ";
    }

    private String getNextString(String text) throws InterruptedException {
        // This adds about 5ms when JFR is enabled
        LockSupport.parkNanos(1); //Somehow this make it take longer and also increases the gap
        LockSupport.parkNanos(this,1);
        return Integer.toString(text.hashCode() % (int) (Math.random() * 100));
    }

    // Goal here is to create events to drive the JFR infrastructure
    // TODO add vthread events
    // TODO add event streaming callbacks (event streaming already occurs)
    public String work(String text) {
        String result = "";
        for (int i = 0; i < 1000; i++){
            try {
                result += getNextString(text);
            } catch (Exception e) {
                // Doesn't matter. Do nothing
            }
            // This adds about 5ms when jfr is enabled
            CustomEvent customEvent = new CustomEvent();
            customEvent.message = result;
            customEvent.commit();
        }

        //  This should result in a new TLAB being required
//        int[] array = new int[ALIGNED_HEAP_CHUNK_SIZE / 4];
//        array[0] = text.length();
//        result += Integer.toString(array[0]+1);

        return result;
    }

//    public String work(String text) {
//        String result = "";
//        for (int i = 0; i < 10; i++){
//            try {
//                result += getNextString(text);
//            } catch (Exception e) {
//                // Doesn't matter. Do nothing
//            }
//        }
//        CustomEvent customEvent = new CustomEvent();
//        customEvent.message = text;
//        customEvent.commit();
//
//
//
//        //  This should result in a new TLAB being required
//        int[] array = new int[ALIGNED_HEAP_CHUNK_SIZE];
//        array[0] = text.length() - 1;
//        array[1] = text.length();
//        for(int i=2; i<10; ++i) {
//            array[i]=array[i-1]+array[i-2];
//        }
//        result += Integer.toString(array[10-1]);
//
//
//        return result;
//    }
}
