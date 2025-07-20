import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Initialize timezone database
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MediTrackRx());
}

class MediTrackRx extends StatefulWidget {
  const MediTrackRx({super.key});

  @override
  State<MediTrackRx> createState() => _MediTrackRxState();
}

class _MediTrackRxState extends State<MediTrackRx> {
  bool _isDarkMode = false;

  void _toggleDarkMode(bool value) {
    setState(() {
      _isDarkMode = value;
    });
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
      useMaterial3: true,
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'Sans',
      ),
      appBarTheme: AppBarTheme(
        titleTextStyle: TextStyle(
          fontFamily: 'Sans',
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
  return ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.lightBlue,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    textTheme: ThemeData.dark().textTheme.apply(
      fontFamily: 'Sans',
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      titleTextStyle: TextStyle(
        fontFamily: 'Sans',
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: Color(0xFF2C2C2C),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediTrack Rx',
      theme: _isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
      home: MediTrackHomePage(
        isDarkMode: _isDarkMode,
        onThemeChanged: _toggleDarkMode,
      ),
    );
  }
}

class MediTrackHomePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const MediTrackHomePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<MediTrackHomePage> createState() => _MediTrackHomePageState();
}

class _MediTrackHomePageState extends State<MediTrackHomePage> {
  int _selectedIndex = 0;
  final TextEditingController _patientNameController = TextEditingController();
  String? _selectedMedicine;
  TimeOfDay? _intakeTime;
  final List<Map<String, String>> _schedule = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  Timer? _reminderTimer;
  List<String> _shownReminders = [];

  @override
  void initState() {
    super.initState();
    _startReminderChecker();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  void _startReminderChecker() {
    _reminderTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkReminders());
    _checkReminders(); // Also check immediately on startup
  }

  Future<void> _checkReminders() async {
    final now = getManilaNow();
    final today = now;
    final patientsSnapshot = await FirebaseFirestore.instance.collection('patients').get();

    for (var doc in patientsSnapshot.docs) {
      final data = doc.data();
      final patientName = data['name'] ?? '';
      final schedule = (data['schedule'] as List<dynamic>?) ?? [];

      for (var item in schedule) {
        final medicine = item['medicine'] ?? '';
        final timeStr = item['time'] ?? '';
        final scheduledTime = _parseTimeOfDay(timeStr);

        if (scheduledTime != null) {
          final scheduledDateTime = DateTime(
            today.year, today.month, today.day, scheduledTime.hour, scheduledTime.minute);

          final diff = scheduledDateTime.difference(now).inMinutes;

          // Show reminder if exactly at the scheduled minute and not already shown
          final reminderId = '${doc.id}_$medicine\_$timeStr\_${today.toIso8601String().substring(0,10)}';
          if (diff == 0 && !_shownReminders.contains(reminderId)) {
            _shownReminders.add(reminderId);
            _showIntakeDialog(patientName, medicine, timeStr, reminderId);
          }
        }
      }
    }
  }

  TimeOfDay? _parseTimeOfDay(String timeStr) {
    try {
      final format = RegExp(r'(\d+):(\d+)\s*([AP]M)?', caseSensitive: false);
      final match = format.firstMatch(timeStr);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.parse(match.group(2)!);
        final ampm = match.group(3)?.toUpperCase();
        if (ampm == 'PM' && hour < 12) hour += 12;
        if (ampm == 'AM' && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return null;
  }

  void _showIntakeDialog(String patient, String medicine, String scheduledTime, String reminderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Now dialogContext is assigned before timer is created
        final dialogContext = ctx;
        Timer? autoMissTimer;

        autoMissTimer = Timer(const Duration(minutes: 2), () {
          // If the dialog is still open after 5 minutes, log as missed and close
          if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
            _logIntake(patient, medicine, scheduledTime, 'Missed');
          }
        });

        return AlertDialog(
          title: const Text('Medicine Reminder'),
          content: Text('$patient should take $medicine at $scheduledTime.\nMark as taken or missed?'),
          actions: [
            TextButton(
              onPressed: () {
                autoMissTimer?.cancel();
                _logIntake(patient, medicine, scheduledTime, 'Missed');
                Navigator.pop(dialogContext);
              },
              child: const Text('Missed', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                autoMissTimer?.cancel();
                _logIntake(patient, medicine, scheduledTime, 'Taken');
                Navigator.pop(dialogContext);
              },
              child: const Text('Taken'),
            ),
          ],
        );
      },
    ).then((_) {
      // Cancel timer if dialog is closed by any means
      // (Timer is already cancelled in button handlers, but this is a safe fallback)
    });
  }

