import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hocalist/main.dart' as app;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/seller/seller_bottom_navigation.dart';
import 'package:hocalist/features/seller/approved_seller_store_page.dart';
import 'package:hocalist/features/seller/approved_seller_meets_page.dart';
import 'package:hocalist/features/seller/approved_seller_chats_page.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/features/account/push_service_scope.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:hocalist/features/media/photo_bytes.dart';
import 'package:hocalist/data/phase2/media/image_gateway.dart';
import 'package:hocalist/data/phase2/avatars/profile_avatar_backend.dart';

// Explicit live test-account journey. A fresh email callback is delivered by
// the external device driver; no credentials are compiled into this harness.
void main() {
  const role = String.fromEnvironment(
    'NATIVE_TEST_ROLE',
    defaultValue: 'seller',
  );
  const checkPush = bool.fromEnvironment('NATIVE_TEST_PUSH');
  const waitForDelivery = bool.fromEnvironment('NATIVE_TEST_PUSH_DELIVERY');
  const checkMedia = bool.fromEnvironment('NATIVE_TEST_MEDIA');
  const systemGallery = bool.fromEnvironment('NATIVE_TEST_SYSTEM_GALLERY');
  const systemCamera = bool.fromEnvironment('NATIVE_TEST_SYSTEM_CAMERA');
  const checkNavigation = bool.fromEnvironment('NATIVE_TEST_NAVIGATION');
  const backgroundPush = bool.fromEnvironment('NATIVE_TEST_BACKGROUND_PUSH');
  const trayTap = bool.fromEnvironment('NATIVE_TEST_TRAY_TAP');
  const prepareColdStart = bool.fromEnvironment('NATIVE_TEST_PREPARE_COLD_START');
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native $role email callback reaches the real dashboard', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('hocalist.auth.selected_role', role);
    app.main();
    final login = find.byKey(ValueKey('real-account-$role'));
    final startupDeadline = DateTime.now().add(const Duration(seconds: 45));
    while (login.evaluate().isEmpty &&
        DateTime.now().isBefore(startupDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(login, findsOneWidget);
    debugPrint('NATIVE_TEST_WAITING_FOR_AUTH');
    final dashboard = role == 'seller'
        ? find.byKey(const Key('sellerHomeScroll'))
        : find.byType(ApprovedBuyerHomePage);
    final authDeadline = DateTime.now().add(const Duration(seconds: 120));
    while (dashboard.evaluate().isEmpty &&
        DateTime.now().isBefore(authDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(dashboard, findsOneWidget);
    expect(
      Supabase.instance.client.auth.currentUser?.email,
      'adepojudolapoo+hocalist-flow-$role-20260927@gmail.com',
    );
    if (checkNavigation && role == 'buyer') {
      Future<void> open(String label) async {
        final item = find.descendant(
          of: find.byType(BuyerBottomNavigation),
          matching: find.text(label),
        );
        expect(item, findsOneWidget);
        await tester.tap(item);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }

      await open('Offers');
      expect(find.byType(ApprovedOffersReceivedPage), findsOneWidget);
      await open('Chats');
      expect(find.byType(app.BuyerChatsPage), findsOneWidget);
      await open('More');
      expect(find.byType(BuyerBottomNavigation), findsOneWidget);
      await open('Home');
      expect(find.byType(ApprovedBuyerHomePage), findsOneWidget);
      debugPrint('NATIVE_BUYER_NAVIGATION_PASSED');
    }
    if (checkNavigation && role == 'seller') {
      Future<void> open(String label, Finder destination) async {
        final item = find.descendant(
          of: find.byType(SellerBottomNavigation),
          matching: find.text(label),
        );
        expect(item, findsOneWidget);
        await tester.tap(item);
        await tester.pump(const Duration(seconds: 2));
        expect(destination, findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await open('Store', find.byType(ApprovedSellerStorePage));
      await open('Meets', find.byType(ApprovedSellerMeetsPage));
      await open('Chats', find.byType(ApprovedSellerChatsPage));
      await open('More', find.byType(ApprovedSellerMorePage));
      await open('Home', find.byKey(const Key('sellerHomeScroll')));
      debugPrint('NATIVE_SELLER_NAVIGATION_PASSED');
    }
    if (checkMedia) {
      final client = Supabase.instance.client;
      final membership = await client
          .schema('hocalist')
          .from('memberships')
          .select('id')
          .eq('user_id', client.auth.currentUser!.id)
          .eq('role', role)
          .single();
      final avatars = createConfiguredProfileAvatarBackend(enabled: true)!;
      final original = await avatars.loadMemberAvatar(
        membership['id'] as String,
      );
      final synthetic = img.Image(width: 96, height: 96);
      img.fill(synthetic, color: img.ColorRgb8(64, 92, 180));
      var input = img.encodePng(synthetic);
      if (systemGallery || systemCamera) {
        debugPrint(
          systemCamera
              ? 'NATIVE_TEST_WAITING_FOR_SYSTEM_CAMERA'
              : 'NATIVE_TEST_WAITING_FOR_SYSTEM_GALLERY',
        );
        final selected = await ImagePicker().pickImage(
          source: systemCamera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        expect(selected, isNotNull);
        input = await selected!.readAsBytes();
        expect(img.decodeImage(input), isNotNull);
        debugPrint(
          systemCamera
              ? 'NATIVE_TEST_SYSTEM_CAMERA_RETURNED_PHOTO'
              : 'NATIVE_TEST_SYSTEM_GALLERY_RETURNED_PHOTO',
        );
      }
      final bytes = preparePrivatePhoto(input);
      final gateway = ImageGateway(client);
      final key = newMediaUploadKey();
      final mediaId = await gateway.upload(bytes, key, 'profile');
      expect(await gateway.upload(bytes, key, 'profile'), mediaId);
      expect(img.decodeJpg(await gateway.read(mediaId)), isNotNull);
      var changed = false;
      try {
        await avatars.updateAvatar(
          role: role,
          operationKey: newMediaUploadKey(),
          expectedRevision: original.revision,
          mediaId: mediaId,
        );
        changed = true;
        final reopened = await avatars.loadMemberAvatar(original.membershipId);
        expect(reopened.imageMediaId, mediaId);
        expect(
          img.decodeJpg(await gateway.read(reopened.imageMediaId!)),
          isNotNull,
        );
        debugPrint('NATIVE_TEST_MEDIA_UPLOAD_REPLAY_READ_AND_AVATAR_REOPENED');
      } finally {
        if (changed) {
          final current = await avatars.loadMemberAvatar(original.membershipId);
          await avatars.updateAvatar(
            role: role,
            operationKey: newMediaUploadKey(),
            expectedRevision: current.revision,
            mediaId: original.imageMediaId,
          );
          expect(
            (await avatars.loadMemberAvatar(
              original.membershipId,
            )).imageMediaId,
            original.imageMediaId,
          );
          debugPrint('NATIVE_TEST_ORIGINAL_AVATAR_RESTORED');
        }
      }
    }
    if (checkPush) {
      final service = PushServiceScope.read(tester.element(dashboard));
      expect(service, isNotNull);
      final delivery = waitForDelivery
          ? FirebaseMessaging.onMessage.first.timeout(
              const Duration(seconds: 120),
            )
          : null;
      try {
        await service!.start();
        await service.enable().timeout(const Duration(seconds: 30));
        expect(await service.isEnabled(), isTrue);
        debugPrint('NATIVE_TEST_DEVICE_REGISTERED');
        if (prepareColdStart) {
          // Explicit isolated-device setup only. The external driver restores
          // the normal entry point, tests process-death delivery, then disables
          // this installation. Run with --no-uninstall to retain its session.
          debugPrint('NATIVE_TEST_COLD_START_PREPARED');
          return;
        }
        if (backgroundPush) {
          // Driver backgrounds the app. NATIVE_TEST_TRAY_TAP requires an
          // actual system-tray tap and conversation route, not SDK relaunch.
          var leftForeground = false;
          final deadline = DateTime.now().add(const Duration(seconds: 150));
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 250));
            final state = WidgetsBinding.instance.lifecycleState;
            if (state != AppLifecycleState.resumed) leftForeground = true;
            if (leftForeground && state == AppLifecycleState.resumed) break;
          }
          expect(leftForeground, isTrue);
          expect(
            WidgetsBinding.instance.lifecycleState,
            AppLifecycleState.resumed,
          );
          final rows = await Supabase.instance.client
              .schema('hocalist')
              .from('notifications')
              .select('id')
              .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
              .order('created_at', ascending: false)
              .limit(1);
          expect(rows, isNotEmpty);
          expect(
            await service.fetchNotification(rows.first['id'] as String),
            isNotNull,
          );
          debugPrint('NATIVE_TEST_BACKGROUND_RESUME_AND_LOOKUP_PASSED');
          if (trayTap) {
            final routeDeadline = DateTime.now().add(
              const Duration(seconds: 30),
            );
            while (find.byType(ApprovedBuyerChatPage).evaluate().isEmpty &&
                DateTime.now().isBefore(routeDeadline)) {
              await tester.pump(const Duration(milliseconds: 250));
            }
            expect(find.byType(ApprovedBuyerChatPage), findsOneWidget);
            debugPrint('NATIVE_TEST_TRAY_TAP_OPENED_BUYER_CONVERSATION');
          }
        }
        if (delivery != null) {
          final message = await delivery;
          final id = message.data['notification_id'];
          expect(id, isA<String>());
          final notification = await service.fetchNotification(id as String);
          expect(notification, isNotNull);
          expect(
            notification!['user_id'],
            Supabase.instance.client.auth.currentUser!.id,
          );
          debugPrint('NATIVE_TEST_PUSH_RECEIVED_AND_AUTHORIZED');
        }
      } finally {
        if (!prepareColdStart) await service!.disableConsent();
      }
      expect(await service.isEnabled(), isFalse);
      debugPrint('NATIVE_TEST_DEVICE_DISABLED');
    }
    expect(tester.takeException(), isNull);
  });
}
