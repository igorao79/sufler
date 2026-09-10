import {
  withDangerousMod,
  withEntitlementsPlist,
  withPlugins,
  withXcodeProject,
  type ConfigPlugin,
} from 'expo/config-plugins';
import * as fs from 'fs';
import * as path from 'path';

const APP_GROUP = 'group.com.igorao.sufler';
const TARGET_NAME = 'SuflerShare';
const SOURCE_DIR = 'plugins/share-extension-files';
const DEPLOYMENT_TARGET = '17.0';

/**
 * Adds the "Share to Sufler" extension target.
 *
 * Written by hand rather than pulled from a community plugin because the extension itself is
 * ~150 lines of plain Swift with no React Native in it, and because hand-editing `ios/` is not an
 * option — `expo prebuild --clean` wipes it. `withXcodeProject` manipulation of the pbxproj is the
 * most brittle thing in this repository; if a prebuild ever produces a project without the
 * SuflerShare target or without the PlugIns copy phase, this file is where to look.
 */
const withSuflerShareExtension: ConfigPlugin = (config) =>
  withPlugins(config, [
    withAppGroupEntitlement,
    withCopiedSources,
    withExtensionTarget,
  ]);

/** The App Group has to be on the main app as well, or the two processes cannot see each other. */
const withAppGroupEntitlement: ConfigPlugin = (config) =>
  withEntitlementsPlist(config, (config) => {
    const key = 'com.apple.security.application-groups';
    const existing = (config.modResults[key] as string[] | undefined) ?? [];
    if (!existing.includes(APP_GROUP)) {
      config.modResults[key] = [...existing, APP_GROUP];
    }
    return config;
  });

const withCopiedSources: ConfigPlugin = (config) =>
  withDangerousMod(config, [
    'ios',
    async (config) => {
      const from = path.join(config.modRequest.projectRoot, SOURCE_DIR);
      const to = path.join(config.modRequest.platformProjectRoot, TARGET_NAME);

      fs.mkdirSync(to, { recursive: true });
      for (const file of fs.readdirSync(from)) {
        fs.copyFileSync(path.join(from, file), path.join(to, file));
      }
      return config;
    },
  ]);

const withExtensionTarget: ConfigPlugin = (config) =>
  withXcodeProject(config, (config) => {
    const project = config.modResults;
    const bundleIdentifier = `${config.ios?.bundleIdentifier ?? 'com.igorao.sufler'}.share`;
    // Set explicitly rather than relying on Expo's own `withDevelopmentTeam`: that mod may run
    // before this one, and a target created afterwards would then be left unsigned.
    const appleTeamId = config.ios?.appleTeamId;
    // The extension's Info.plist reads these through $(MARKETING_VERSION) and
    // $(CURRENT_PROJECT_VERSION); App Store validation fails if they drift from the app's.
    const marketingVersion = config.version ?? '1.0.0';
    const buildNumber = config.ios?.buildNumber ?? '1';

    // Prebuild can run more than once against the same project; adding the target twice produces
    // a project that fails to open.
    if (project.pbxTargetByName(TARGET_NAME)) {
      return config;
    }

    const files = ['ShareViewController.swift', 'Info.plist', `${TARGET_NAME}.entitlements`];

    const group = project.addPbxGroup(files, TARGET_NAME, TARGET_NAME);

    // Hang the new group off the project's main group so the files show up in Xcode's navigator.
    const mainGroupUuid = project.getFirstProject().firstProject.mainGroup;
    const mainGroup = project.hash.project.objects.PBXGroup[mainGroupUuid];
    if (mainGroup?.children) {
      mainGroup.children.push({ value: group.uuid, comment: TARGET_NAME });
    }

    // `addTarget` with type `app_extension` also creates the PlugIns copy-files phase on the app
    // target, embeds the product into it, and registers the target dependency.
    const target = project.addTarget(TARGET_NAME, 'app_extension', TARGET_NAME, bundleIdentifier);

    // `addPbxGroup` above already registered the file reference and build file, so this reuses
    // them rather than creating a second reference to the same path.
    project.addBuildPhase(
      ['ShareViewController.swift'],
      'PBXSourcesBuildPhase',
      'Sources',
      target.uuid,
    );
    project.addBuildPhase([], 'PBXResourcesBuildPhase', 'Resources', target.uuid);
    project.addBuildPhase([], 'PBXFrameworksBuildPhase', 'Frameworks', target.uuid);

    const configurations = project.pbxXCBuildConfigurationSection();
    for (const key of Object.keys(configurations)) {
      const settings = configurations[key].buildSettings;
      if (!settings || settings.PRODUCT_NAME !== `"${TARGET_NAME}"`) continue;

      settings.PRODUCT_BUNDLE_IDENTIFIER = `"${bundleIdentifier}"`;
      settings.INFOPLIST_FILE = `"${TARGET_NAME}/Info.plist"`;
      settings.CODE_SIGN_ENTITLEMENTS = `"${TARGET_NAME}/${TARGET_NAME}.entitlements"`;
      settings.IPHONEOS_DEPLOYMENT_TARGET = DEPLOYMENT_TARGET;
      settings.SWIFT_VERSION = '5.9';
      settings.TARGETED_DEVICE_FAMILY = '"1"';
      settings.CODE_SIGN_STYLE = 'Automatic';
      if (appleTeamId) settings.DEVELOPMENT_TEAM = appleTeamId;
      settings.MARKETING_VERSION = marketingVersion;
      settings.CURRENT_PROJECT_VERSION = buildNumber;
      settings.SKIP_INSTALL = 'YES';
      settings.CLANG_ENABLE_MODULES = 'YES';
      // The extension is embedded in the app bundle; without this the linker looks in the wrong
      // place for the Swift runtime at load time.
      settings.LD_RUNPATH_SEARCH_PATHS =
        '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"';
    }

    return config;
  });

export default withSuflerShareExtension;
