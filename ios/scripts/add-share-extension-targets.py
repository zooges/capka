#!/usr/bin/env python3
"""Add Share Extension targets + ShareSupport sources to BossYoung / BossYoung2 xcodeprojs."""

from pathlib import Path
import re

IOS = Path("/Users/hanxin/capka-dev/ios")

SHARE_SOURCES = [
    "ShareSupport/ShareHostConfig.swift",
    "ShareSupport/ShareChatIndex.swift",
    "ShareSupport/ShareInboxStore.swift",
    "ShareSupport/ShareViewController.swift",
]

APP_SHARE_SOURCES = [
    "ShareSupport/ShareHostConfig.swift",
    "ShareSupport/ShareChatIndex.swift",
    "ShareSupport/ShareInboxStore.swift",
]


def patch_bossyoung():
    path = IOS / "BossYoung.xcodeproj/project.pbxproj"
    text = path.read_text()
    if "BossYoungShare" in text:
        print("BossYoung.xcodeproj already has Share target")
        return

    # --- PBXBuildFile ---
    build_files = """
		S1BF01 /* ShareHostConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR01 /* ShareHostConfig.swift */; };
		S1BF02 /* ShareChatIndex.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR02 /* ShareChatIndex.swift */; };
		S1BF03 /* ShareInboxStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR03 /* ShareInboxStore.swift */; };
		S1BF04 /* ShareViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR04 /* ShareViewController.swift */; };
		S1BF05 /* ShareHostConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR01 /* ShareHostConfig.swift */; };
		S1BF06 /* ShareChatIndex.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR02 /* ShareChatIndex.swift */; };
		S1BF07 /* ShareInboxStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = S1FR03 /* ShareInboxStore.swift */; };
		S1BF08 /* BossYoungShare.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = S1PR01 /* BossYoungShare.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
"""
    text = text.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_files)

    # --- PBXFileReference ---
    file_refs = """
		S1FR01 /* ShareHostConfig.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareHostConfig.swift; sourceTree = "<group>"; };
		S1FR02 /* ShareChatIndex.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareChatIndex.swift; sourceTree = "<group>"; };
		S1FR03 /* ShareInboxStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareInboxStore.swift; sourceTree = "<group>"; };
		S1FR04 /* ShareViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; };
		S1FR05 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		S1FR06 /* BossYoungShare.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BossYoungShare.entitlements; sourceTree = "<group>"; };
		S1PR01 /* BossYoungShare.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BossYoungShare.appex; sourceTree = BUILT_PRODUCTS_DIR; };
"""
    text = text.replace("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n" + file_refs)

    # --- PBXContainerItemProxy + PBXTargetDependency ---
    proxy = """
/* Begin PBXContainerItemProxy section */
		S1PX01 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A60000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = S1TG01;
			remoteInfo = BossYoungShare;
		};
/* End PBXContainerItemProxy section */

"""
    if "/* Begin PBXContainerItemProxy section */" not in text:
        text = text.replace("/* Begin PBXFileReference section */", proxy + "/* Begin PBXFileReference section */")
    else:
        # unlikely
        pass

    # Groups
    groups = """
		S1GR01 /* ShareSupport */ = {
			isa = PBXGroup;
			children = (
				S1FR01 /* ShareHostConfig.swift */,
				S1FR02 /* ShareChatIndex.swift */,
				S1FR03 /* ShareInboxStore.swift */,
				S1FR04 /* ShareViewController.swift */,
			);
			path = ShareSupport;
			sourceTree = "<group>";
		};
		S1GR02 /* BossYoungShare */ = {
			isa = PBXGroup;
			children = (
				S1FR05 /* Info.plist */,
				S1FR06 /* BossYoungShare.entitlements */,
			);
			path = BossYoungShare;
			sourceTree = "<group>";
		};
"""
    text = text.replace("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n" + groups)

    # Add to main group children (after BossYoungMac)
    text = text.replace(
        "\t\t\t\tA40000000000000000000005 /* BossYoungMac */,\n",
        "\t\t\t\tA40000000000000000000005 /* BossYoungMac */,\n\t\t\t\tS1GR01 /* ShareSupport */,\n\t\t\t\tS1GR02 /* BossYoungShare */,\n",
    )
    # Products
    text = text.replace(
        "\t\t\t\tA20000000000000000000007 /* BossYoung.app */,\n",
        "\t\t\t\tA20000000000000000000007 /* BossYoung.app */,\n\t\t\t\tS1PR01 /* BossYoungShare.appex */,\n",
    )

    # Embed phase + dependency on app target
    embed_phase = """
		S1EP01 /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				S1BF08 /* BossYoungShare.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace(
        "/* Begin PBXResourcesBuildPhase section */",
        "/* Begin PBXCopyFilesBuildPhase section */\n" + embed_phase + "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXResourcesBuildPhase section */",
    )

    text = text.replace(
        """\t\t\tbuildPhases = (
\t\t\t\tA50000000000000000000002 /* Sources */,
\t\t\t\tA30000000000000000000001 /* Frameworks */,
\t\t\t\tA50000000000000000000003 /* Resources */,
\t\t\t\tA50000000000000000000004 /* Embed Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = BossYoung;
""",
        """\t\t\tbuildPhases = (
\t\t\t\tA50000000000000000000002 /* Sources */,
\t\t\t\tA30000000000000000000001 /* Frameworks */,
\t\t\t\tA50000000000000000000003 /* Resources */,
\t\t\t\tA50000000000000000000004 /* Embed Frameworks */,
\t\t\t\tS1EP01 /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\tS1TD01 /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = BossYoung;
""",
    )

    # Share target
    native_target = """
		S1TG01 /* BossYoungShare */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = S1CL01 /* Build configuration list for PBXNativeTarget "BossYoungShare" */;
			buildPhases = (
				S1SP01 /* Sources */,
				S1FP01 /* Frameworks */,
				S1RP01 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = BossYoungShare;
			productName = BossYoungShare;
			productReference = S1PR01 /* BossYoungShare.appex */;
			productType = "com.apple.product-type.app-extension";
		};
"""
    text = text.replace(
        "/* End PBXNativeTarget section */",
        native_target + "/* End PBXNativeTarget section */",
    )

    text = text.replace(
        "\t\t\t\tA50000000000000000000020 /* BossYoungMac */,\n\t\t\t);\n\t\t};\n/* End PBXProject section */",
        "\t\t\t\tA50000000000000000000020 /* BossYoungMac */,\n\t\t\t\tS1TG01 /* BossYoungShare */,\n\t\t\t);\n\t\t};\n/* End PBXProject section */",
    )

    # TargetAttributes
    text = text.replace(
        """\t\t\t\tTargetAttributes = {
\t\t\t\t\tA50000000000000000000001 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t};
""",
        """\t\t\t\tTargetAttributes = {
\t\t\t\t\tA50000000000000000000001 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t\tS1TG01 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t};
""",
    )

    # Frameworks empty phase for share
    frameworks = """
		S1FP01 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXFrameworksBuildPhase section */\n", "/* Begin PBXFrameworksBuildPhase section */\n" + frameworks)

    resources = """
		S1RP01 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXResourcesBuildPhase section */\n", "/* Begin PBXResourcesBuildPhase section */\n" + resources)

    # App sources get ShareSupport (without ViewController)
    text = text.replace(
        "\t\t\t\tA10000000000000000000001 /* BossYoungApp.swift in Sources */,\n",
        "\t\t\t\tA10000000000000000000001 /* BossYoungApp.swift in Sources */,\n\t\t\t\tS1BF05 /* ShareHostConfig.swift in Sources */,\n\t\t\t\tS1BF06 /* ShareChatIndex.swift in Sources */,\n\t\t\t\tS1BF07 /* ShareInboxStore.swift in Sources */,\n",
    )

    share_sources = """
		S1SP01 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				S1BF01 /* ShareHostConfig.swift in Sources */,
				S1BF02 /* ShareChatIndex.swift in Sources */,
				S1BF03 /* ShareInboxStore.swift in Sources */,
				S1BF04 /* ShareViewController.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXSourcesBuildPhase section */\n", "/* Begin PBXSourcesBuildPhase section */\n" + share_sources)

    # Target dependency
    dep = """
/* Begin PBXTargetDependency section */
		S1TD01 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = S1TG01 /* BossYoungShare */;
			targetProxy = S1PX01 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

"""
    if "/* Begin PBXTargetDependency section */" not in text:
        text = text.replace("/* Begin XCBuildConfiguration section */", dep + "/* Begin XCBuildConfiguration section */")

    # Build configs for share extension
    configs = """
		S1CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = BossYoungShare/BossYoungShare.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 28;
				DEVELOPMENT_TEAM = 5FSTWGBV38;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BossYoungShare/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.4;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		S1CFG2 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = BossYoungShare/BossYoungShare.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 28;
				DEVELOPMENT_TEAM = 5FSTWGBV38;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BossYoungShare/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.4;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
"""
    text = text.replace("/* End XCBuildConfiguration section */", configs + "/* End XCBuildConfiguration section */")

    config_list = """
		S1CL01 /* Build configuration list for PBXNativeTarget "BossYoungShare" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				S1CFG1 /* Debug */,
				S1CFG2 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
"""
    text = text.replace("/* End XCConfigurationList section */", config_list + "/* End XCConfigurationList section */")

    # Fix container proxy placement - I may have inserted before FileReference incorrectly if proxy section already issues
    # Ensure PBXContainerItemProxy exists once
    if text.count("S1PX01 /* PBXContainerItemProxy */") != 2:
        # one def + one ref in dependency - ok if 2
        pass

    path.write_text(text)
    print("patched BossYoung.xcodeproj")


def patch_bossyoung2():
    path = IOS / "BossYoung2.xcodeproj/project.pbxproj"
    text = path.read_text()
    if "BossYoung2Share" in text:
        print("BossYoung2.xcodeproj already has Share target")
        return

    # Find project object id and main target id
    # From earlier: B2P000000000000000000001 project, B2T target for app
    m = re.search(r"([A-F0-9]{24}|B2[A-Z0-9]+) /\* Project object \*/", text)
    # BossYoung2 uses B2P000000000000000000001 style
    proj_id = "B2P000000000000000000001"
    if "B2P000000000000000000001 /* Project object */" not in text:
        # try find
        m = re.search(r"(\w+) /\* Project object \*/", text)
        if not m:
            raise SystemExit("no project object")
        proj_id = m.group(1)

    m = re.search(r"(\w+) /\* BossYoung2 \*/ = \{\n\t\t\tisa = PBXNativeTarget;", text)
    if not m:
        raise SystemExit("no BossYoung2 target")
    app_target = m.group(1)

    m = re.search(r"(\w+) /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;", text)
    app_sources = m.group(1) if m else None

    build_files = """
		S2BF01 /* ShareHostConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR01 /* ShareHostConfig.swift */; };
		S2BF02 /* ShareChatIndex.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR02 /* ShareChatIndex.swift */; };
		S2BF03 /* ShareInboxStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR03 /* ShareInboxStore.swift */; };
		S2BF04 /* ShareViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR04 /* ShareViewController.swift */; };
		S2BF05 /* ShareHostConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR01 /* ShareHostConfig.swift */; };
		S2BF06 /* ShareChatIndex.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR02 /* ShareChatIndex.swift */; };
		S2BF07 /* ShareInboxStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = S2FR03 /* ShareInboxStore.swift */; };
		S2BF08 /* BossYoung2Share.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = S2PR01 /* BossYoung2Share.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
"""
    text = text.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_files)

    file_refs = """
		S2FR01 /* ShareHostConfig.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareHostConfig.swift; sourceTree = "<group>"; };
		S2FR02 /* ShareChatIndex.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareChatIndex.swift; sourceTree = "<group>"; };
		S2FR03 /* ShareInboxStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareInboxStore.swift; sourceTree = "<group>"; };
		S2FR04 /* ShareViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; };
		S2FR05 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		S2FR06 /* BossYoung2Share.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BossYoung2Share.entitlements; sourceTree = "<group>"; };
		S2PR01 /* BossYoung2Share.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BossYoung2Share.appex; sourceTree = BUILT_PRODUCTS_DIR; };
"""
    text = text.replace("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n" + file_refs)

    if "/* Begin PBXContainerItemProxy section */" not in text:
        proxy = f"""
/* Begin PBXContainerItemProxy section */
		S2PX01 /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {proj_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = S2TG01;
			remoteInfo = BossYoung2Share;
		}};
/* End PBXContainerItemProxy section */

"""
        text = text.replace("/* Begin PBXFileReference section */", proxy + "/* Begin PBXFileReference section */")

    groups = """
		S2GR01 /* ShareSupport */ = {
			isa = PBXGroup;
			children = (
				S2FR01 /* ShareHostConfig.swift */,
				S2FR02 /* ShareChatIndex.swift */,
				S2FR03 /* ShareInboxStore.swift */,
				S2FR04 /* ShareViewController.swift */,
			);
			path = ShareSupport;
			sourceTree = "<group>";
		};
		S2GR02 /* BossYoung2Share */ = {
			isa = PBXGroup;
			children = (
				S2FR05 /* Info.plist */,
				S2FR06 /* BossYoung2Share.entitlements */,
			);
			path = BossYoung2Share;
			sourceTree = "<group>";
		};
"""
    text = text.replace("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n" + groups)

    # main group - find children with BossYoung2
    text = text.replace(
        "\t\t\t\tB2G000000000000000000002 /* BossYoung2 */,\n",
        "\t\t\t\tB2G000000000000000000002 /* BossYoung2 */,\n\t\t\t\tS2GR01 /* ShareSupport */,\n\t\t\t\tS2GR02 /* BossYoung2Share */,\n",
    )
    # fallback if group id differs
    if "S2GR01 /* ShareSupport */" not in text:
        text = re.sub(
            r"(children = \(\n\t\t\t\t)(\w+ /\* BossYoung2 \*/,\n)",
            r"\1\2\t\t\t\tS2GR01 /* ShareSupport */,\n\t\t\t\tS2GR02 /* BossYoung2Share */,\n",
            text,
            count=1,
        )

    text = re.sub(
        r"(B2R000000000000000000001 /\* BossYoung2\.app \*/,\n)",
        r"\1\t\t\t\tS2PR01 /* BossYoung2Share.appex */,\n",
        text,
        count=1,
    )
    if "S2PR01 /* BossYoung2Share.appex */" not in text:
        text = re.sub(
            r"(\w+ /\* BossYoung2\.app \*/,\n)",
            r"\1\t\t\t\tS2PR01 /* BossYoung2Share.appex */,\n",
            text,
            count=1,
        )

    embed = """
		S2EP01 /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				S2BF08 /* BossYoung2Share.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    if "/* Begin PBXCopyFilesBuildPhase section */" in text:
        text = text.replace("/* Begin PBXCopyFilesBuildPhase section */\n", "/* Begin PBXCopyFilesBuildPhase section */\n" + embed)
    else:
        text = text.replace(
            "/* Begin PBXResourcesBuildPhase section */",
            "/* Begin PBXCopyFilesBuildPhase section */\n" + embed + "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXResourcesBuildPhase section */",
        )

    # Patch app target buildPhases + dependencies
    text = re.sub(
        rf"({app_target} /\* BossYoung2 \*/ = \{{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = \w+ /\* Build configuration list for PBXNativeTarget \"BossYoung2\" \*/;\n\t\t\tbuildPhases = \(\n)([\s\S]*?)(\t\t\t\);\n\t\t\tbuildRules = \(\n\t\t\t\);\n\t\t\tdependencies = \(\n\t\t\t\);",
        rf"\1\2\t\t\t\tS2EP01 /* Embed Foundation Extensions */,\n\3\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\tS2TD01 /* PBXTargetDependency */,\n\t\t\t);",
        text,
        count=1,
    )
    # Simpler approach if regex failed
    if "S2EP01 /* Embed Foundation Extensions */" not in text.split("name = BossYoung2;")[0][-800:]:
        # find BossYoung2 target block and inject before buildRules
        def inject_app(m):
            block = m.group(0)
            if "S2EP01" in block:
                return block
            block = block.replace(
                "\t\t\tdependencies = (\n\t\t\t);",
                "\t\t\tdependencies = (\n\t\t\t\tS2TD01 /* PBXTargetDependency */,\n\t\t\t);",
            )
            # add embed phase before closing buildPhases
            block = re.sub(
                r"(buildPhases = \(\n(?:\t\t\t\t.+\n)+)(\t\t\t\);)",
                r"\1\t\t\t\tS2EP01 /* Embed Foundation Extensions */,\n\2",
                block,
                count=1,
            )
            return block
        text2, n = re.subn(
            rf"{app_target} /\* BossYoung2 \*/ = \{{[\s\S]*?productType = \"com\.apple\.product-type\.application\";\n\t\t\}};",
            inject_app,
            text,
            count=1,
        )
        if n:
            text = text2
            print("injected embed via fallback")

    native = """
		S2TG01 /* BossYoung2Share */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = S2CL01 /* Build configuration list for PBXNativeTarget "BossYoung2Share" */;
			buildPhases = (
				S2SP01 /* Sources */,
				S2FP01 /* Frameworks */,
				S2RP01 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = BossYoung2Share;
			productName = BossYoung2Share;
			productReference = S2PR01 /* BossYoung2Share.appex */;
			productType = "com.apple.product-type.app-extension";
		};
