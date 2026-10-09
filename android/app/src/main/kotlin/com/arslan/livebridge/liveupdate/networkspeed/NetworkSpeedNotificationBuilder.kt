package com.arslan.livebridge.liveupdate.networkspeed

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.arslan.livebridge.MainActivity
import com.arslan.livebridge.R
import com.arslan.livebridge.liveupdate.ConverterPrefs
import com.arslan.livebridge.liveupdate.WearOsLiveUpdatesPolicy
import com.arslan.livebridge.liveupdate.NativeAppStrings

class NetworkSpeedNotificationBuilder(
    private val context: Context
) {
    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val text = localizedText()
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            val shouldUpdate =
                existing.name?.toString() != text.channelName ||
                    existing.description != text.channelDescription
            if (!shouldUpdate) {
                return
            }

            existing.name = text.channelName
            existing.description = text.channelDescription
            manager.createNotificationChannel(existing)
            return
        }

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                text.channelName,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = text.channelDescription
                setShowBadge(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
        )
    }

    fun build(
        sample: NetworkSpeedSample,
        minPromotedBytesPerSecond: Long = 0L,
        allowPromotion: Boolean = true
    ): Notification {
        ensureChannel()
        val text = localizedText()

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val detailText = buildString {
            append("↓")
            append(NetworkSpeedFormatter.formatCompact(sample.downloadBytesPerSecond))
            append("  ↑")
            append(NetworkSpeedFormatter.formatCompact(sample.uploadBytesPerSecond))
        }
        val shouldPromote =
            allowPromotion && sample.totalBytesPerSecond >= minPromotedBytesPerSecond.coerceAtLeast(0L)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_speed)
            .setContentTitle(text.notificationTitle)
            .setContentText(detailText)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setLocalOnly(WearOsLiveUpdatesPolicy.isLocalOnly(
                Build.VERSION.SDK_INT, ConverterPrefs(context).getWearOsLiveUpdatesEnabled()
            ))
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (shouldPromote) {
            builder
                .setShortCriticalText(NetworkSpeedFormatter.formatCompact(sample.totalBytesPerSecond))
                .setRequestPromotedOngoing(true)
        }

        return builder.build()
    }

    private fun localizedText() = LocalizedText(
        notificationTitle = NativeAppStrings.text(context, "Network speed", "Скорость сети", "Velocidad de red", "Netzwerkgeschwindigkeit"),
        channelName = NativeAppStrings.text(context, "Network speed monitor", "Монитор скорости сети", "Monitor de velocidad de red", "Netzwerkgeschwindigkeitsmonitor"),
        channelDescription = NativeAppStrings.text(context, "Shows current network speed in the status bar", "Показывает текущую скорость сети в статус-баре", "Muestra la velocidad de red actual en la barra de estado", "Zeigt die aktuelle Netzwerkgeschwindigkeit in der Statusleiste an")
    )

    private data class LocalizedText(
        val notificationTitle: String,
        val channelName: String,
        val channelDescription: String
    )

    companion object {
        const val CHANNEL_ID = "livebridge_network_speed"
    }
}
