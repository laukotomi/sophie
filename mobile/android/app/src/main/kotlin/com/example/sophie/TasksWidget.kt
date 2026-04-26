package com.example.sophie

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.actionStartActivity as actionStartActivityWithIntent
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import org.json.JSONArray
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

private val BackgroundColor = ColorProvider(Color(0xFF1E1E2E))
private val TextPrimary = ColorProvider(Color(0xFFCDD6F4))
private val TextMuted = ColorProvider(Color(0xFF6C7086))
private val AccentColor = ColorProvider(Color(0xFF89B4FA))

data class TaskItem(val id: String, val text: String, val dueAt: LocalDateTime?)

private val isoFormatter = DateTimeFormatter.ISO_LOCAL_DATE_TIME
private val timeFormatter = DateTimeFormatter.ofPattern("HH:mm")
private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

private fun formatDue(dueAt: LocalDateTime?): String {
    if (dueAt == null) return ""
    val today = LocalDate.now()
    return if (dueAt.toLocalDate() == today) {
        "Today ${dueAt.format(timeFormatter)}"
    } else {
        "${dueAt.format(dateFormatter)} ${dueAt.format(timeFormatter)}"
    }
}

class TasksWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val tasks = loadPendingTasks(context)
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            data = Uri.parse("sophie://widget/tasks")
            putExtra("homeWidgetIsWidgetClick", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val launchAction = actionStartActivityWithIntent(launchIntent)

        provideContent {
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(BackgroundColor)
                    .clickable(launchAction)
                    .padding(12.dp),
            ) {
                Text(
                    text = "Sophie Tasks",
                    style = TextStyle(
                        color = TextPrimary,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    modifier = GlanceModifier.padding(bottom = 8.dp),
                )
                if (tasks.isEmpty()) {
                    Text(
                        text = "No pending tasks",
                        style = TextStyle(color = TextMuted, fontSize = 13.sp),
                    )
                } else {
                    LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                        items(tasks) { task ->
                            Row(
                                modifier = GlanceModifier
                                    .fillMaxWidth()
                                    .clickable(launchAction)
                                    .padding(top = 4.dp, bottom = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Spacer(
                                    modifier = GlanceModifier
                                        .width(6.dp)
                                        .height(6.dp)
                                        .background(AccentColor),
                                )
                                Column(
                                    modifier = GlanceModifier
                                        .padding(start = 8.dp)
                                        .defaultWeight(),
                                ) {
                                    Text(
                                        text = task.text,
                                        style = TextStyle(color = TextPrimary, fontSize = 13.sp),
                                        maxLines = 2,
                                    )
                                    val due = formatDue(task.dueAt)
                                    if (due.isNotEmpty()) {
                                        Text(
                                            text = due,
                                            style = TextStyle(color = TextMuted, fontSize = 11.sp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun loadPendingTasks(context: Context): List<TaskItem> {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("tasks_json", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            List(arr.length()) { i ->
                val obj = arr.getJSONObject(i)
                val dueAtStr = if (obj.isNull("dueAt")) null else obj.getString("dueAt")
                val dueAt = dueAtStr?.let {
                    // ISO string from Dart may have fractional seconds; trim to seconds
                    LocalDateTime.parse(it.substringBefore(".").trimEnd('Z'), isoFormatter)
                }
                TaskItem(id = obj.getString("id"), text = obj.getString("text"), dueAt = dueAt)
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
