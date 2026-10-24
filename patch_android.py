import os
import re

# ---------------- AndroidManifest.xml ----------------
p = 'app/android/app/src/main/AndroidManifest.xml'
s = open(p).read()

perms = '''<uses-permission android:name="android.permission.READ_CONTACTS"/>
    <uses-permission android:name="android.permission.WRITE_CONTACTS"/>
    <uses-permission android:name="android.permission.READ_CALL_LOG"/>
    <uses-permission android:name="android.permission.CALL_PHONE"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    '''

dial_filters = '''<intent-filter>
                <action android:name="android.intent.action.DIAL"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.DIAL"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:scheme="tel"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="tel"/>
            </intent-filter>
        '''

components = '''
        <activity
            android:name=".InCallActivity"
            android:exported="false"
            android:launchMode="singleTask"
            android:excludeFromRecents="true"
            android:showWhenLocked="true"
            android:turnScreenOn="true"
            android:taskAffinity=""
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"/>
        <service
            android:name=".CallService"
            android:exported="true"
            android:permission="android.permission.BIND_INCALL_SERVICE">
            <meta-data android:name="android.telecom.IN_CALL_SERVICE_UI" android:value="true"/>
            <meta-data android:name="android.telecom.IN_CALL_SERVICE_RINGING" android:value="false"/>
            <intent-filter>
                <action android:name="android.telecom.InCallService"/>
            </intent-filter>
        </service>'''

queries = '''<queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="sms"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="mailto"/></intent>'''

assert '<application' in s and '</activity>' in s and '<queries>' in s
s = s.replace('<application', perms + '<application', 1)
s = s.replace('</activity>', dial_filters + '</activity>' + components, 1)
s = s.replace('<queries>', queries, 1)
s = s.replace('android:label="contacts_dialer"', 'android:label="Phone"')
open(p, 'w').write(s)

# ---------------- Launcher icon (original Xiaomi phone icon) ----------------
if os.path.exists('icon.png'):
    from PIL import Image
    im = Image.open('icon.png').convert('RGBA')
    for dens, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        out = 'app/android/app/src/main/res/mipmap-' + dens
        os.makedirs(out, exist_ok=True)
        im.resize((px, px), Image.LANCZOS).save(out + '/ic_launcher.png')
    print('launcher icon written')

# ---------------- Gradle ----------------
d = 'app/android/app'
kts, gr = d + '/build.gradle.kts', d + '/build.gradle'
if os.path.exists(kts):
    g = open(kts).read()
    assert 'compileOptions {' in g
    g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', g)
    g = re.sub(r'^android \{', 'android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }', g, count=1, flags=re.M)
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, 'w').write(g)
else:
    g = open(gr).read()
    assert 'compileOptions {' in g
    g = g.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    g = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdkVersion 24', g)
    g = re.sub(r'^android \{', 'android {\n    lint {\n        checkReleaseBuilds false\n        abortOnError false\n    }', g, count=1, flags=re.M)
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(gr, 'w').write(g)

print('manifest and gradle patched')
