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

    // Goal here is to create events to drive the JFR infrastructure
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
}
