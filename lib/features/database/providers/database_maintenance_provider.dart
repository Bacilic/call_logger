import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_maintenance_service.dart';

final databaseMaintenanceServiceProvider = Provider<DatabaseMaintenanceService>(
  (ref) => DatabaseMaintenanceService(),
);
