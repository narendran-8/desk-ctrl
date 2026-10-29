#!/usr/bin/env python3
"""Test the production Android PCM writer and phone-volume lease with cached Kotlin on the JVM."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
modules = ['org.jetbrains.kotlin/kotlin-compiler-embeddable', 'org.jetbrains.kotlin/kotlin-stdlib',
           'org.jetbrains.kotlin/kotlin-reflect', 'org.jetbrains.kotlin/kotlin-script-runtime', 'org.jetbrains.kotlin/kotlin-daemon-embeddable',
           'org.jetbrains.intellij.deps/trove4j', 'org.jetbrains/annotations',
           'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm']
jars = []
for module in modules:
    versions = sorted((cache / module).glob('*'), key=lambda p: [int(x) if x.isdigit() else 0 for x in p.name.split('.')])
    if versions:
        jars.extend(versions[-1].glob('*/*.jar'))
cp = os.pathsep.join(map(str, jars))
with tempfile.TemporaryDirectory(prefix='vil-pcm-test-') as dest:
    subprocess.run(['java', '-cp', cp, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect',
                    '-classpath', cp, '-d', dest,
                    str(root / 'mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PcmPump.kt'),
                    str(root / 'mobile/android/app/src/main/kotlin/com/deskctrl/deskctrl/PhoneVolumeLease.kt'),
                    str(root / 'tools/audio/PhoneVolumeLeaseTest.kt'),
                    str(root / 'tools/audio/PcmPumpTest.kt')], check=True)
    subprocess.run(['java', '-cp', dest + os.pathsep + cp, 'com.deskctrl.deskctrl.PcmPumpTestKt'], check=True)
