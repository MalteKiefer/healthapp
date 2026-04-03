class Allergy {
  final String id;
  final String allergen;
  final String? reaction;
  final String? severity;
  final String? diagnosedAt;
  final String? notes;
  final String? orderedBy;

  Allergy({
    required this.id,
    required this.allergen,
    this.reaction,
    this.severity,
    this.diagnosedAt,
    this.notes,
    this.orderedBy,
  });

  factory Allergy.fromJson(Map<String, dynamic> json) => Allergy(
        id: json['id'],
        allergen: json['allergen'],
        reaction: json['reaction'],
        severity: json['severity'],
        diagnosedAt: json['diagnosed_at'],
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
  final String? notes;
  final String? diagnosedBy;

  Diagnosis({
    required this.id,
    required this.name,
    this.icdCode,
    this.status,
    this.diagnosedAt,
    this.resolvedAt,
    this.notes,
    this.diagnosedBy,
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
        id: json['id'],
        name: json['name'],
        icdCode: json['icd_code'],
        status: json['status'],
        diagnosedAt: json['diagnosed_at'],
        resolvedAt: json['resolved_at'],
        notes: json['notes'],
        diagnosedBy: json['diagnosed_by'],
      );
}

class Vaccination {
  final String id;
  final String vaccine;
  final String? dose;
  final String? administeredAt;
  final String? nextDueAt;
  final String? batchNumber;
  final String? notes;
  final String? administeredBy;

  Vaccination({
    required this.id,
    required this.vaccine,
    this.dose,
    this.administeredAt,
    this.nextDueAt,
    this.batchNumber,
    this.notes,
    this.administeredBy,
  });

  factory Vaccination.fromJson(Map<String, dynamic> json) => Vaccination(
        id: json['id'],
        vaccine: json['vaccine'],
        dose: json['dose'],
        administeredAt: json['administered_at'],
        nextDueAt: json['next_due_at'],
        batchNumber: json['batch_number'],
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
  });

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'],
        title: json['title'],
        scheduledAt: json['scheduled_at'] as String,
        appointmentType: json['appointment_type'],
        durationMinutes: json['duration_minutes'],
        doctorId: json['doctor_id'],
        location: json['location'],
        preparationNotes: json['preparation_notes'],
        status: json['status'],
        recurrence: json['recurrence'],
      );
}

class Contact {
  final String id;
  final String name;
  final String? specialty;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;

  Contact({
    required this.id,
    required this.name,
    this.specialty,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'],
        name: json['name'],
        specialty: json['specialty'],
        phone: json['phone'],
        email: json['email'],
        address: json['address'],
        notes: json['notes'],
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

  Task({
    required this.id,
    required this.title,
    this.description,
    this.dueAt,
    this.completed = false,
    this.completedAt,
    this.priority,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        dueAt: json['due_at'],
        completed: json['completed'] ?? false,
        completedAt: json['completed_at'],
        priority: json['priority'],
      );
}

class DiaryEvent {
  final String id;
  final String recordedAt;
  final String? mood;
  final int? moodScore;
  final String? content;
  final String? tags;
  final String? sleepHours;

  DiaryEvent({
    required this.id,
    required this.recordedAt,
    this.mood,
    this.moodScore,
    this.content,
    this.tags,
    this.sleepHours,
  });

  factory DiaryEvent.fromJson(Map<String, dynamic> json) => DiaryEvent(
        id: json['id'],
        recordedAt: json['recorded_at'],
        mood: json['mood'],
        moodScore: json['mood_score'],
        content: json['content'],
        tags: json['tags'],
        sleepHours: json['sleep_hours'],
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

  Symptom({
    required this.id,
    required this.name,
    this.recordedAt,
    this.severity,
    this.duration,
    this.notes,
    this.isOngoing = false,
  });

  factory Symptom.fromJson(Map<String, dynamic> json) => Symptom(
        id: json['id'],
        name: json['name'],
        recordedAt: json['recorded_at'],
        severity: json['severity'],
        duration: json['duration'],
        notes: json['notes'],
        isOngoing: json['is_ongoing'] ?? false,
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

  Document({
    required this.id,
    required this.filename,
    this.category,
    this.mimeType,
    this.fileSize,
    this.uploadedAt,
    this.notes,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'],
        filename: json['filename_enc'] ?? json['filename'] ?? json['file_name'] ?? 'Untitled',
        category: json['category'],
        mimeType: json['mime_type'],
        fileSize: json['file_size'],
        uploadedAt: json['uploaded_at'] ?? json['created_at'],
        notes: json['notes'],
      );
}
