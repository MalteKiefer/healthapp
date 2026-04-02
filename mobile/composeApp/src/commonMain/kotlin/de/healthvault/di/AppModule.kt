package de.healthvault.di

import de.healthvault.data.repository.*
import de.healthvault.ui.screens.*
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val appModule = module {
    // Repositories
    single { AuthRepository() }
    single { ProfileRepository() }
    single { VitalsRepository() }
    single { LabsRepository() }
    single { MedicationsRepository() }
    single { HealthDataRepository() }

    // ViewModels
    viewModel { LoginViewModel(get()) }
    viewModel { HomeViewModel(get()) }
    viewModel { params -> VitalsViewModel(params.get(), get()) }
    viewModel { params -> LabsViewModel(params.get(), get()) }
    viewModel { params -> MedicationsViewModel(params.get(), get()) }
}
