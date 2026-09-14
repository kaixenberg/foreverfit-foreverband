import os
import uuid

def generate_uuid():
    return uuid.uuid4().hex[:24].upper()

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    app_dir = os.path.join(root_dir, "ForeverFit")
    test_dir = os.path.join(root_dir, "ForeverFitTests")
    resources_dir = os.path.join(app_dir, "Resources")

    app_files = []
    for dirpath, _, filenames in os.walk(app_dir):
        if "Resources" in dirpath or "Assets.xcassets" in dirpath:
            continue
        for f in filenames:
            if f.endswith(".swift"):
                rel_path = os.path.relpath(os.path.join(dirpath, f), root_dir)
                app_files.append((f, rel_path))

    test_files = []
    if os.path.exists(test_dir):
        for dirpath, _, filenames in os.walk(test_dir):
            for f in filenames:
                if f.endswith(".swift"):
                    rel_path = os.path.relpath(os.path.join(dirpath, f), root_dir)
                    test_files.append((f, rel_path))

    resource_files = []
    if os.path.exists(resources_dir):
        for f in os.listdir(resources_dir):
            if not f.startswith("."):
                rel_path = os.path.relpath(os.path.join(resources_dir, f), root_dir)
                resource_files.append((f, rel_path))

    # Static IDs
    proj_id = "010000000000000000000001"
    main_group_id = "010000000000000000000002"
    products_group_id = "010000000000000000000003"
    app_target_id = "010000000000000000000010"
    app_product_id = "010000000000000000000011"
    app_sources_build_phase_id = "010000000000000000000012"
    app_frameworks_build_phase_id = "010000000000000000000013"
    app_resources_build_phase_id = "010000000000000000000014"

    test_target_id = "010000000000000000000020"
    test_product_id = "010000000000000000000021"
    test_sources_build_phase_id = "010000000000000000000022"
    test_frameworks_build_phase_id = "010000000000000000000023"
    test_resources_build_phase_id = "010000000000000000000024"
    target_dep_id = "010000000000000000000025"
    container_item_proxy_id = "010000000000000000000026"

    # Configs
    proj_config_list_id = "010000000000000000000030"
    proj_debug_config_id = "010000000000000000000031"
    proj_release_config_id = "010000000000000000000032"

    app_config_list_id = "010000000000000000000040"
    app_debug_config_id = "010000000000000000000041"
    app_release_config_id = "010000000000000000000042"

    test_config_list_id = "010000000000000000000050"
    test_debug_config_id = "010000000000000000000051"
    test_release_config_id = "010000000000000000000052"

    assets_file_id = "010000000000000000000060"
    assets_build_id = "010000000000000000000061"

    # Build file mapping
    app_file_entries = []
    for fname, fpath in app_files:
        f_id = generate_uuid()
        b_id = generate_uuid()
        app_file_entries.append((fname, fpath, f_id, b_id))

    test_file_entries = []
    for fname, fpath in test_files:
        f_id = generate_uuid()
        b_id = generate_uuid()
        test_file_entries.append((fname, fpath, f_id, b_id))

    resource_file_entries = []
    for fname, fpath in resource_files:
        f_id = generate_uuid()
        b_id = generate_uuid()
        resource_file_entries.append((fname, fpath, f_id, b_id))

    pbx = []
    pbx.append("// !$*UTF8*$!")
    pbx.append("{")
    pbx.append("\tarchiveVersion = 1;")
    pbx.append("\tclasses = {")
    pbx.append("\t};")
    pbx.append("\tobjectVersion = 56;")
    pbx.append("\tobjects = {")

    # PBXBuildFile
    pbx.append("/* Begin PBXBuildFile section */")
    for fname, fpath, f_id, b_id in app_file_entries:
        pbx.append(f"\t\t{b_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {fname} */; }};")
    for fname, fpath, f_id, b_id in test_file_entries:
        pbx.append(f"\t\t{b_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {fname} */; }};")
    for fname, fpath, f_id, b_id in resource_file_entries:
        pbx.append(f"\t\t{b_id} /* {fname} in Resources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {fname} */; }};")
    pbx.append(f"\t\t{assets_build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_file_id} /* Assets.xcassets */; }};")
    pbx.append("/* End PBXBuildFile section */\n")

    # PBXContainerItemProxy
    pbx.append("/* Begin PBXContainerItemProxy section */")
    pbx.append(f"\t\t{container_item_proxy_id} /* PBXContainerItemProxy */ = {{")
    pbx.append("\t\t\tisa = PBXContainerItemProxy;")
    pbx.append(f"\t\t\tcontainerPortal = {proj_id} /* Project object */;")
    pbx.append("\t\t\tproxyType = 1;")
    pbx.append(f"\t\t\tremoteGlobalIDString = {app_target_id};")
    pbx.append("\t\t\tremoteInfo = ForeverFit;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXContainerItemProxy section */\n")

    # PBXFileReference
    pbx.append("/* Begin PBXFileReference section */")
    pbx.append(f"\t\t{app_product_id} /* ForeverFit.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ForeverFit.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    pbx.append(f"\t\t{test_product_id} /* ForeverFitTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ForeverFitTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    pbx.append(f"\t\t{assets_file_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"ForeverFit/Assets.xcassets\"; sourceTree = SOURCE_ROOT; }};")

    for fname, fpath, f_id, b_id in app_file_entries:
        pbx.append(f"\t\t{f_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = \"{fname}\"; path = \"{fpath}\"; sourceTree = SOURCE_ROOT; }};")
    for fname, fpath, f_id, b_id in test_file_entries:
        pbx.append(f"\t\t{f_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = \"{fname}\"; path = \"{fpath}\"; sourceTree = SOURCE_ROOT; }};")
    for fname, fpath, f_id, b_id in resource_file_entries:
        pbx.append(f"\t\t{f_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = file; name = \"{fname}\"; path = \"{fpath}\"; sourceTree = SOURCE_ROOT; }};")
    pbx.append("/* End PBXFileReference section */\n")

    # PBXFrameworksBuildPhase
    pbx.append("/* Begin PBXFrameworksBuildPhase section */")
    pbx.append(f"\t\t{app_frameworks_build_phase_id} /* Frameworks */ = {{")
    pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_frameworks_build_phase_id} /* Frameworks */ = {{")
    pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXFrameworksBuildPhase section */\n")

    # PBXGroup
    pbx.append("/* Begin PBXGroup section */")
    pbx.append(f"\t\t{main_group_id} = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    for fname, fpath, f_id, _ in app_file_entries:
        pbx.append(f"\t\t\t\t{f_id} /* {fname} */,")
    for fname, fpath, f_id, _ in test_file_entries:
        pbx.append(f"\t\t\t\t{f_id} /* {fname} */,")
    for fname, fpath, f_id, _ in resource_file_entries:
        pbx.append(f"\t\t\t\t{f_id} /* {fname} */,")
    pbx.append(f"\t\t\t\t{assets_file_id} /* Assets.xcassets */,")
    pbx.append(f"\t\t\t\t{products_group_id} /* Products */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{products_group_id} /* Products */ = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    pbx.append(f"\t\t\t\t{app_product_id} /* ForeverFit.app */,")
    pbx.append(f"\t\t\t\t{test_product_id} /* ForeverFitTests.xctest */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = Products;")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
    pbx.append("/* End PBXGroup section */\n")

    # PBXNativeTarget
    pbx.append("/* Begin PBXNativeTarget section */")
    pbx.append(f"\t\t{app_target_id} /* ForeverFit */ = {{")
    pbx.append("\t\t\tisa = PBXNativeTarget;")
    pbx.append(f"\t\t\tbuildConfigurationList = {app_config_list_id} /* Build configuration list for PBXNativeTarget \"ForeverFit\" */;")
    pbx.append("\t\t\tbuildPhases = (")
    pbx.append(f"\t\t\t\t{app_sources_build_phase_id} /* Sources */,")
    pbx.append(f"\t\t\t\t{app_frameworks_build_phase_id} /* Frameworks */,")
    pbx.append(f"\t\t\t\t{app_resources_build_phase_id} /* Resources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tbuildRules = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdependencies = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = ForeverFit;")
    pbx.append("\t\t\tproductName = ForeverFit;")
    pbx.append(f"\t\t\tproductReference = {app_product_id} /* ForeverFit.app */;")
    pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_target_id} /* ForeverFitTests */ = {{")
    pbx.append("\t\t\tisa = PBXNativeTarget;")
    pbx.append(f"\t\t\tbuildConfigurationList = {test_config_list_id} /* Build configuration list for PBXNativeTarget \"ForeverFitTests\" */;")
    pbx.append("\t\t\tbuildPhases = (")
    pbx.append(f"\t\t\t\t{test_sources_build_phase_id} /* Sources */,")
    pbx.append(f"\t\t\t\t{test_frameworks_build_phase_id} /* Frameworks */,")
    pbx.append(f"\t\t\t\t{test_resources_build_phase_id} /* Resources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tbuildRules = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdependencies = (")
    pbx.append(f"\t\t\t\t{target_dep_id} /* PBXTargetDependency */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = ForeverFitTests;")
    pbx.append("\t\t\tproductName = ForeverFitTests;")
    pbx.append(f"\t\t\tproductReference = {test_product_id} /* ForeverFitTests.xctest */;")
    pbx.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    pbx.append("\t\t};")
    pbx.append("/* End PBXNativeTarget section */\n")

    # PBXProject
    pbx.append("/* Begin PBXProject section */")
    pbx.append(f"\t\t{proj_id} /* Project object */ = {{")
    pbx.append("\t\t\tisa = PBXProject;")
    pbx.append("\t\t\tattributes = {")
    pbx.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    pbx.append("\t\t\t\tLastUpgradeCheck = 1600;")
    pbx.append("\t\t\t\tTargetAttributes = {")
    pbx.append(f"\t\t\t\t\t{app_target_id} = {{")
    pbx.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    pbx.append("\t\t\t\t\t};")
    pbx.append(f"\t\t\t\t\t{test_target_id} = {{")
    pbx.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    pbx.append(f"\t\t\t\t\t\tTestTargetID = {app_target_id};")
    pbx.append("\t\t\t\t\t};")
    pbx.append("\t\t\t\t};")
    pbx.append("\t\t\t};")
    pbx.append(f"\t\t\tbuildConfigurationList = {proj_config_list_id} /* Build configuration list for PBXProject \"ForeverFit\" */;")
    pbx.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    pbx.append("\t\t\tdevelopmentRegion = en;")
    pbx.append("\t\t\thasScannedForEncodings = 0;")
    pbx.append("\t\t\tknownRegions = (")
    pbx.append("\t\t\t\ten,")
    pbx.append("\t\t\t\tBase,")
    pbx.append("\t\t\t);")
    pbx.append(f"\t\t\tmainGroup = {main_group_id};")
    pbx.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    pbx.append("\t\t\tprojectDirPath = \"\";")
    pbx.append("\t\t\tprojectRoot = \"\";")
    pbx.append("\t\t\ttargets = (")
    pbx.append(f"\t\t\t\t{app_target_id} /* ForeverFit */,")
    pbx.append(f"\t\t\t\t{test_target_id} /* ForeverFitTests */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t};")
    pbx.append("/* End PBXProject section */\n")

    # PBXResourcesBuildPhase
    pbx.append("/* Begin PBXResourcesBuildPhase section */")
    pbx.append(f"\t\t{app_resources_build_phase_id} /* Resources */ = {{")
    pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append(f"\t\t\t\t{assets_build_id} /* Assets.xcassets in Resources */,")
    for fname, fpath, f_id, b_id in resource_file_entries:
        pbx.append(f"\t\t\t\t{b_id} /* {fname} in Resources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_resources_build_phase_id} /* Resources */ = {{")
    pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXResourcesBuildPhase section */\n")

    # PBXSourcesBuildPhase
    pbx.append("/* Begin PBXSourcesBuildPhase section */")
    pbx.append(f"\t\t{app_sources_build_phase_id} /* Sources */ = {{")
    pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    for fname, fpath, f_id, b_id in app_file_entries:
        pbx.append(f"\t\t\t\t{b_id} /* {fname} in Sources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_sources_build_phase_id} /* Sources */ = {{")
    pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    for fname, fpath, f_id, b_id in test_file_entries:
        pbx.append(f"\t\t\t\t{b_id} /* {fname} in Sources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXSourcesBuildPhase section */\n")

    # PBXTargetDependency
    pbx.append("/* Begin PBXTargetDependency section */")
    pbx.append(f"\t\t{target_dep_id} /* PBXTargetDependency */ = {{")
    pbx.append("\t\t\tisa = PBXTargetDependency;")
    pbx.append(f"\t\t\ttarget = {app_target_id} /* ForeverFit */;")
    pbx.append(f"\t\t\ttargetProxy = {container_item_proxy_id} /* PBXContainerItemProxy */;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXTargetDependency section */\n")

    # XCBuildConfiguration
    pbx.append("/* Begin XCBuildConfiguration section */")
    pbx.append(f"\t\t{proj_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    pbx.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    pbx.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    pbx.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    pbx.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    pbx.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    pbx.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    pbx.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    pbx.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    pbx.append("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
    pbx.append("\t\t\t\t\t\"DEBUG=1\",")
    pbx.append("\t\t\t\t\t\"$(inherited)\",")
    pbx.append("\t\t\t\t);")
    pbx.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    pbx.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
    pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{proj_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    pbx.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    pbx.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    pbx.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    pbx.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    pbx.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    pbx.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    pbx.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    pbx.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{app_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
    pbx.append("\t\t\t\tENABLE_PREVIEWS = NO;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    pbx.append("\t\t\t\tINFOPLIST_FILE = ForeverFit/Info.plist;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;")
    pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    pbx.append("\t\t\t\t\t\"$(inherited)\",")
    pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    pbx.append("\t\t\t\t);")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.sih2026.foreverfit;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{app_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
    pbx.append("\t\t\t\tENABLE_PREVIEWS = NO;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    pbx.append("\t\t\t\tINFOPLIST_FILE = ForeverFit/Info.plist;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;")
    pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    pbx.append("\t\t\t\t\t\"$(inherited)\",")
    pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    pbx.append("\t\t\t\t);")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.sih2026.foreverfit;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.sih2026.foreverfit.ForeverFitTests;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
    pbx.append("\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/ForeverFit.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ForeverFit\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.sih2026.foreverfit.ForeverFitTests;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
    pbx.append("\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/ForeverFit.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ForeverFit\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")
    pbx.append("/* End XCBuildConfiguration section */\n")

    # XCConfigurationList
    pbx.append("/* Begin XCConfigurationList section */")
    pbx.append(f"\t\t{proj_config_list_id} /* Build configuration list for PBXProject \"ForeverFit\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{proj_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{proj_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{app_config_list_id} /* Build configuration list for PBXNativeTarget \"ForeverFit\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{app_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{app_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")

    pbx.append(f"\t\t{test_config_list_id} /* Build configuration list for PBXNativeTarget \"ForeverFitTests\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{test_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{test_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")
    pbx.append("/* End XCConfigurationList section */\n")

    pbx.append("\t};")
    pbx.append(f"\trootObject = {proj_id} /* Project object */;")
    pbx.append("}")

    xcodeproj_dir = os.path.join(root_dir, "ForeverFit.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    pbx_path = os.path.join(xcodeproj_dir, "project.pbxproj")
    with open(pbx_path, "w") as f:
        f.write("\n".join(pbx))
    print(f"Generated {pbx_path} with {len(app_files)} app files, {len(resource_files)} resource files, and {len(test_files)} test files.")

if __name__ == "__main__":
    main()
