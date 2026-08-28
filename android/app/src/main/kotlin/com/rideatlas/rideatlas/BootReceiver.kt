package com.rideatlas.rideatlas

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * When daily mode is enabled, relaunch [MainActivity] after boot / package
 * replace so Dart can silently resume or start today's recording without
 * the rider having to tap the icon (battery death → charge → power on).
 *
 * The enabled flag is mirrored from Flutter into SharedPreferences (see
 * MainActivity's daily_mode channel) because Hive isn't readable here.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_FROM_BOOT, true)
        }
        // On Android 10+ BOOT_COMPLETED is an allowed background-activity
        // start reason; still catch OEM blocks so we never crash the
        // receiver process.
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
            // Rider can still open the app manually; daily mode kicks in then.
        }
    }

    companion object {
        const val PREFS_NAME = "rideatlas_daily_mode"
        const val KEY_ENABLED = "enabled"
        const val EXTRA_FROM_BOOT = "rideatlas_from_boot"
    }
}
