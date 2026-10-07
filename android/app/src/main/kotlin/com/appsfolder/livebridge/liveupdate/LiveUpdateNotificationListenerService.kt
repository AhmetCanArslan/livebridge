package com.appsfolder.livebridge.liveupdate

import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.appsfolder.livebridge.liveupdate.networkspeed.NetworkSpeedController
import kotlin.math.min

class LiveUpdateNotificationListenerService : NotificationListenerService() {
    private val prefs by lazy { ConverterPrefs(applicationContext) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processingHandler = NotificationProcessing.handler
    private val refreshPolicy = SnapshotRefreshPolicy()
    private var lastSettings: Map<String, *>? = null
    private var lastInterruptionFilter: Int? = null
    @Volatile
    private var destroyed = false
    private val selfDismissLock = Any()
    private val selfDismissedSourceKeys = mutableSetOf<String>()
    private var rebindAttempts = 0
    private var rebindScheduled = false
    private var snapshotSyncScheduled = false
    @Volatile
    private var listenerConnected = false

    private val rebindRunnable = object : Runnable {
        override fun run() {
            rebindScheduled = false
            if (listenerConnected || !isListenerEnabled(applicationContext)) {
                return
            }
            requestRebindIfEnabled(applicationContext, "listener_disconnected")
            rebindAttempts++
            scheduleRebind("retry")
        }
    }

    private val snapshotSyncRunnable = object : Runnable {
        override fun run() {
            snapshotSyncScheduled = false
            if (!listenerConnected) {
                return
            }
            processingHandler.post {
                if (destroyed || !listenerConnected) return@post
                try {
                    val settings = prefs.runtimeSettingsSnapshot()
                    val filter = (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .currentInterruptionFilter
                    if (settings != lastSettings || filter != lastInterruptionFilter) {
                        refreshPolicy.invalidate()
                        lastSettings = settings
                        lastInterruptionFilter = filter
                    }
                    if (!prefs.getConverterEnabled()) {
                        refreshPolicy.invalidate()
                        mainHandler.post { if (!destroyed) scheduleSnapshotSync() }
                        return@post
                    }
                    val snapshots = activeNotifications?.toList().orEmpty()
                    refreshPolicy.retain(snapshots.mapTo(mutableSetOf()) { it.key })
                    for (sbn in snapshots) {
                        if (sbn.packageName == packageName) continue
                        if (!refreshPolicy.needsRefresh(
                                sbn.key, sbn.postTime, SystemClock.elapsedRealtime(),
                                LiveUpdateNotifier.needsPeriodicRefresh(sbn.notification)
                            )) continue
                        processSafely(sbn)
                    }
                } catch (error: Throwable) {
                    Log.w(TAG, "Snapshot sync failed", error)
                    listenerConnected = false
                    mainHandler.post { scheduleRebind("snapshot_sync_failed") }
                }
                mainHandler.post { if (!destroyed) scheduleSnapshotSync() }
            }
            return
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this

        if (!prefs.getConverterEnabled()) {
            LiveUpdateNotifier.clearRuntimeState()
            NotificationManagerCompat.from(applicationContext).cancelAll()
        }

        LiveUpdateNotifier.ensureChannel(applicationContext)
        NetworkSpeedController.sync(applicationContext, prefs)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        listenerConnected = true
        mainHandler.removeCallbacks(rebindRunnable)
        rebindAttempts = 0
        rebindScheduled = false
        KeepAliveForegroundService.sync(applicationContext, prefs)
        NetworkSpeedController.sync(applicationContext, prefs)
        scheduleSnapshotSync()

        if (!prefs.getConverterEnabled()) {
            LiveUpdateNotifier.clearRuntimeState()
            NotificationManagerCompat.from(applicationContext).cancelAll()
            scheduleSnapshotSync()
            return
        }

        processingHandler.post {
            if (destroyed || !listenerConnected) return@post
            refreshPolicy.invalidate()
            val snapshots = try {
                activeNotifications?.toList().orEmpty()
            } catch (error: Throwable) {
                Log.w(TAG, "Unable to read active notifications on connect", error)
                emptyList()
            }
            for (sbn in snapshots) {
                if (sbn.packageName != packageName) processSafely(sbn)
            }
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        listenerConnected = false
        mainHandler.removeCallbacks(snapshotSyncRunnable)
        snapshotSyncScheduled = false
        scheduleRebind("listener_disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName == packageName) {
            return
        }
        processingHandler.post {
            if (!destroyed) processSafely(sbn)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        processingHandler.post {
            if (destroyed) return@post
            if (sbn.packageName == packageName) {
                LiveUpdateNotifier.handleMirroredRemoved(applicationContext, sbn)
                return@post
            }
            if (consumeSelfDismissedSourceKey(sbn.key)) return@post
            refreshPolicy.remove(sbn.key)
            try {
                LiveUpdateNotifier.cancelMirrored(applicationContext, sbn)
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to process removed notification: ${sbn.key}", error)
            }
        }
    }

    override fun onDestroy() {
        destroyed = true
        listenerConnected = false
        mainHandler.removeCallbacksAndMessages(null)
        rebindScheduled = false
        snapshotSyncScheduled = false
        if (activeInstance === this) {
            activeInstance = null
        }
        super.onDestroy()
    }

    private fun isSourceNotificationActive(key: String): Boolean? {
        return try {
            activeNotifications?.any { it.key == key } ?: false
        } catch (_: Throwable) {
            null
        }
    }

    private fun processSafely(sbn: StatusBarNotification) {
        try {
            if (processIncomingNotification(sbn)) {
                refreshPolicy.record(sbn.key, sbn.postTime, SystemClock.elapsedRealtime())
            } else {
                refreshPolicy.remove(sbn.key)
            }
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to process notification: ${sbn.key}", error)
        }
    }

    private fun processIncomingNotification(sbn: StatusBarNotification): Boolean {
        val result = LiveUpdateNotifier.maybeMirror(applicationContext, prefs, sbn)
        if (!prefs.getConverterEnabled()) return false
        if (result.mirrored) {
            ConversionLogStore.upsertMirroredNotification(
                context = applicationContext,
                prefs = prefs,
                sbn = sbn,
                title = extractLogTitle(sbn),
                text = extractLogText(sbn.notification)
            )
        }
        maybeDismissOriginalSource(sbn, result)
        return !result.retryNeeded
    }

    private fun extractLogTitle(sbn: StatusBarNotification): String {
        val extras = sbn.notification.extras
        return extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
            ?: AppMetadataCache.get(applicationContext, sbn.packageName).label
    }

    private fun extractLogText(notification: android.app.Notification): String {
        val extras = notification.extras
        return extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.mapNotNull { it?.toString()?.trim()?.takeIf(String::isNotEmpty) }
                ?.joinToString("\n")
                .orEmpty()
    }

    private fun maybeDismissOriginalSource(
        sbn: StatusBarNotification,
        result: LiveUpdateNotifier.MirrorResult
    ) {
        if (!result.mirrored) {
            return
        }
        if (!sbn.isClearable) {
            return
        }
        val appPresentationRemoveOriginal = AppPresentationOverridesLoader
            .get(prefs)
            .resolve(sbn.packageName.lowercase())
            .removeOriginalMessage
        val shouldDismiss = appPresentationRemoveOriginal || when (result.dedupKind) {
            LiveUpdateNotifier.MirrorDedupKind.OTP -> {
                prefs.getOtpRemoveOriginalMessageEnabled() &&
                    prefs.isOtpPackageAllowed(sbn.packageName)
            }
            LiveUpdateNotifier.MirrorDedupKind.STATUS -> {
                prefs.getSmartRemoveOriginalMessageEnabled() &&
                    prefs.isSmartPackageAllowed(sbn.packageName)
            }
            else -> false
        }
        if (!shouldDismiss) {
            return
        }

        rememberSelfDismissedSourceKey(sbn.key)
        try {
            cancelNotification(sbn.key)
        } catch (error: Throwable) {
            forgetSelfDismissedSourceKey(sbn.key)
            Log.e(TAG, "Failed to auto-dismiss original notification: ${sbn.key}", error)
        }
    }

    private fun rememberSelfDismissedSourceKey(sbnKey: String) {
        synchronized(selfDismissLock) {
            selfDismissedSourceKeys.add(sbnKey)
        }
    }

    private fun forgetSelfDismissedSourceKey(sbnKey: String) {
        synchronized(selfDismissLock) {
            selfDismissedSourceKeys.remove(sbnKey)
        }
    }

    private fun consumeSelfDismissedSourceKey(sbnKey: String): Boolean {
        return synchronized(selfDismissLock) {
            selfDismissedSourceKeys.remove(sbnKey)
        }
    }

    private fun scheduleRebind(reason: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return
        }
        if (listenerConnected || rebindScheduled || !isListenerEnabled(applicationContext)) {
            return
        }
        if (rebindAttempts >= MAX_REBIND_ATTEMPTS) {
            Log.w(TAG, "Listener rebind attempts exhausted ($reason)")
            return
        }

        val delayMs = min(MAX_REBIND_DELAY_MS, INITIAL_REBIND_DELAY_MS shl rebindAttempts)
        rebindScheduled = true
        mainHandler.postDelayed(rebindRunnable, delayMs)
    }

    private fun scheduleSnapshotSync() {
        if (!listenerConnected || snapshotSyncScheduled) {
            return
        }
        snapshotSyncScheduled = true
        mainHandler.postDelayed(snapshotSyncRunnable, SNAPSHOT_SYNC_INTERVAL_MS)
    }

    companion object {
        @Volatile
        private var activeInstance: LiveUpdateNotificationListenerService? = null

        fun isConnected(): Boolean = activeInstance?.listenerConnected == true

        internal fun invalidateSnapshotCache() {
            val listener = activeInstance ?: return
            listener.processingHandler.post { listener.refreshPolicy.invalidate() }
        }

        fun isSourceNotificationActive(key: String): Boolean? {
            val listener = activeInstance ?: return null
            return if (listener.listenerConnected) listener.isSourceNotificationActive(key) else null
        }
        private const val TAG = "LiveUpdateListener"
        private const val INITIAL_REBIND_DELAY_MS = 1_000L
        private const val MAX_REBIND_DELAY_MS = 30_000L
        private const val MAX_REBIND_ATTEMPTS = 6
        private const val SNAPSHOT_SYNC_INTERVAL_MS = 4_000L

        fun requestRebindIfEnabled(context: Context, reason: String): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                return false
            }
            if (!isListenerEnabled(context)) {
                Log.w(TAG, "Skip rebind ($reason): listener disabled")
                return false
            }

            return try {
                requestRebind(ComponentName(context, LiveUpdateNotificationListenerService::class.java))
                Log.i(TAG, "Requested listener rebind ($reason)")
                true
            } catch (error: Throwable) {
                Log.e(TAG, "Failed listener rebind ($reason)", error)
                false
            }
        }

        fun isListenerEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val service = ComponentName(context, LiveUpdateNotificationListenerService::class.java)
            return enabled.split(":")
                .mapNotNull(ComponentName::unflattenFromString)
                .any { it == service }
        }
    }
}
