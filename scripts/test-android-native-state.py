#!/usr/bin/env python3
"""Run Android C++ state data tests on a Mac host using existing example Pods.

No Android device, simulator or application is launched. The ANDROID branch
of the data header is tested; Android ABI compilation is a separate check.
"""
from pathlib import Path
import hashlib
import json
import platform
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'android/build/native-state-host'
output.mkdir(parents=True, exist_ok=True)
pods = root / 'example/ios/Pods'
react = pods / 'React-Core-prebuilt/React.xcframework/ios-arm64_x86_64-maccatalyst'
deps = pods / 'ReactNativeDependencies/framework/packages/react-native/ReactNativeDependencies.xcframework/ios-arm64_x86_64-maccatalyst'
hermes = pods / 'hermes-engine/destroot/Library/Frameworks/universal/hermesvm.xcframework/ios-arm64_x86_64-maccatalyst'
if not (react / 'React.framework').exists():
    sys.exit('Missing Mac Catalyst RN dependencies: install the example iOS Pods before running this host test.')
sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
rn = root / 'node_modules/react-native/ReactCommon'
source = root / 'tests/android-native/BottomSheetViewStateTests.cpp'
header = root / 'common/cpp/react/renderer/components/ReactNativeBottomSheetSpec/BottomSheetViewState.h'
pins = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (source, header, Path(__file__).resolve())}
command = ['xcrun', 'clang++', '-std=c++20', '-DANDROID', '-target', platform.machine() + '-apple-ios17.0-macabi',
           '-isysroot', str(sdk), '-F', str(sdk / 'System/iOSSupport/System/Library/Frameworks'),
           '-DREACT_NATIVE_TARGET_PLATFORM_IOS=1', '-DFOLLY_MOBILE=1',
           '-DFOLLY_USE_LIBCPP=1', '-DFOLLY_CFG_NO_COROUTINES=1']
for path in [root / 'common/cpp', rn, rn / 'yoga', rn / 'jsi',
             pods / 'ReactNativeDependencies/Headers', pods / 'hermes-engine/destroot/include',
             rn / 'react/renderer/components/view/platform/cxx'] + list(rn.rglob('platform/ios')):
    command += ['-I', str(path)]
for path in [react, deps, hermes]:
    command += ['-F', str(path), '-Wl,-rpath,' + str(path)]
binary = output / 'BottomSheetStateTests'
command += [str(source), '-framework', 'React', '-framework', 'ReactNativeDependencies',
            '-framework', 'hermesvm', '-framework', 'Foundation', '-framework', 'UIKit',
            '-o', str(binary)]
compiled = subprocess.run(command, text=True, capture_output=True)
(output / 'compile.log').write_text(compiled.stdout + compiled.stderr)
result = {'compile_exit': compiled.returncode, 'source_sha256': pins, 'UI_launches': 0,
          'host_data_test': True, 'Android_runtime': False}
if compiled.returncode == 0:
    tested = subprocess.run([str(binary)], text=True, capture_output=True, timeout=20)
    log = tested.stdout + tested.stderr
    (output / 'test.log').write_text(log)
    match = re.search(r'STATE RESULT tests=(\d+) failures=(\d+)', log)
    result.update(test_exit=tested.returncode, tests=int(match[1]) if match else None,
                  failures=int(match[2]) if match else None)
    print(log)
else:
    print(compiled.stderr[-3000:])
for path, expected in pins.items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == expected, path
    (output / Path(path).name).write_bytes((root / path).read_bytes())
(output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
sys.exit(result.get('test_exit', compiled.returncode))
