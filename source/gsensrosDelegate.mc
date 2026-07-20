import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

class gsensrosDelegate extends WatchUi.BehaviorDelegate {

    var view as gsensrosView;

    function initialize(view as gsensrosView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() as Boolean {
        return view.onSelect();
    }

    function onBack() as Boolean {
        System.println("Delegate: onBack called");

        try {
            view.prepareToExit();
        } catch (e) {
            try {
                System.println("Delegate onBack cleanup error: " + e.getErrorMessage());
            } catch (ex) {
            }
        }

        // IMPORTANT:
        // Return false so Garmin does the default Back behavior and pops the view.
        return false;
    }
}