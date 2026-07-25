import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Handles the "Stop & Save?" confirmation dialog pushed from
// gsensrosView.onBack() while a session is recording.
class ConfirmStopDelegate extends WatchUi.ConfirmationDelegate {

    var view as gsensrosView;

    function initialize(view as gsensrosView) {
        ConfirmationDelegate.initialize();
        self.view = view;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            view.stopSession();
            view.prepareToExit();
            System.exit();
        }
        // CONFIRM_NO (or dismissed): just close the dialog and stay in the view.
        return true;
    }
}
