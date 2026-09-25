#!/usr/bin/env python3
"""Generate the Xcode project using stable identifiers and pinned packages."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    key = ident(name)
    objects[key] = body
    return key
def quoted(s): return '"' + s.replace('"', '\\"') + '"'
def array(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
def settings(items): return '{ ' + ' '.join(f'{k} = {v};' for k,v in items.items()) + ' }'

def target(name, folder, product_type, extension):
    sources, children = [], []
    for path in sorted((ROOT/folder).rglob('*.swift')):
        relative = str(path.relative_to(ROOT))
        ref = add(relative, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT; }}')
        children.append(ref)
        sources.append(add(relative+'-build', f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))
    group = add(name+'-group', f'{{isa = PBXGroup; children = {array(children)}; name = {quoted(name)}; sourceTree = "<group>"; }}')
    product = add(name+'-product', f'{{isa = PBXFileReference; explicitFileType = {"wrapper.application" if extension == "app" else "wrapper.cfbundle"}; path = {name}.{extension}; sourceTree = BUILT_PRODUCTS_DIR; }}')
    phase = add(name+'-sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0; }}')
    resource_items = []
    if name == 'Heimdall':
        for file, typ in [('Sweden','folder'), ('Maps','folder'), ('PrivacyInfo.xcprivacy','text.xml'), ('Assets.xcassets','folder.assetcatalog')]:
            ref = add(file, f'{{isa = PBXFileReference; lastKnownFileType = {typ}; path = Heimdall/Resources/{file}; sourceTree = SOURCE_ROOT; }}')
            children.append(ref)
            resource_items.append(add(file+'-build', f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))
        objects[group] = f'{{isa = PBXGroup; children = {array(children)}; name = Heimdall; sourceTree = "<group>"; }}'
    if name == 'HeimdallTests':
        ref = add('test-fixtures', '{isa = PBXFileReference; lastKnownFileType = folder; path = HeimdallTests/Fixtures; sourceTree = SOURCE_ROOT; }')
        resource_items.append(add('test-fixtures-build', f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))
    resources = add(name+'-resources', f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_items)}; runOnlyForDeploymentPostprocessing = 0; }}')
    products = []
    framework_items = []
    if name == 'Heimdall':
        for product_name, repo, version in [('MapLibre', 'maplibre/maplibre-native-distribution', '6.31.0'), ('ZIPFoundation', 'weichsel/ZIPFoundation', '0.9.20')]:
            package = add(product_name+'-package', f'{{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/{repo}.git"; requirement = {{kind = exactVersion; version = {version}; }}; }}')
            dependency = add(product_name+'-dependency', f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = {product_name}; }}')
            products.append(dependency)
            framework_items.append(add(product_name+'-framework-build', f'{{isa = PBXBuildFile; productRef = {dependency}; }}'))
    frameworks = add(name+'-frameworks', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array(framework_items)}; runOnlyForDeploymentPostprocessing = 0; }}')
    configs = []
    for config in ['Debug','Release']:
        values = {'PRODUCT_NAME':'"$(TARGET_NAME)"', 'PRODUCT_BUNDLE_IDENTIFIER':f'com.heimdall.local.{name.lower()}',
                  'SWIFT_VERSION':'6.0', 'IPHONEOS_DEPLOYMENT_TARGET':'27.0', 'TARGETED_DEVICE_FAMILY':'1',
                  'SDKROOT':'iphoneos', 'SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"',
                  'CODE_SIGN_STYLE':'Automatic', 'SWIFT_STRICT_CONCURRENCY':'complete',
                  'ONLY_ACTIVE_ARCH':'YES' if config == 'Debug' else 'NO',
                  'SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if config == 'Debug' else '"-O"',
                  'DEBUG_INFORMATION_FORMAT':'dwarf' if config == 'Debug' else '"dwarf-with-dsym"',
                  'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config == 'Debug' else '""',
                  'ENABLE_TESTABILITY':'YES' if config == 'Debug' else 'NO',
                  'GENERATE_INFOPLIST_FILE':'YES' if name != 'Heimdall' else 'NO',
                  'LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"'}
        if name == 'Heimdall':
            values.update({'INFOPLIST_FILE':'Heimdall/Resources/Info.plist',
                           'CODE_SIGN_ENTITLEMENTS':'Heimdall/Resources/Heimdall.entitlements',
                           'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
                           'ENABLE_APP_SANDBOX':'YES'})
        elif name == 'HeimdallTests':
            values.update({'TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/Heimdall.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Heimdall"', 'BUNDLE_LOADER':'"$(TEST_HOST)"'})
        else: values['TEST_TARGET_NAME'] = 'Heimdall'
        configs.append(add(name+config, f'{{isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {config}; }}'))
    configlist = add(name+'-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
    dependencies = []
    if name != 'Heimdall':
        proxy = add(name+'-proxy', f'{{isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("Heimdall-target")}; remoteInfo = Heimdall; }}')
        dependencies = [add(name+'-dependency', f'{{isa = PBXTargetDependency; target = {ident("Heimdall-target")}; targetProxy = {proxy}; }}')]
    phases = [phase, frameworks, resources]
    if name == 'Heimdall':
        check = add('map-check', r'{isa = PBXShellScriptBuildPhase; name = "Check offline maps"; buildActionMask = 2147483647; files = (); inputPaths = ("$(SRCROOT)/Scripts/check_maps.sh", "$(SRCROOT)/Heimdall/Resources/Maps"); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "sh \"$SRCROOT/Scripts/check_maps.sh\""; alwaysOutOfDate = 1; }')
        phases.insert(0, check)
    targetid = add(name+'-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; packageProductDependencies = {array(products)}; name = {name}; productName = {name}; productReference = {product}; productType = {quoted(product_type)}; }}')
    return targetid, group, product

targets = [target('Heimdall','Heimdall','com.apple.product-type.application','app'),
           target('HeimdallTests','HeimdallTests','com.apple.product-type.bundle.unit-test','xctest'),
           target('HeimdallUITests','HeimdallUITests','com.apple.product-type.bundle.ui-testing','xctest')]
products = add('products', f'{{isa = PBXGroup; children = {array([t[2] for t in targets])}; name = Products; sourceTree = "<group>"; }}')
main = add('main', f'{{isa = PBXGroup; children = {array([t[1] for t in targets]+[products])}; sourceTree = "<group>"; }}')
configs = []
for config in ['Debug','Release']:
    values = {'CLANG_ENABLE_MODULES':'YES', 'CLANG_ENABLE_OBJC_ARC':'YES', 'ENABLE_USER_SCRIPT_SANDBOXING':'YES',
              'SWIFT_COMPILATION_MODE':'singlefile' if config == 'Debug' else 'wholemodule'}
    configs.append(add('project'+config, f'{{isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {config}; }}'))
configlist = add('project-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
add('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }}; buildConfigurationList = {configlist}; compatibilityVersion = "Xcode 14.0"; packageReferences = ({ident("MapLibre-package")}, {ident("ZIPFoundation-package")}); developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, sv, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([t[0] for t in targets])}; }}')
project = ROOT/'Heimdall.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{k} = {v};' for k,v in objects.items()) + f'\n}}; rootObject = {ident("project")}; }}\n')
scheme = project/'xcshareddata/xcschemes'
scheme.mkdir(parents=True,exist_ok=True)
def reference(name, ext):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name+"-target")}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:Heimdall.xcodeproj"/>'
(scheme/'Heimdall.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('Heimdall','app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO"><CommandLineArguments><CommandLineArgument argument="--ui-testing" isEnabled="YES"/><CommandLineArgument argument="--isolated-ui-tests" isEnabled="YES"/></CommandLineArguments><Testables>
<TestableReference skipped="NO">{reference('HeimdallTests','xctest')}</TestableReference>
<TestableReference skipped="NO">{reference('HeimdallUITests','xctest')}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Heimdall','app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Heimdall','app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Heimdall.xcodeproj')
