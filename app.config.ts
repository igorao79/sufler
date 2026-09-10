import type { ExpoConfig } from 'expo/config';

const APP_GROUP = 'group.com.igorao.sufler';
const BUNDLE_ID = 'com.igorao.sufler';
const APPLE_TEAM_ID = 'GJ2YHZYUJ2';

const config: ExpoConfig = {
  name: 'Sufler',
  slug: 'sufler',
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  scheme: 'sufler',
  userInterfaceStyle: 'dark',
  ios: {
    bundleIdentifier: BUNDLE_ID,
    // Prebuild writes this into DEVELOPMENT_TEAM for every native target, so neither the app nor
    // the share extension needs the team set by hand in Xcode. Not a secret — a Team ID ships
    // inside every provisioning profile.
    appleTeamId: APPLE_TEAM_ID,
    // App Store Connect rejects a re-upload of a build number it has already seen, so this has
    // to be bumped for every upload of the same `version`.
    buildNumber: '4',
    supportsTablet: false,
    infoPlist: {
      // Required by AVPictureInPictureController: without it the PiP window will not open when the
      // app leaves the foreground, which is the entire point of this app. See README for the App
      // Store review implications.
      UIBackgroundModes: ['audio'],
      NSMicrophoneUsageDescription:
        'Sufler слушает вашу речь, чтобы прокручивать текст в такт тому, что вы говорите.',
      NSSpeechRecognitionUsageDescription:
        'Распознавание речи нужно, чтобы находить ваше место в тексте и вести суфлёр за вами.',
      // The two below are required by App Store validation rather than by the app itself.
      // Apple's check looks at what the linked binaries *reference*, not at what they call, so a
      // dependency is enough to demand a string. Neither dialog is ever shown, because Sufler
      // never requests either permission — so the strings say that rather than inventing a
      // purpose. Run `scripts/check-purpose-strings.sh` against an archive to catch new ones.
      //
      // react-native-reanimated links CoreMotion for useAnimatedSensor.
      NSMotionUsageDescription:
        'Sufler не использует датчики движения и не запрашивает к ним доступ.',
      // expo-file-system links Photos for its media-capable file picking API. Sufler imports
      // only .txt and .md, through expo-document-picker.
      NSPhotoLibraryUsageDescription:
        'Sufler не обращается к медиатеке и не запрашивает к ней доступ — импортируются только текстовые файлы.',
      ITSAppUsesNonExemptEncryption: false,
    },
    entitlements: {
      'com.apple.security.application-groups': [APP_GROUP],
    },
  },
  android: {
    // Not supported in v1 — a persistent overlay on Android is a different API with its own review
    // story. The JS layer stays platform-agnostic and the native modules resolve to null.
    package: 'com.igorao.sufler',
    adaptiveIcon: {
      backgroundColor: '#0B0B0F',
      foregroundImage: './assets/android-icon-foreground.png',
      backgroundImage: './assets/android-icon-background.png',
      monochromeImage: './assets/android-icon-monochrome.png',
    },
    predictiveBackGestureEnabled: false,
  },
  plugins: [
    'expo-router',
    [
      'expo-build-properties',
      {
        ios: {
          // AVSampleBufferDisplayLayer.sampleBufferRenderer — the non-deprecated enqueue path.
          deploymentTarget: '17.0',
        },
      },
    ],
    'expo-document-picker',
    './plugins/withSuflerShareExtension',
  ],
  experiments: {
    typedRoutes: true,
  },
};

export default config;
