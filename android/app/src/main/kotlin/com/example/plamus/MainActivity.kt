package com.example.plamus

import io.flutter.embedding.android.FlutterFragmentActivity

// audio_service / just_audio_background register a MediaBrowserService
// that requires a FragmentActivity host. The default FlutterActivity is a
// plain ComponentActivity, which causes:
//   IllegalStateException: The Activity class declared in your
//   AndroidManifest.xml is wrong or has not provided the correct FlutterEngine.
class MainActivity : FlutterFragmentActivity()
