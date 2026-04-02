package de.healthvault.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.healthvault.data.model.Vital
import de.healthvault.data.repository.VitalsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn
import org.koin.compose.viewmodel.koinViewModel
import org.koin.core.parameter.parametersOf

// ── State ────────────────────────────────────────────────────────────────────

data class VitalsUiState(
    val vitals: List<Vital> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val showAddDialog: Boolean = false,
)

// ── ViewModel ────────────────────────────────────────────────────────────────

class VitalsViewModel(
    private val profileId: String,
    private val repo: VitalsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(VitalsUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = repo.list(profileId)
                _state.value = _state.value.copy(vitals = response.items, isLoading = false)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Failed to load vitals")
            }
        }
    }

    fun showAddDialog() { _state.value = _state.value.copy(showAddDialog = true) }
    fun hideAddDialog() { _state.value = _state.value.copy(showAddDialog = false) }

    fun addVital(vital: Vital) {
        viewModelScope.launch {
            try {
                repo.create(profileId, vital)
                hideAddDialog()
                load()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message ?: "Failed to add vital")
            }
        }
    }

    fun deleteVital(id: String) {
        viewModelScope.launch {
            try {
                repo.delete(profileId, id)
                load()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message ?: "Failed to delete vital")
            }
        }
    }
}

// ── Screen ───────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VitalsScreen(
    profileId: String,
    onBack: () -> Unit,
    viewModel: VitalsViewModel = koinViewModel(parameters = { parametersOf(profileId) }),
) {
    val state by viewModel.state.collectAsState()

    if (state.showAddDialog) {
        AddVitalDialog(
            onDismiss = viewModel::hideAddDialog,
            onConfirm = viewModel::addVital,
            profileId = profileId,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vitals") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = viewModel::showAddDialog) {
                Icon(Icons.Default.Add, contentDescription = "Add vital")
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isLoading,
            onRefresh = viewModel::load,
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            if (state.error != null) {
                Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
                )
            }
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(state.vitals, key = { it.id }) { vital ->
                    VitalCard(vital = vital)
                }
            }
        }
    }
}

// ── Card ─────────────────────────────────────────────────────────────────────

@Composable
private fun VitalCard(vital: Vital) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(vital.measuredAt.take(10), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (vital.bloodPressureSystolic != null && vital.bloodPressureDiastolic != null)
                VitalRow("Blood Pressure", "${vital.bloodPressureSystolic.toInt()}/${vital.bloodPressureDiastolic.toInt()} mmHg")
            if (vital.pulse != null)
                VitalRow("Pulse", "${vital.pulse.toInt()} bpm")
            if (vital.weight != null)
                VitalRow("Weight", "${vital.weight} kg")
            if (vital.bodyTemperature != null)
                VitalRow("Temperature", "${vital.bodyTemperature} °C")
            if (vital.oxygenSaturation != null)
                VitalRow("SpO2", "${vital.oxygenSaturation.toInt()} %")
            if (vital.bloodGlucose != null)
                VitalRow("Glucose", "${vital.bloodGlucose} mmol/L")
            if (vital.notes != null)
                Text(vital.notes, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun VitalRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall)
    }
}

// ── Add Dialog ───────────────────────────────────────────────────────────────

@Composable
private fun AddVitalDialog(onDismiss: () -> Unit, onConfirm: (Vital) -> Unit, profileId: String) {
    var systolic   by remember { mutableStateOf("") }
    var diastolic  by remember { mutableStateOf("") }
    var pulse      by remember { mutableStateOf("") }
    var weight     by remember { mutableStateOf("") }
    var temp       by remember { mutableStateOf("") }
    var spo2       by remember { mutableStateOf("") }
    var glucose    by remember { mutableStateOf("") }
    var notes      by remember { mutableStateOf("") }

    val numOpts = KeyboardOptions(keyboardType = KeyboardType.Decimal)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Vital Measurement") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(systolic,  { systolic = it },  label = { Text("Systolic") },
                        keyboardOptions = numOpts, modifier = Modifier.weight(1f))
                    OutlinedTextField(diastolic, { diastolic = it }, label = { Text("Diastolic") },
                        keyboardOptions = numOpts, modifier = Modifier.weight(1f))
                }
                OutlinedTextField(pulse,   { pulse = it },   label = { Text("Pulse (bpm)") },
                    keyboardOptions = numOpts, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(weight,  { weight = it },  label = { Text("Weight (kg)") },
                    keyboardOptions = numOpts, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(temp,    { temp = it },    label = { Text("Temperature (°C)") },
                    keyboardOptions = numOpts, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(spo2,    { spo2 = it },    label = { Text("SpO2 (%)") },
                    keyboardOptions = numOpts, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(glucose, { glucose = it }, label = { Text("Glucose (mmol/L)") },
                    keyboardOptions = numOpts, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(notes,   { notes = it },   label = { Text("Notes") },
                    modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            val today = Clock.System.todayIn(TimeZone.currentSystemDefault()).toString()
            TextButton(onClick = {
                onConfirm(
                    Vital(
                        id = "",
                        profileId = profileId,
                        measuredAt = today,
                        bloodPressureSystolic  = systolic.toDoubleOrNull(),
                        bloodPressureDiastolic = diastolic.toDoubleOrNull(),
                        pulse          = pulse.toDoubleOrNull(),
                        weight         = weight.toDoubleOrNull(),
                        bodyTemperature  = temp.toDoubleOrNull(),
                        oxygenSaturation = spo2.toDoubleOrNull(),
                        bloodGlucose   = glucose.toDoubleOrNull(),
                        notes = notes.ifBlank { null },
                    )
                )
            }) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
