package de.healthvault

import android.app.Application
import de.healthvault.data.api.ApiClient
import de.healthvault.di.appModule
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.startKoin

class HealthVaultApp : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidContext(this@HealthVaultApp)
            modules(appModule)
        }
    }
}
