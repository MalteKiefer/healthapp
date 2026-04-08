class Allergy {
  final String id;
  final String allergen;
  final String? reaction;
  final String? severity;
  final String? category;
  final String? onsetDate;
  final String? diagnosedAt;
  final String? diagnosedBy;
  final String? status;
  final String? notes;
  final String? orderedBy;

  Allergy({
    required this.id,
    required this.allergen,
    this.reaction,
    this.severity,
    this.category,
    this.onsetDate,
    this.diagnosedAt,
    this.diagnosedBy,
    this.status,
    this.notes,
    this.orderedBy,
  });

  factory Allergy.fromJson(Map<String, dynamic> json) => Allergy(
        id: json['id'] as String? ?? '',
        allergen: json['allergen'] as String? ?? '',
        reaction: json['reaction'],
        severity: json['severity'],
        category: json['category'],
        onsetDate: json['onset_date'],
        diagnosedAt: json['diagnosed_at'],
        diagnosedBy: json['diagnosed_by'],
        status: json['status'],
        notes: json['notes'],
        orderedBy: json['ordered_by'],
      );
}

class Diagnosis {
  final String id;
  final String name;
  final String? icdCode;
  final String? status;
  final String? diagnosedAt;
  final String? resolvedAt;
  final String? diagnosedBy;
  final String? notes;

  Diagnosis({
    required this.id,
    required this.name,
    this.icdCode,
    this.status,
    this.diagnosedAt,
    this.resolvedAt,
    this.diagnosedBy,
    this.notes,
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icdCode: json['icd_code'],
        status: json['status'],
        diagnosedAt: json['diagnosed_at'],
        resolvedAt: json['resolved_at'],
        diagnosedBy: json['diagnosed_by'],
        notes: json['notes'],
      );
}

class Vaccination {
  final String id;
  final String vaccine;
  final String? dose;
  final String? administeredAt;
  final String? nextDueAt;
  final String? batchNumber;
  final String? tradeName;
  final String? manufacturer;
  final int? doseNumber;
  final String? site;
  final String? notes;
  final String? administeredBy;

  Vaccination({
    required this.id,
    required this.vaccine,
    this.dose,
    this.administeredAt,
    this.nextDueAt,
    this.batchNumber,
    this.tradeName,
    this.manufacturer,
    this.doseNumber,
    this.site,
    this.notes,
    this.administeredBy,
  });

  factory Vaccination.fromJson(Map<String, dynamic> json) => Vaccination(
        id: json['id'] as String? ?? '',
        vaccine: json['vaccine'] as String? ?? '',
        dose: json['dose'],
        administeredAt: json['administered_at'],
        nextDueAt: json['next_due_at'],
        batchNumber: json['batch_number'],
        tradeName: json['trade_name'],
        manufacturer: json['manufacturer'],
        doseNumber: (json['dose_number'] as num?)?.toInt(),
        site: json['site'],
        notes: json['notes'],
        administeredBy: json['administered_by'],
      );
}

class Appointment {
  final String id;
  final String title;
  final String scheduledAt;
  final String? appointmentType;
  final int? durationMinutes;
  final String? doctorId;
  final String? location;
  final String? preparationNotes;
  final String? status;
  final String? recurrence;
  final List<int>? reminderDaysBefore;

  Appointment({
    required this.id,
    required this.title,
    required this.scheduledAt,
    this.appointmentType,
    this.durationMinutes,
    this.doctorId,
    this.location,
    this.preparationNotes,
    this.status,
    this.recurrence,
    this.reminderDaysBefore,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        scheduledAt: json['scheduled_at'] as String? ?? '',
        appointmentType: json['appointment_type'],
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
        doctorId: json['doctor_id'],
        location: json['location'],
        preparationNotes: json['preparation_notes'],
        status: json['status'],
        recurrence: json['recurrence'],
        reminderDaysBefore: (json['reminder_days_before'] as List?)
            ?.map((e) => e as int)
            .toList(),
      );
}

class Contact {
  final String id;
  final String name;
  final String? contactType;
  final String? specialty;
  final String? facility;
  final String? phone;
  final String? email;
  final String? address;
  final String? country;
  final String? notes;
  final bool isEmergencyContact;

