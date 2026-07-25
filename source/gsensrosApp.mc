import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class gsensrosApp extends Application.AppBase {

    // Stores the actual running view so onStop() can clean up the real
    // instance instead of a throwaway one created on the fly.
    var mainView as gsensrosView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        var view = mainView;
        if (view != null && view has :prepareToExit) {
            view.prepareToExit();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new gsensrosView();
        mainView = view;
        return [ view, new gsensrosDelegate(view) ];
    }
}

function getApp() as gsensrosApp {
    return Application.getApp() as gsensrosApp;
}