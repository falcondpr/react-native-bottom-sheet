#!/usr/bin/env python3
"""Build/run the non-UI JNI test in the existing library instrumentation APK.

Reuse the example's SDK/CMake flags and production objects in a separate test
library. Only the JNI object is replaced by a fixture that includes that same
production translation unit. No production files or libraries are modified.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'android/build/publication-jni'
TEST_CLASS = 'com.swmansion.reactnativebottomsheet.accessibility.FabricPortalPublicationJniTest'
ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')


def run(command, *, cwd=ROOT, capture=False):
    return subprocess.check_output(command, cwd=cwd, text=True) if capture else subprocess.run(
        command, cwd=cwd, check=True)


def physical_device():
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        properties = ROOT / 'example/android/local.properties'
        match = re.search(r'^sdk.dir=(.+)$', properties.read_text(), re.MULTILINE)
        if not match:
            sys.exit('Set ANDROID_HOME or sdk.dir in example/android/local.properties.')
        sdk = match[1]
    adb = Path(sdk) / 'platform-tools/adb'
    devices = [line.split()[0] for line in run([str(adb), 'devices'], capture=True).splitlines()
               if len(line.split()) >= 2 and line.split()[1] == 'device'
               and not line.startswith('emulator-')]
    selected = os.environ.get('ANDROID_SERIAL')
    if selected:
        if selected not in devices:
            sys.exit('ANDROID_SERIAL must select an authorized physical Android device.')
    elif len(devices) == 1:
        selected = devices[0]
    else:
        sys.exit('Connect one authorized physical Android, or select it with ANDROID_SERIAL.')
    os.environ['ANDROID_SERIAL'] = selected


def build_native(abi):
    databases = sorted((ROOT / 'example/android/app/.cxx/Debug').glob(
        f'*/{abi}/compile_commands.json'), key=lambda path: path.stat().st_mtime, reverse=True)
    item = None
    for database in databases:
        item = next((entry for entry in json.loads(database.read_text())
                     if entry['file'].endswith('/PortalPublicationSourceAndroid.cpp')), None)
        if item:
            break
    if not item:
        sys.exit(f'Missing production CMake compilation database for {abi}.')
    directory = Path(item['directory'])
    command = shlex.split(item['command'])
    original_object = command[command.index('-o') + 1]
    object_file = OUTPUT / 'objects' / f'{abi}.o'
    object_file.parent.mkdir(parents=True, exist_ok=True)
    command[command.index('-o') + 1] = str(object_file)
    command[command.index('-c') + 1] = str(ROOT / 'tests/android-native/FabricPublicationJniFixture.cpp')
    run(command, cwd=directory)

    cache = (directory / 'CMakeCache.txt').read_text()
    ninja = re.search(r'^CMAKE_MAKE_PROGRAM:[^=]+=(.+)$', cache, re.MULTILINE)[1]
    target = re.search(r'^build (.+): CXX_SHARED_LIBRARY_LINKER__react_codegen_ReactNativeBottomSheetSpec_',
                       (directory / 'build.ninja').read_text(), re.MULTILINE)[1]
    link = shlex.split(run([ninja, '-t', 'commands', target], cwd=directory, capture=True).splitlines()[-1])
    # CMake wraps its actual linker invocation in two shell no-ops.
    if link[:2] == [':', '&&']:
        link = link[2:]
    if link[-2:] == ['&&', ':']:
        link = link[:-2]
    if any(token in ('&&', ';', '|') for token in link):
        sys.exit('Unsupported CMake linker command; refusing to execute shell syntax.')
    if original_object not in link:
        sys.exit('JNI production object not found in the actual CMake link command.')
    link[link.index(original_object)] = str(object_file)
    library = OUTPUT / 'libs' / abi / 'libbottomsheet_publication_jni_test.so'
    library.parent.mkdir(parents=True, exist_ok=True)
    link[link.index('-o') + 1] = str(library)
    link = [token.replace('-Wl,-soname,libreact_codegen_ReactNativeBottomSheetSpec.so',
                          '-Wl,-soname,libbottomsheet_publication_jni_test.so') for token in link]
    run(link, cwd=directory)
    print(f'JNI fixture built: {abi}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assemble', action='store_true', help='Build only; no device is needed.')
    args = parser.parse_args()
    if not args.assemble:
        physical_device()
    gradle = [str(ROOT / 'example/android/gradlew'), '--project-dir', str(ROOT / 'example/android'),
              '--no-daemon', '--console=plain', '-PreactNativeArchitectures=' + ','.join(ABIS)]
    run(gradle + [':app:assembleDebug'])
    for abi in ABIS:
        build_native(abi)
    task = 'assembleDebugAndroidTest' if args.assemble else 'connectedDebugAndroidTest'
    started = time.time()
    run(gradle + ['--init-script', str(ROOT / 'tests/android-native/publication-jni.gradle'),
                 '-Pandroid.testInstrumentationRunnerArguments.class=' + TEST_CLASS,
                 '-Pandroid.testInstrumentationRunnerArguments.bottomSheetPublicationJni=true',
                 ':swmansion_react-native-bottom-sheet:' + task])
    if not args.assemble:
        cases = []
        for report in (ROOT / 'android/build/outputs/androidTest-results/connected/debug').rglob('TEST-*.xml'):
            if report.stat().st_mtime >= started:
                cases.extend(ET.parse(report).getroot().iter('testcase'))
        if len(cases) != 2 or any(case.get('classname') != TEST_CLASS or
                                 any(case.find(tag) is not None for tag in ('skipped', 'failure', 'error'))
                                 for case in cases):
            sys.exit('Expected exactly two freshly executed JNI tests without skips/failures; inspect the report.')
    print('JNI test APK assembled; Android runtime is pending.' if args.assemble else
          'JNI instrumentation finished; see android/build/reports/androidTests/connected/debug.')


if __name__ == '__main__':
    main()
