class WebProbe {
    static const List<String> debugLog = [];

      static Future<bool> requestMotionAccess() async => true;

        static void watchTilt(void Function(double pitchDeg) onTilt) {}

          static void stopTilt() {}

            static void watchFrame(void Function(double brightness, double sharpness) onFrame) {}
}