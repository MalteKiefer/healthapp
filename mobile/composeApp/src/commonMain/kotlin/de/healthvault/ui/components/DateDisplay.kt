package de.healthvault.ui.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import kotlinx.datetime.LocalDate

@Composable
fun DateDisplay(
    isoDate: String,
    format: String = "dd.MM.yyyy",
    modifier: Modifier = Modifier,
) {
    val formatted = remember(isoDate, format) {
        runCatching {
            val date = LocalDate.parse(isoDate)
            format
                .replace("dd", date.dayOfMonth.toString().padStart(2, '0'))
                .replace("MM", date.monthNumber.toString().padStart(2, '0'))
                .replace("yyyy", date.year.toString())
        }.getOrElse { isoDate }
    }

    Text(
        text = formatted,
        style = MaterialTheme.typography.bodyMedium,
        modifier = modifier,
    )
}