"""
    text = text.replace("/* End PBXNativeTarget section */", native + "/* End PBXNativeTarget section */")

    text = re.sub(
        r"(targets = \(\n\t\t\t\t" + app_target + r" /\* BossYoung2 \*/,)\n\t\t\t\);",
        r"\1\n\t\t\t\tS2TG01 /* BossYoung2Share */,\n\t\t\t);",
        text,
        count=1,
    )

    frameworks = """
		S2FP01 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXFrameworksBuildPhase section */\n", "/* Begin PBXFrameworksBuildPhase section */\n" + frameworks)

    resources = """
		S2RP01 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXResourcesBuildPhase section */\n", "/* Begin PBXResourcesBuildPhase section */\n" + resources)

    share_sources = """
		S2SP01 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				S2BF01 /* ShareHostConfig.swift in Sources */,
				S2BF02 /* ShareChatIndex.swift in Sources */,
				S2BF03 /* ShareInboxStore.swift in Sources */,
				S2BF04 /* ShareViewController.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
    text = text.replace("/* Begin PBXSourcesBuildPhase section */\n", "/* Begin PBXSourcesBuildPhase section */\n" + share_sources)

    # Add share support to app sources - after AppConfig
    text = text.replace(
        "\t\t\t\tB2B0000000001000000000000 /* AppConfig.swift in Sources */,\n",
        "\t\t\t\tB2B0000000001000000000000 /* AppConfig.swift in Sources */,\n\t\t\t\tS2BF05 /* ShareHostConfig.swift in Sources */,\n\t\t\t\tS2BF06 /* ShareChatIndex.swift in Sources */,\n\t\t\t\tS2BF07 /* ShareInboxStore.swift in Sources */,\n",
    )

    dep = """
/* Begin PBXTargetDependency section */
		S2TD01 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = S2TG01 /* BossYoung2Share */;
			targetProxy = S2PX01 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

"""
    if "/* Begin PBXTargetDependency section */" not in text:
        text = text.replace("/* Begin XCBuildConfiguration section */", dep + "/* Begin XCBuildConfiguration section */")

    # Add BOSSYOUNG2 to app configs + share configs
    text = text.replace(
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka2;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";\n\t\t\t\tSUPPORTS_MACCATALYST = NO;\n\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n\t\t\t\tSWIFT_VERSION = 5.0;\n",
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka2;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";\n\t\t\t\tSUPPORTS_MACCATALYST = NO;\n\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"$(inherited) BOSSYOUNG2\";\n\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n\t\t\t\tSWIFT_VERSION = 5.0;\n",
    )

    configs = """
		S2CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = BossYoung2Share/BossYoung2Share.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 11;
				DEVELOPMENT_TEAM = 5FSTWGBV38;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BossYoung2Share/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.4;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka2.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) BOSSYOUNG2";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		S2CFG2 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = BossYoung2Share/BossYoung2Share.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 11;
				DEVELOPMENT_TEAM = 5FSTWGBV38;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BossYoung2Share/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.4;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.bossyoung.capka2.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) BOSSYOUNG2";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
"""
    text = text.replace("/* End XCBuildConfiguration section */", configs + "/* End XCBuildConfiguration section */")

    config_list = """
		S2CL01 /* Build configuration list for PBXNativeTarget "BossYoung2Share" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				S2CFG1 /* Debug */,
				S2CFG2 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
"""
    text = text.replace("/* End XCConfigurationList section */", config_list + "/* End XCConfigurationList section */")

    path.write_text(text)
    print("patched BossYoung2.xcodeproj")


if __name__ == "__main__":
    patch_bossyoung()
    patch_bossyoung2()
