#!/usr/bin/env python3
"""Writes Pitwall.xcodeproj: one multiplatform app target (iOS, iPadOS, tvOS, macOS)
using a synchronized folder group, so new Swift files in Pitwall/ are picked up
automatically by Xcode 16 or later.

Usage:  python3 Tools/generate_project.py [build-number]
"""
import hashlib, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
PROJ = os.path.join(ROOT, "Pitwall.xcodeproj")

def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

def current_build():
    path = os.path.join(PROJ, "project.pbxproj")
    if os.path.exists(path):
        m = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", open(path).read())
        if m: return int(m.group(1))
    return 1

BUILD = int(sys.argv[1]) if len(sys.argv) > 1 else current_build()
MARKETING = "1.0.0"
TEAM = "EU3UY476T6"
BUNDLE = "nl.lrvdlinden.pitwall"

I = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "configGroup", "syncGroup", "appRef", "infoRef", "entRef", "ent2Ref",
    "target", "sources", "frameworks", "resources", "projList", "targetList",
    "projDebug", "projRelease", "targetDebug", "targetRelease"]}

common_project = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_FAST_MATH = YES;
"""

project_debug = common_project + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

project_release = common_project + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
"""

target_settings = f"""				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvos*]" = "App Icon & Top Shelf Image";
				"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvsimulator*]" = "App Icon & Top Shelf Image";
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Config/Pitwall.entitlements;
				"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = "Config/Pitwall-macOS.entitlements";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = {BUILD};
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Config/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Pitwall;
				INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
				INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Pitwall zoekt je Apple TV in het lokale netwerk om je F1 TV-login veilig door te geven.";
				"INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphoneos*]" = YES;
				"INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphonesimulator*]" = YES;
				"INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphoneos*]" = YES;
				"INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphonesimulator*]" = YES;
				"INFOPLIST_KEY_UIStatusBarStyle[sdk=iphoneos*]" = UIStatusBarStyleLightContent;
				"INFOPLIST_KEY_UIStatusBarStyle[sdk=iphonesimulator*]" = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UIUserInterfaceStyle = Dark;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
				"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = {MARKETING};
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = auto;
				SUPPORTED_PLATFORMS = "appletvos appletvsimulator iphoneos iphonesimulator macosx";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2,3";
				TVOS_DEPLOYMENT_TARGET = 17.0;
"""

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXFileReference section */
		{I['appRef']} /* Pitwall.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Pitwall.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['infoRef']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{I['entRef']} /* Pitwall-macOS.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "Pitwall-macOS.entitlements"; sourceTree = "<group>"; }};
		{I['ent2Ref']} /* Pitwall.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Pitwall.entitlements; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['syncGroup']} /* Pitwall */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = Pitwall; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['syncGroup']} /* Pitwall */,
				{I['configGroup']} /* Config */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['configGroup']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['infoRef']} /* Info.plist */,
				{I['entRef']} /* Pitwall-macOS.entitlements */,
				{I['ent2Ref']} /* Pitwall.entitlements */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appRef']} /* Pitwall.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['target']} /* Pitwall */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['targetList']} /* Build configuration list for PBXNativeTarget "Pitwall" */;
			buildPhases = (
				{I['sources']} /* Sources */,
				{I['frameworks']} /* Frameworks */,
				{I['resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['syncGroup']} /* Pitwall */,
			);
			name = Pitwall;
			packageProductDependencies = (
			);
			productName = Pitwall;
			productReference = {I['appRef']} /* Pitwall.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {I['projList']} /* Build configuration list for PBXProject "Pitwall" */;
			developmentRegion = nl;
			hasScannedForEncodings = 0;
			knownRegions = (
				nl,
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['target']} /* Pitwall */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{I['projDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{project_debug}			}};
			name = Debug;
		}};
		{I['projRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{project_release}			}};
			name = Release;
		}};
		{I['targetDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{target_settings}			}};
			name = Debug;
		}};
		{I['targetRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{target_settings}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['projList']} /* Build configuration list for PBXProject "Pitwall" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['projDebug']} /* Debug */,
				{I['projRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['targetList']} /* Build configuration list for PBXNativeTarget "Pitwall" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['targetDebug']} /* Debug */,
				{I['targetRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Pitwall.app" BlueprintName = "Pitwall" ReferencedContainer = "container:Pitwall.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Pitwall.app" BlueprintName = "Pitwall" ReferencedContainer = "container:Pitwall.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Pitwall.app" BlueprintName = "Pitwall" ReferencedContainer = "container:Pitwall.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

workspace = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "self:">
   </FileRef>
</Workspace>
"""

os.makedirs(os.path.join(PROJ, "xcshareddata", "xcschemes"), exist_ok=True)
os.makedirs(os.path.join(PROJ, "project.xcworkspace"), exist_ok=True)
open(os.path.join(PROJ, "project.pbxproj"), "w").write(pbx)
open(os.path.join(PROJ, "xcshareddata", "xcschemes", "Pitwall.xcscheme"), "w").write(scheme)
open(os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata"), "w").write(workspace)
print(f"Pitwall.xcodeproj written (version {MARKETING}, build {BUILD})")
