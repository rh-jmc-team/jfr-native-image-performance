package org.acme.getting.started;

import jakarta.enterprise.context.ApplicationScoped;

import java.util.concurrent.locks.LockSupport;

@ApplicationScoped
public class GreetingService {
    public String greeting(String name) {
        return "hello " + name + "JFR TEST ";
    }

    private String getNextString(String text) throws InterruptedException {
        // This adds about 5ms when JFR is enabled
        LockSupport.parkNanos(1); //Somehow this make it take longer and also increases the gap
        LockSupport.parkNanos(this,1);
        return Integer.toString(text.hashCode() % (int) (Math.random() * 100));
    }

    /** This endpoint is used to test new JFR development changes. Always with JFR recording.
     * Tries to emphasize impact of JFR changes on performance.*/
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

        return result;
    }

    /** This endpoint is used to compare between with/without JFR built into the image.
     * Therefore it must not use any custom JFR events or the Event API at all, to avoid runtime errors.
     * It should have less unrealistic tasks, unlike GreetingService#work which simply loops to create many events.*/
    public String regular(String text) { //TODO not sure how to highlight differences here.
        String result = text;
//        int count = (int) (Math.random() * (30)) + 10;
//
//        for (int i = 0; i < 100; i++) {
//            String temp = Integer.toString(result.hashCode()).repeat(count);
//            result = "";
//            for (int j = 0; j < temp.length(); j += 2) {
//                result += temp.charAt(j);
//            }
//        }
        LockSupport.parkNanos(this,1);
        return result;
    }
}