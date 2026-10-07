package com.appsfolder.livebridge.liveupdate

import java.util.Locale

internal object AppUiLanguage {
    fun resolve(preference: String, systemLanguage: String): String {
        val tag = preference.trim().ifBlank { "system" }
        return (if (tag.equals("system", ignoreCase = true)) systemLanguage else tag)
            .replace('_', '-').substringBefore('-').lowercase(Locale.ROOT)
    }
}
