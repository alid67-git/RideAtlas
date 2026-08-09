import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/route_photo.dart';

/// A gallery photo/video found within a just-finished recording's time
/// window, offered to the rider so they can attach any they took mid-ride
/// (see RidePhotoPickerScreen) without hunting through their whole gallery
/// by hand.
class GalleryCandidate {
  const GalleryCandidate(this.asset);

  final AssetEntity asset;

  RouteMediaType get mediaType =>
      asset.type == AssetType.video ? RouteMediaType.video : RouteMediaType.photo;
}

/// Looks for photos/videos the device's gallery gained between [start] and
/// [end]. Returns an empty list on any unsupported platform, on permission
/// refusal, or if nothing was found in that window - all silent, since this
/// is an optional nice-to-have prompt after finishing a ride, not something
/// that should ever block or nag.
Future<List<GalleryCandidate>> findGalleryMediaBetween(
  DateTime start,
  DateTime end,
) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return const [];

  final permission = await PhotoManager.requestPermissionExtend();
  if (!permission.hasAccess) return const [];

  final paths = await PhotoManager.getAssetPathList(
    onlyAll: true,
    type: RequestType.common,
    filterOption: FilterOptionGroup(
      createTimeCond: DateTimeCond(min: start, max: end),
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
    ),
  );
  if (paths.isEmpty) return const [];

  final all = paths.first;
  final count = await all.assetCountAsync;
  if (count == 0) return const [];

  final assets = await all.getAssetListRange(start: 0, end: count);
  return assets.map(GalleryCandidate.new).toList();
}
