# WakeScheduler.releasePluginWakeLock() reads this field by reflection.
-keepclassmembers class id.flutter.flutter_background_service.BackgroundService {
    public static *** lockStatic;
}
