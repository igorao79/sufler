import type { ExpoConfig } from 'expo/config';

const APP_GROUP = 'group.com.igorao.sufler';
const BUNDLE_ID = 'com.igorao.sufler';

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
