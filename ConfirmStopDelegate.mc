import Toybox.Lang;
import Toybox.WatchUi;

class ConfirmStopDelegate extends WatchUi.ConfirmationDelegate {

    var view as gsensrosView;

    function initialize(view as gsensrosView) {
        ConfirmationDelegate.initialize();
        self.view = view;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            // User confirmed → stop session and exit
            view.stopSession();
            view.prepareToExit();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // close the confirmation
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // close the main view
        }
        // If NO → just close the confirmation dialog, stay on main view
        return true;
    }
}