  Contact({
    required this.id,
    required this.name,
    this.contactType,
    this.specialty,
    this.facility,
    this.phone,
    this.email,
    this.address,
    this.country,
    this.notes,
    this.isEmergencyContact = false,
  });

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        contactType: json['contact_type'],
        specialty: json['specialty'],
        facility: json['facility'],
        phone: json['phone'],
        email: json['email'],
        address: json['address'],
        country: json['country'],
        notes: json['notes'],
        isEmergencyContact: json['is_emergency_contact'] ?? false,
      );
}

class Task {
  final String id;
  final String title;
  final String? description;
  final String? dueAt;
  final bool completed;
  final String? completedAt;
  final String? priority;
  final String? status;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.dueAt,
    this.completed = false,
    this.completedAt,
    this.priority,
    this.status,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'],
        dueAt: json['due_at'],
        completed: json['completed'] ?? false,
        completedAt: json['completed_at'],
        priority: json['priority'],
        status: json['status'],
      );
}

class DiaryEvent {
  final String id;
  final String recordedAt;
  final String? title;
  final String? eventType;
  final String? mood;
  final int? moodScore;
  final String? content;
  final String? tags;
  final String? sleepHours;
  final String? startedAt;
  final String? endedAt;
  final int? severity;
  final String? location;
  final String? outcome;

  DiaryEvent({
    required this.id,
    required this.recordedAt,
    this.title,
    this.eventType,
    this.mood,
    this.moodScore,
    this.content,
    this.tags,
    this.sleepHours,
    this.startedAt,
    this.endedAt,
    this.severity,
    this.location,
    this.outcome,
  });

  factory DiaryEvent.fromJson(Map<String, dynamic> json) => DiaryEvent(
        id: json['id'] as String? ?? '',
        recordedAt: json['recorded_at'] as String? ?? '',
        title: json['title'],
        eventType: json['event_type'],
        mood: json['mood'],
        moodScore: (json['mood_score'] as num?)?.toInt(),
        content: json['content'],
        tags: json['tags'],
        sleepHours: json['sleep_hours'],
        startedAt: json['started_at'],
        endedAt: json['ended_at'],
        severity: (json['severity'] as num?)?.toInt(),
        location: json['location'],
        outcome: json['outcome'],
      );
}

class Symptom {
  final String id;
  final String name;
  final String? recordedAt;
  final String? severity;
  final String? duration;
  final String? notes;
  final bool isOngoing;
  final String? triggerFactors;
  final String? symptomType;
  final String? bodyRegion;
  final int? durationMinutes;

  Symptom({
    required this.id,
    required this.name,
    this.recordedAt,
    this.severity,
    this.duration,
    this.notes,
    this.isOngoing = false,
    this.triggerFactors,
    this.symptomType,
    this.bodyRegion,
    this.durationMinutes,
  });

  factory Symptom.fromJson(Map<String, dynamic> json) => Symptom(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        recordedAt: json['recorded_at'],
        severity: json['severity'],
        duration: json['duration'],
        notes: json['notes'],
        isOngoing: json['is_ongoing'] ?? false,
        triggerFactors: json['trigger_factors'] is List
            ? (json['trigger_factors'] as List).join(', ')
            : json['trigger_factors'] as String?,
        symptomType: json['symptom_type'],
        bodyRegion: json['body_region'],
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      );
}

class Document {
  final String id;
  final String filename;
  final String? category;
  final String? mimeType;
  final int? fileSize;
  final String? uploadedAt;
  final String? notes;
  final String? tags;

  Document({
    required this.id,
    required this.filename,
    this.category,
    this.mimeType,
    this.fileSize,
    this.uploadedAt,
    this.notes,
    this.tags,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] as String? ?? '',
        filename: json['filename_enc'] ??
            json['filename'] ??
            json['file_name'] ??
            'Untitled',
        category: json['category'],
        mimeType: json['mime_type'],
        fileSize: (json['file_size'] as num?)?.toInt(),
        uploadedAt: json['uploaded_at'] ?? json['created_at'],
        notes: json['notes'],
        tags: json['tags'] is List
            ? (json['tags'] as List).join(', ')
            : json['tags'] as String?,
      );
}
