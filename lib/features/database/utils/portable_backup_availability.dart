import '../../../core/config/app_config.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';

/// Διαθεσιμότητα portable πόρων για switches αντιγράφου ασφαλείας.
class PortableBackupAvailability {
  const PortableBackupAvailability({
    required this.hasMapImages,
    required this.hasToolImages,
    required this.hasLoadedLexicon,
    required this.hasLampDbInPortableDataBase,
  });

  final bool hasMapImages;
  final bool hasToolImages;
  final bool hasLoadedLexicon;
  final bool hasLampDbInPortableDataBase;

  static Future<PortableBackupAvailability> load({
    required bool lexiconLoaded,
  }) async {
    final mapFiles = await BuildingMapStorage.listPortableImageFiles();
    final toolImages = await PortableToolImageStorage.portableImagesFolderHasFiles();
    final lampDb = await PortableLampStorage.lampReadDbExistsInPortableDataBase();
    return PortableBackupAvailability(
      hasMapImages: mapFiles.isNotEmpty,
      hasToolImages: toolImages,
      hasLoadedLexicon: lexiconLoaded,
      hasLampDbInPortableDataBase: lampDb,
    );
  }

  static String mapsImagesSubtitle() =>
      'Zip με call_logger.db και φάκελο ${AppConfig.portableMapsDirName} '
      '(στη ρίζα εφαρμογής)';
}