  Future<void> _logIntake(String patient, String medicine, String scheduledTime, String status) async {
    await FirebaseFirestore.instance.collection('logs').add({
      'patient': patient,
      'medicine': medicine,
      'scheduled_time': scheduledTime,
      'timestamp': getManilaNow().toIso8601String(),
      'status': status,
    });
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _intakeTime = picked);
    }
  }

  void _addSchedule() {
    if (_selectedMedicine != null && _intakeTime != null) {
      setState(() {
        _schedule.add({
          'medicine': _selectedMedicine!,
          'time': _intakeTime!.format(context),
        });
        _selectedMedicine = null;
        _intakeTime = null;
      });
    }
  }

  Future<void> _saveMedicineToSlot(int slotNumber) async {
  final nameCtrl = TextEditingController();
  DateTime? pickedDate;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Add Medicine'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Medicine Name'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Pick Expiry Date'),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          pickedDate = date;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (pickedDate != null)
                    Text(
                      'Selected: ${DateFormat('yyyy-MM-dd').format(pickedDate!)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isNotEmpty && pickedDate != null) {
                    final formattedDate = DateFormat('yyyy-MM-dd').format(pickedDate!);
                    try {
                      await FirebaseFirestore.instance
                          .collection('medicines')
                          .doc('slot$slotNumber')
                          .set({
                        'name': nameCtrl.text,
                        'expiry': formattedDate,
                      });

                      Navigator.pop(ctx);

                      // Show confirmation SnackBar
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medicine added successfully')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving medicine: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}


  Widget _buildHeader() {
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.primary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Icon(Icons.medical_services, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'MediTrack Rx',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('medicines').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final Map<String, Map<String, String>> slots = {
          for (int i = 1; i <= 10; i++) 
            'slot$i': {'name': '', 'expiry': ''}
        };

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          slots[doc.id] = {
            'name': data['name']?.toString() ?? '',
            'expiry': data['expiry']?.toString() ?? ''
          };
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Medicine Inventory',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: 10,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final slotNumber = index + 1;
                    final slotKey = 'slot$slotNumber';
                    final slot = slots[slotKey]!;
                    final filled = slot['name']!.isNotEmpty;

                    return Card(
                      key: ValueKey(slotKey),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              alignment: Alignment.center,
                              child: Text(
                                '$slotNumber',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.teal,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    filled ? slot['name']! : 'Empty Slot',
                                    style: TextStyle(
                                      fontStyle: filled 
                                          ? FontStyle.normal 
                                          : FontStyle.italic,
                                      color: filled 
                                          ? Theme.of(context).textTheme.bodyLarge?.color 
                                          : Colors.grey,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (slot['expiry']!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Expiry: ${slot['expiry']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                textStyle: const TextStyle(fontSize: 14),
                              ),
                              onPressed: () => _saveMedicineToSlot(slotNumber),
                            ),
                            if (filled) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                                onPressed: () => _confirmDeleteMedicine(context, slotKey),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMedicine(BuildContext context, String slotKey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Medicine'),
        content: const Text('Are you sure you want to delete this medicine?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('medicines')
            .doc(slotKey)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medicine deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Widget _buildPatientSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _patientNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline),
              labelText: 'e.g., John Doe',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Schedule Medications', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('medicines').snapshots(),
            builder: (context, snapshot) {
              final validItems = snapshot.hasData
                  ? snapshot.data!.docs
                      .where((doc) => (doc.data()['name'] ?? '').toString().isNotEmpty)
                      .map((doc) => DropdownMenuItem<String>(
                          value: doc.data()['name'], child: Text(doc.data()['name'])))
                      .toList()
                  : <DropdownMenuItem<String>>[];

              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedMedicine,
                      items: validItems,
                      onChanged: (val) => setState(() => _selectedMedicine = val),
                      decoration: const InputDecoration(
                        labelText: 'Select a medicine',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(context),
                      icon: const Icon(Icons.access_time),
                      label: Text(_intakeTime?.format(context) ?? '--:--'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addSchedule,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Card(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  elevation: 2,
  child: Container(
    padding: const EdgeInsets.all(12),
    constraints: const BoxConstraints(maxHeight: 240),
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scheduled Medicines',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                  Colors.lightBlue,
                ),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Medicine')),
                  DataColumn(label: Text('Intake Time')),
                  DataColumn(label: Text('Action')),
                ],
                rows: _schedule.isNotEmpty
                    ? _schedule.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return DataRow(
                          cells: [
                            DataCell(Text(item['medicine']!)),
                            DataCell(Text(item['time']!)),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _schedule.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      }).toList()
                    : const [
                        DataRow(
                          cells: [
                            DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                            DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                            DataCell(Text('-')),
                          ],
                        ),
                      ],
              ),
            ),
          ),
        ),
      ],
    ),
  ),
),


          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              if (_patientNameController.text.isNotEmpty && _schedule.isNotEmpty) {
                await FirebaseFirestore.instance.collection('patients').add({
                  'name': _patientNameController.text,
                  'schedule': _schedule,
                });
                _patientNameController.clear();
                _schedule.clear();
                _selectedMedicine = null;
                _intakeTime = null;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Patient added.')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter name and at least one medicine.')));
              }
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Patient'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.lightBlue,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('patients').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Text('Loading patients...');
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Text('No patients added.');

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: docs.map((doc) {
                  final data = doc.data();
                  final name = data['name'] ?? '';
                  final schedule = (data['schedule'] as List<dynamic>?) ?? [];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text(name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: schedule
                            .map((s) =>
                                Text('- ${s['medicine']} at ${s['time']}'))
                            .toList()
                            .cast<Widget>(),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('patients')
                              .doc(doc.id)
                              .delete();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Patient deleted.')),
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Medicine Intake Logs',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: const Text('Clear Logs', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 14),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear All Logs'),
                      content: const Text('Are you sure you want to delete all logs? This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final logs = await FirebaseFirestore.instance.collection('logs').get();
                    for (var doc in logs.docs) {
                      await doc.reference.delete();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All logs cleared.')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('logs')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No logs available.'));
                }

                final logs = snapshot.data!.docs;

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final log = logs[index].data() as Map<String, dynamic>;
                    final status = log['status'] ?? 'Unknown';
                    final statusColor =
                        status == 'Taken' ? Colors.green : Colors.red;
                    final icon = status == 'Taken'
                        ? Icons.check_circle
                        : Icons.cancel;

                    final formattedTime = log['timestamp'] != null
                        ? DateFormat('yyyy-MM-dd').format(DateTime.parse(log['timestamp']))
                        : 'Unknown date';

                    return Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.15),
                          child: Icon(icon, color: statusColor),
                        ),
                        title: Text(
                          '${log['patient'] ?? 'Unknown'} took ${log['medicine'] ?? 'Unknown'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scheduled at: ${log['scheduled_time'] ?? '--:--'}'),
                            Text('Logged at: $formattedTime'),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            border: Border.all(color: statusColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.isDarkMode
                      ? [const Color(0xFF424242), const Color(0xFF212121)]
                      : [const Color(0xFF4FC3F7), const Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: DrawerHeader(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.medical_services,
                        color: widget.isDarkMode ? Colors.grey[800] : Colors.lightBlue,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'MediTrack Rx',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Medicine & Patient Manager',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: Theme.of(context).iconTheme.color),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutPage()),
                );
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Dark Mode'),
              secondary: Icon(
                widget.isDarkMode ? Icons.nightlight_round : Icons.wb_sunny,
                color: Theme.of(context).iconTheme.color,
              ),
              value: widget.isDarkMode,
              onChanged: widget.onThemeChanged,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.help_outline, color: Theme.of(context).iconTheme.color),
              title: const Text('Help & Support'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Help & Support'),
                    content: const Text('For support, contact: meditrackrx@example.com'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildMedicineSection(),
                _buildPatientSection(),
                _buildLogsSection(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: Colors.lightBlue,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medication),
            label: 'Medicines',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.lightBlue.shade100,
                    child: const Icon(Icons.medical_services, color: Colors.lightBlue, size: 40),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'MediTrack Rx',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.lightBlue,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A simple medicine and patient management app.\n\nDeveloped for Capstone Project.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.email, color: Colors.lightBlue, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'meditrackrx@example.com',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DateTime getManilaNow() {
  final manila = tz.getLocation('Asia/Manila');
  return tz.TZDateTime.now(manila);
}