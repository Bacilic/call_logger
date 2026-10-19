import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';

/// Διαθεσιμότητα portable πόρων για switches αντιγράφου ασφαλείας.
class PortableBackupAvailability {
  const PortableBackupAvailability({
    required this.hasToolImages,
    required this.hasLoadedLexicon,
    required this.hasLampDbInPortableDataBase,
  });

  final bool hasToolImages;
  final bool hasLoadedLexicon;
  final bool hasLampDbInPortableDataBase;

  static Future<PortableBackupAvailability> load({
    required bool lexiconLoaded,
  }) async {
    final toolImages =
        await PortableToolImageStorage.portableImagesFolderHasFiles();
    final lampDb =
        await PortableLampStorage.lampReadDbExistsInPortableDataBase();
    return PortableBackupAvailability(
      hasToolImages: toolImages,
      hasLoadedLexicon: lexiconLoaded,
      hasLampDbInPortableDataBase: lampDb,
    );
  }
}
