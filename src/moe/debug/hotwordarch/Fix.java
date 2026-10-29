package moe.debug.hotwordarch;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * OnePlus 15R / OxygenOS 16 workaround for the Google app's screen-off hotword.
 *
 * The Qualcomm SoundTrigger HAL reports an empty supportedModelArch. GSA checks
 * that field against a whitelist of DSP platform ids and disables DSP hotword
 * when the value is missing. Faking a whitelisted value in the Google app is
 * not sufficient: system_server re-lists modules and compares ModuleProperties
 * objects with equals(), and the OEM build's client/server lists do not compare
 * equal. This module also replaces the argument passed to
 * SoundTriggerService.newSoundTriggerHelper() with the server's own object.
 *
 * Scope: com.google.android.googlequicksearchbox and system_server.
 * Tested on: CPH2769, OxygenOS 16.0.5.701(EX01), Google app 17.68.28.ve.arm64.
 */
public final class Fix implements IXposedHookLoadPackage {
    private static final String TAG = "[HotwordArchFix] ";
    private static final String TARGET_PKG = "com.google.android.googlequicksearchbox";
    private static final String FAKE_ARCH = "259,0e01b779-79f1-3b55-ab94-1feb46ad70ef";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lp) {
        if ("android".equals(lp.packageName) || "system".equals(lp.packageName)) {
            hookSystemServer(lp.classLoader);
            return;
        }
        if (!TARGET_PKG.equals(lp.packageName)) {
            return;
        }
        hookGoogleApp();
    }

    private static void hookGoogleApp() {
        try {
            Class<?> mp = XposedHelpers.findClass(
                    "android.hardware.soundtrigger.SoundTrigger$ModuleProperties", null);
            XposedBridge.hookAllMethods(mp, "getSupportedModelArch", new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    Object real = param.getResult();
                    // Leave the AOSP fake-HAL module ("injection") untouched so
                    // SoundTriggerManager keeps filtering it out.
                    if (real == null || ((String) real).isEmpty()) {
                        param.setResult(FAKE_ARCH);
                    }
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + "arch hook failed: " + t);
        }

        // Keep the client Identity consistent before list/attach calls.
        try {
            Class<?> proxy = XposedHelpers.findClass(
                    "com.android.internal.app.ISoundTriggerService$Stub$Proxy", null);
            XC_MethodHook identityHook = new XC_MethodHook() {
                @Override
                protected void beforeHookedMethod(MethodHookParam param) {
                    if (param.args.length > 0) {
                        fixIdentity(param.args[0]);
                    }
                }
            };
            XposedBridge.hookAllMethods(proxy, "attachAsOriginator", identityHook);
            XposedBridge.hookAllMethods(proxy, "listModuleProperties", identityHook);
        } catch (Throwable t) {
            XposedBridge.log(TAG + "identity hooks failed: " + t);
        }
    }

    private static void hookSystemServer(ClassLoader cl) {
        try {
            Class<?> svc;
            try {
                svc = XposedHelpers.findClass(
                        "com.android.server.soundtrigger.SoundTriggerService", cl);
            } catch (Throwable t) {
                svc = XposedHelpers.findClass(
                        "com.android.server.soundtrigger.SoundTriggerService", null);
            }
            XposedBridge.hookAllMethods(svc, "newSoundTriggerHelper", new XC_MethodHook() {
                @Override
                protected void beforeHookedMethod(MethodHookParam param) {
                    try {
                        if (param.args.length < 1 || param.args[0] == null) {
                            return;
                        }
                        Object props = param.args[0];
                        if (!props.getClass().getName().contains("ModuleProperties")) {
                            return;
                        }
                        int id = (Integer) XposedHelpers.callMethod(props, "getId");
                        Class<?> ic = XposedHelpers.findClass(
                                "android.media.permission.IdentityContext", null);
                        Object identity = XposedHelpers.callStaticMethod(ic, "getNonNull");
                        Object list = XposedHelpers.callMethod(param.thisObject,
                                "listUnderlyingModuleProperties", identity);
                        if (!(list instanceof java.util.List)) {
                            return;
                        }
                        for (Object candidate : (java.util.List<?>) list) {
                            int candidateId = (Integer) XposedHelpers.callMethod(
                                    candidate, "getId");
                            if (candidateId == id) {
                                param.args[0] = candidate;
                                break;
                            }
                        }
                    } catch (Throwable t) {
                        XposedBridge.log(TAG + "system hook err: " + t);
                    }
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + "system_server hook failed: " + t);
        }
    }

    private static void fixIdentity(Object identity) {
        if (identity == null) {
            return;
        }
        try {
            XposedHelpers.setIntField(identity, "uid", android.os.Process.myUid());
            XposedHelpers.setIntField(identity, "pid", android.os.Process.myPid());
        } catch (Throwable t) {
            XposedBridge.log(TAG + "fixIdentity failed: " + t);
        }
    }
}
